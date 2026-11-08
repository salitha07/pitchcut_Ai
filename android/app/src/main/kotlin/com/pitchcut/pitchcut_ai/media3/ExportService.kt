package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

internal fun deleteTemporaryOutput(file: File?): Boolean {
    if (file == null) return true
    return try {
        if (!file.exists() || file.delete()) {
            true
        } else {
            android.util.Log.e(
                "ExportService",
                "Failed to delete temporary export: ${file.absolutePath}"
            )
            false
        }
    } catch (error: Exception) {
        try {
            android.util.Log.e(
                "ExportService",
                "Failed to delete temporary export: ${file.absolutePath}",
                error
            )
        } catch (_: Exception) {}
        false
    }
}

/**
 * Service that exports a list of video clips (optionally with burned-in captions) to a single
 * output file using AndroidX Media3 Transformer.
 *
 * Caption burn-in is implemented via a [BitmapOverlay] that draws the active caption on each
 * video frame. Each caption is visible only while the frame's presentation time falls within
 * [Caption.startMs]..[Caption.endMs]. Multiple non-overlapping, back-to-back and overlapping
 * captions are all supported.
 *
 * Style: white text, semi-transparent black background (50%), positioned bottom-center, font
 * size scaled to 4.5% of the output frame height.
 *
 * Progress updates are emitted via [EventChannel.EventSink] as:
 *   `{ "progress": Float }` — 0.0 to 1.0
 *   `{ "progress": Float, "outputPath": String }` — final event on success
 * On cancellation an error event with code "CANCELLED" is emitted.
 */
@UnstableApi
class ExportService(private val context: Context) {

    companion object {
        /**
         * Caption font height as a fraction of the output frame height.
         * At 720p → about 32 px; at 1080p → about 49 px.
         * Increase this value to make captions larger on all resolutions simultaneously.
         */
        private const val CAPTION_FONT_RATIO = 0.045f
        private const val CAPTION_MAX_LINES = 3
        private const val CAPTION_MAX_FRAME_WIDTH_RATIO = 0.9f
        private const val CAPTION_BOTTOM_MARGIN_RATIO = 0.05f
    }

    interface Callback {
        fun onSuccess(outputPath: String)
        fun onError(errorCode: String, message: String)
    }

    /** Matches the Dart `Caption` model in `lib/models/caption.dart`. */
    data class Caption(val startMs: Long, val endMs: Long, val text: String)

    private data class ClipVideoSize(
        val width: Int,
        val height: Int,
        val rotationDegrees: Int
    ) {
        private val swapsDimensions: Boolean
            get() = ((rotationDegrees % 360) + 360) % 360 in setOf(90, 270)

        val displayedHeight: Int get() = if (swapsDimensions) width else height
    }

    @Volatile private var activeExport: ActiveExport? = null

    private inner class ActiveExport(
        val thread: HandlerThread,
        val mainHandler: Handler,
        val callback: Callback
    ) {
        private val finished = AtomicBoolean(false)
        private val cleanupLock = Any()
        private val afterCleanup = mutableListOf<() -> Unit>()
        private var cleanedUp = false
        @Volatile var eventSink: EventChannel.EventSink? = null
        @Volatile var outputFile: File? = null
        @Volatile var transformer: Transformer? = null
        @Volatile var pollRunnable: Runnable? = null
        @Volatile private var lastProgress = 0f
        @Volatile var backgroundHandler: Handler? = null
        private val captionOverlays = mutableListOf<CaptionBitmapOverlay>()

        fun retainCaptionOverlay(overlay: CaptionBitmapOverlay) {
            captionOverlays.add(overlay)
        }

        fun postProgress(progress: Float) {
            mainHandler.post {
                if (!finished.get() && activeExport === this) {
                    val monotonicProgress = maxOf(lastProgress, progress)
                        .coerceIn(0f, 0.99999994f)
                    lastProgress = monotonicProgress
                    emitSuccess(mapOf("progress" to monotonicProgress))
                }
            }
        }

        fun succeed() {
            if (!finished.compareAndSet(false, true)) return
            stopProgressPolling()
            mainHandler.post {
                try {
                    val path = outputFile?.absolutePath
                    if (path == null) {
                        finishStreamWithError(
                            ErrorCodes.EXPORT_FAILED,
                            "Export completed without an output file"
                        )
                        callback.onError(
                            ErrorCodes.EXPORT_FAILED,
                            "Export completed without an output file"
                        )
                    } else {
                        emitTerminalSuccess(mapOf("progress" to 1.0f, "outputPath" to path))
                        callback.onSuccess(path)
                    }
                } catch (error: Exception) {
                    android.util.Log.e("ExportService", "Export success callback failed", error)
                } finally {
                    cleanup()
                }
            }
        }

        fun fail(errorCode: String, message: String, emitStreamError: Boolean = true) {
            if (!finished.compareAndSet(false, true)) return
            stopProgressPolling()
            deleteTemporaryOutput(outputFile)
            mainHandler.post {
                try {
                    if (emitStreamError) finishStreamWithError(errorCode, message)
                    else clearEventSink()
                    callback.onError(errorCode, message)
                } catch (error: Exception) {
                    android.util.Log.e("ExportService", "Export error callback failed", error)
                } finally {
                    cleanup()
                }
            }
        }

        fun cancel(
            emitStreamError: Boolean = true,
            onSettled: (() -> Unit)? = null
        ) {
            if (!finished.compareAndSet(false, true)) {
                onSettled?.let(::runAfterCleanup)
                return
            }
            onSettled?.let(::runAfterCleanup)
            stopProgressPolling()
            val handler = backgroundHandler
            if (handler == null) {
                deleteTemporaryOutput(outputFile)
                mainHandler.post {
                    try {
                        if (emitStreamError) {
                            finishStreamWithError(
                                ErrorCodes.CANCELLED,
                                "Export cancelled"
                            )
                        } else {
                            clearEventSink()
                        }
                        callback.onError(
                            ErrorCodes.CANCELLED,
                            "Export cancelled"
                        )
                    } finally {
                        cleanup()
                    }
                }
                return
            }
            val cancellationPosted = handler.post {
                try {
                    transformer?.cancel()
                } catch (error: Exception) {
                    android.util.Log.e("ExportService", "Failed to cancel Transformer", error)
                }
                deleteTemporaryOutput(outputFile)
                mainHandler.post {
                    try {
                        if (emitStreamError) {
                            finishStreamWithError(
                                ErrorCodes.CANCELLED,
                                "Export cancelled"
                            )
                        } else {
                            clearEventSink()
                        }
                        callback.onError(
                            ErrorCodes.CANCELLED,
                            "Export cancelled"
                        )
                    } catch (error: Exception) {
                        android.util.Log.e("ExportService", "Export cancellation callback failed", error)
                    } finally {
                        cleanup()
                    }
                }
            }
            if (!cancellationPosted) {
                mainHandler.post {
                    try {
                        deleteTemporaryOutput(outputFile)
                        if (emitStreamError) {
                            finishStreamWithError(
                                ErrorCodes.CANCELLED,
                                "Export cancelled"
                            )
                        } else {
                            clearEventSink()
                        }
                        callback.onError(
                            ErrorCodes.CANCELLED,
                            "Export cancelled"
                        )
                    } finally {
                        cleanup()
                    }
                }
            }
        }

        fun stopProgressPolling() {
            pollRunnable?.let { backgroundHandler?.removeCallbacks(it) }
            pollRunnable = null
        }

        fun isFinished(): Boolean = finished.get()

        fun emitSuccess(event: Any) {
            try {
                eventSink?.success(event)
            } catch (error: Exception) {
                android.util.Log.w("ExportService", "Flutter stopped listening to export events", error)
            }
        }

        private fun finishStreamWithError(code: String, message: String) {
            val sink = eventSink
            try {
                ErrorCodes.sendEventError(sink, code, message, ErrorCodes.all)
            } catch (error: Exception) {
                android.util.Log.w("ExportService", "Flutter stopped listening to export errors", error)
            } finally {
                try {
                    sink?.endOfStream()
                } catch (error: Exception) {
                    android.util.Log.w("ExportService", "Failed to close export event stream", error)
                }
                clearEventSink()
            }
        }

        private fun emitTerminalSuccess(event: Any) {
            val sink = eventSink
            try {
                sink?.success(event)
            } catch (error: Exception) {
                android.util.Log.w("ExportService", "Flutter stopped listening to export events", error)
            } finally {
                try {
                    sink?.endOfStream()
                } catch (error: Exception) {
                    android.util.Log.w("ExportService", "Failed to close export event stream", error)
                }
                clearEventSink()
            }
        }

        private fun clearEventSink() {
            eventSink = null
        }

        private fun cleanup() {
            stopProgressPolling()
            captionOverlays.forEach { overlay ->
                try {
                    overlay.releaseBitmaps()
                } catch (error: Exception) {
                    android.util.Log.w("ExportService", "Failed to release caption bitmaps", error)
                }
            }
            captionOverlays.clear()
            transformer = null
            pollRunnable = null
            eventSink = null
            outputFile = null
            thread.quitSafely()
            synchronized(this@ExportService) {
                if (activeExport === this) activeExport = null
            }
            val callbacks = synchronized(cleanupLock) {
                cleanedUp = true
                afterCleanup.toList().also { afterCleanup.clear() }
            }
            callbacks.forEach { callback ->
                try {
                    callback()
                } catch (error: Exception) {
                    android.util.Log.e("ExportService", "Export cleanup callback failed", error)
                }
            }
        }

        private fun runAfterCleanup(callback: () -> Unit) {
            val alreadyCleaned = synchronized(cleanupLock) {
                if (cleanedUp) {
                    true
                } else {
                    afterCleanup.add(callback)
                    false
                }
            }
            if (alreadyCleaned) mainHandler.post(callback)
        }
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Export [clipPaths] into a single video at [targetHeight] (720 or 1080), optionally
     * burning [captions] into every frame.
     *
     * @param clipPaths   Ordered list of absolute source video paths.
     * @param targetHeight Target output height in pixels (720 or 1080).
     * @param captions    Raw maps from Dart: keys `startMs`, `endMs` (Number), `text` (String).
     *                    Malformed entries are silently skipped.
     * @param eventSink   EventChannel sink for streaming progress; may be null.
     * @param callback    Completion callback; always called on the main thread.
     */
    fun export(
        clipPaths: List<String>,
        targetHeight: Int,
        captions: List<Map<String, Any>>?,
        eventSink: EventChannel.EventSink?,
        callback: Callback
    ) {
        val main = Handler(Looper.getMainLooper())

        val session = synchronized(this) {
            if (activeExport != null) {
                main.post {
                    callback.onError(
                        ErrorCodes.EXPORT_FAILED,
                        "An export is already running"
                    )
                }
                null
            } else {
                val threadId = UUID.randomUUID().toString().take(8)
                val thread = HandlerThread("Media3ExportThread_$threadId")
                val created = ActiveExport(thread, main, callback)
                created.outputFile = File(
                    context.cacheDir,
                    "export_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.mp4"
                )
                created.eventSink = eventSink
                activeExport = created
                created
            }
        } ?: return
        val ht = session.thread
        val outputFile = requireNotNull(session.outputFile)

        // ---- Start background thread -------------------------------------------
        val bgHandler: Handler
        try {
            ht.start()
            bgHandler = Handler(ht.looper)
            session.backgroundHandler = bgHandler
        } catch (error: Exception) {
            session.fail(
                ErrorCodes.mapThrowable(error),
                error.message ?: "Failed to start export thread"
            )
            return
        }

        val workPosted = bgHandler.post {
            try {
                if (clipPaths.isEmpty()) {
                    session.fail(ErrorCodes.INVALID_RANGE, "clipPaths cannot be empty")
                    return@post
                }
                if (targetHeight != 720 && targetHeight != 1080) {
                    session.fail(
                        ErrorCodes.INVALID_RANGE,
                        "targetHeight must be 720 or 1080 (got $targetHeight)"
                    )
                    return@post
                }

                val validatedClipDurationsMs = mutableListOf<Long>()
                val validatedClipSizes = mutableListOf<ClipVideoSize>()
                for (path in clipPaths) {
                    if (!File(path).isFile) {
                        session.fail(
                            ErrorCodes.FILE_NOT_FOUND,
                            "Source video not found: $path"
                        )
                        return@post
                    }
                    val retriever = MediaMetadataRetriever()
                    var durationMs: Long? = null
                    var videoWidth: Int? = null
                    var videoHeight: Int? = null
                    var rotationDegrees = 0
                    var readError: String? = null
                    try {
                        retriever.setDataSource(path)
                        durationMs = retriever
                            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                            ?.toLongOrNull()
                        videoWidth = retriever
                            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                            ?.toIntOrNull()
                        videoHeight = retriever
                            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                            ?.toIntOrNull()
                        rotationDegrees = retriever
                            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                            ?.toIntOrNull() ?: 0
                    } catch (error: Exception) {
                        readError = error.message ?: "Unable to read media metadata"
                    } finally {
                        try { retriever.release() } catch (_: Exception) {}
                    }
                    if (readError != null || durationMs == null || durationMs <= 0L ||
                        videoWidth == null || videoWidth <= 0 ||
                        videoHeight == null || videoHeight <= 0) {
                        session.fail(
                            ErrorCodes.UNSUPPORTED_FORMAT,
                            "Unsupported or unreadable video: $path" +
                                (readError?.let { " ($it)" } ?: "")
                        )
                        return@post
                    }
                    validatedClipDurationsMs.add(durationMs)
                    validatedClipSizes.add(
                        ClipVideoSize(videoWidth, videoHeight, rotationDegrees)
                    )
                }

                val parsedCaptions: List<Caption>
                if (captions == null) {
                    parsedCaptions = emptyList()
                } else {
                    val parsed = mutableListOf<Caption>()
                    for ((index, map) in captions.withIndex()) {
                        val start = parseCaptionTimestamp(map["startMs"])
                        val end = parseCaptionTimestamp(map["endMs"])
                        val text = try { map["text"] as? String } catch (_: Exception) { null }
                        if (start == null || end == null || text == null || text.isBlank()) continue
                        if (start < 0 || end <= start) {
                            session.fail(
                                ErrorCodes.INVALID_RANGE,
                                "Caption[$index] has invalid timing"
                            )
                            return@post
                        }
                        parsed.add(Caption(start, end, text))
                    }
                    val totalDurationMs = validatedClipDurationsMs.sum()
                    parsedCaptions = parsed
                        .asSequence()
                        .filter { it.startMs < totalDurationMs }
                        .sortedBy { it.startMs }
                        .toList()
                }

                session.postProgress(0f)

                // Pre-compute each clip's duration so we can offset caption times.
                // presentationTimeUs inside getBitmap() is relative to the START of that clip,
                // so we need to add the cumulative offset of all preceding clips to convert to
                // the global export timeline before matching against caption startMs/endMs.
                var cumulativeOffsetMs = 0L
                val editedItems = clipPaths.mapIndexed { clipIndex, path ->
                    val mediaItem = MediaItem.fromUri(Uri.fromFile(File(path)))
                    val effectList = mutableListOf<androidx.media3.common.Effect>()

                    val clipSize = validatedClipSizes[clipIndex]
                    val displayedHeight = clipSize.displayedHeight
                    val scale = targetHeight.toFloat() / displayedHeight.toFloat()
                    if (scale != 1f) {
                        effectList.add(
                            ScaleAndRotateTransformation.Builder()
                                .setScale(scale, scale)
                                .build()
                        )
                    }

                    // 2. Caption overlay — only when captions exist.
                    //
                    //    Media3 resets presentationTimeUs to 0 at the start of each clip, so
                    //    we capture the cumulative offset of this clip's start in the global
                    //    export timeline and add it inside getBitmap() before comparing against
                    //    caption startMs/endMs (which are expressed in the global timeline).
                    if (parsedCaptions.isNotEmpty()) {
                        val clipOffsetMs = cumulativeOffsetMs  // snapshot for this clip's lambda
                        val overlay = buildCaptionOverlay(
                            captions = parsedCaptions,
                            clipOffsetMs = clipOffsetMs
                        )
                        session.retainCaptionOverlay(overlay)
                        effectList.add(OverlayEffect(listOf(overlay)))
                    }

                    cumulativeOffsetMs += validatedClipDurationsMs[clipIndex]

                    val effects = Effects(emptyList(), effectList)
                    EditedMediaItem.Builder(mediaItem)
                        .setEffects(effects)
                        .build()
                }

                // All clips joined into a single sequence (end-to-end).
                val sequence     = EditedMediaItemSequence(editedItems)
                val composition  = Composition.Builder(listOf(sequence)).build()

                val transformer = Transformer.Builder(context)
                    .setLooper(ht.looper)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(comp: Composition, exportResult: ExportResult) {
                            val validationError = validateExportOutput(outputFile)
                            if (validationError != null) {
                                session.fail(
                                    ErrorCodes.EXPORT_FAILED,
                                    validationError
                                )
                                return
                            }
                            session.succeed()
                        }

                        override fun onError(
                            comp: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            session.fail(
                                ErrorCodes.mapThrowable(exportException),
                                exportException.message ?: "Export failed"
                            )
                        }
                    })
                    .build()

                session.transformer = transformer

                // ---- Progress polling (every 300 ms) ---------------------------
                val progressHolder = ProgressHolder()
                val poll = object : Runnable {
                    override fun run() {
                        if (activeExport !== session || session.isFinished()) return
                        val tr = session.transformer ?: return
                        try {
                            val state = tr.getProgress(progressHolder)
                            if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                                session.postProgress(
                                    (progressHolder.progress / 100f).coerceIn(0f, 1f)
                                )
                            }
                        } catch (error: Exception) {
                            session.fail(
                                ErrorCodes.mapThrowable(error),
                                error.message ?: "Failed to read export progress"
                            )
                            return
                        }
                        if (!session.isFinished()) bgHandler.postDelayed(this, 300)
                    }
                }
                session.pollRunnable = poll

                transformer.start(composition, outputFile.absolutePath)
                bgHandler.post(poll)

            } catch (e: Exception) {
                session.fail(
                    ErrorCodes.EXPORT_FAILED,
                    e.message ?: "Failed to start export"
                )
            }
        }
        if (!workPosted) {
            session.fail(
                ErrorCodes.EXPORT_FAILED,
                "Failed to schedule export work"
            )
        }
    }

    /**
     * Cancel the in-progress export.  Safe to call when no export is running.
     */
    fun cancelExport(eventSink: EventChannel.EventSink?, onComplete: () -> Unit) {
        val main = Handler(Looper.getMainLooper())
        val session = activeExport
        if (session == null) {
            main.post(onComplete)
            return
        }
        if (eventSink != null) session.eventSink = eventSink
        session.cancel(onSettled = onComplete)
    }

    fun onProgressStreamListen(eventSink: EventChannel.EventSink?) {
        activeExport?.eventSink = eventSink
    }

    fun onProgressStreamCancelled(eventSink: EventChannel.EventSink?) {
        val session = activeExport ?: return
        if (session.eventSink === eventSink) {
            session.eventSink = null
            session.cancel(emitStreamError = false)
        }
    }

    private fun validateExportOutput(outputFile: File): String? {
        if (!outputFile.isFile || outputFile.length() == 0L) {
            return "Transformer completed without creating a non-empty output file"
        }

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(outputFile.absolutePath)
            val hasVideo =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val durationMs =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull()
            if (!hasVideo || durationMs == null || durationMs <= 0L) {
                "Transformer output is not a valid video file"
            } else {
                val frame = retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST)
                if (frame == null) {
                    "Transformer output contains no decodable video frame"
                } else {
                    frame.recycle()
                    null
                }
            }
        } catch (e: Exception) {
            "Unable to validate transformer output: ${e.message}"
        } finally {
            retriever.release()
        }
    }

    private fun buildCaptionOverlay(
        captions: List<Caption>,
        clipOffsetMs: Long
    ): CaptionBitmapOverlay = CaptionBitmapOverlay(
        captions,
        clipOffsetMs,
        CAPTION_FONT_RATIO,
        CAPTION_MAX_FRAME_WIDTH_RATIO,
        CAPTION_BOTTOM_MARGIN_RATIO,
        CAPTION_MAX_LINES
    )

    private fun parseCaptionTimestamp(value: Any?): Long? {
        if (value is Byte || value is Short || value is Int || value is Long) {
            return (value as Number).toLong()
        }
        val number = value as? Number ?: return null
        val valueAsDouble = number.toDouble()
        if (!valueAsDouble.isFinite() ||
            valueAsDouble % 1.0 != 0.0 ||
            valueAsDouble < Long.MIN_VALUE.toDouble() ||
            valueAsDouble >= Long.MAX_VALUE.toDouble()) {
            return null
        }
        return number.toLong()
    }
}