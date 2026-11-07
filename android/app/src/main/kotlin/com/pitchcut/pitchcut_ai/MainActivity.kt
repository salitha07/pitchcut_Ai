package com.pitchcut.pitchcut_ai

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.Effect
import androidx.media3.effect.Crop
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.ProgressHolder
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.ByteArrayOutputStream

@OptIn(UnstableApi::class)
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "pitchcut_ai/video_trim"
    }

    private val exportHandler = Handler(Looper.getMainLooper())
    private var exportEventSink: EventChannel.EventSink? = null
    private var activeTransformer: Transformer? = null
    private var activeExportId: String? = null
    private var activeExportWasCancelled = false

    @OptIn(UnstableApi::class)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "pitchcut_ai/video_export_progress")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    exportEventSink = events
                    events?.success(mapOf("type" to "ready"))
                }

                override fun onCancel(arguments: Any?) {
                    exportEventSink = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "generateThumbnail") {
                    val inputPath = call.argument<String>("inputPath")
                    val timeMs = call.argument<Int>("timeMs") ?: 0
                    if (inputPath == null || !File(inputPath).isFile) {
                        result.error("missing_input", "The selected video file was not found.", null)
                        return@setMethodCallHandler
                    }
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(inputPath)
                        val frame = retriever.getFrameAtTime(
                            timeMs.coerceAtLeast(0).toLong() * 1000,
                            MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                        )
                        if (frame == null) {
                            result.success(null)
                        } else {
                            val scale = minOf(1f, 280f / maxOf(frame.width, frame.height))
                            val thumbnail = if (scale < 1f) {
                                Bitmap.createScaledBitmap(
                                    frame,
                                    (frame.width * scale).toInt().coerceAtLeast(1),
                                    (frame.height * scale).toInt().coerceAtLeast(1),
                                    true
                                )
                            } else {
                                frame
                            }
                            val output = ByteArrayOutputStream()
                            thumbnail.compress(Bitmap.CompressFormat.JPEG, 70, output)
                            if (thumbnail !== frame) thumbnail.recycle()
                            frame.recycle()
                            result.success(output.toByteArray())
                        }
                    } catch (error: Exception) {
                        result.success(null)
                    } finally {
                        retriever.release()
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "cancelExport") {
                    val exportId = call.argument<String>("exportId")
                    if (exportId != null && exportId == activeExportId && activeTransformer != null) {
                        activeExportWasCancelled = true
                        activeTransformer?.cancel()
                    }
                    result.success(null)
                    return@setMethodCallHandler
                }
                if (call.method == "exportTimeline" || call.method == "startExportTimeline") {
                    val trackedExport = call.method == "startExportTimeline"
                    val outputPath = call.argument<String>("outputPath")
                    val clips = call.argument<List<Map<String, Any?>>>("clips")
                    val exportId = if (trackedExport) call.argument<String>("exportId") else null
                    val qualityHeight = if (trackedExport) call.argument<Int>("qualityHeight") else null
                    if (outputPath == null || clips.isNullOrEmpty()) {
                        result.error("invalid_timeline", "There are no clips to export.", null)
                        return@setMethodCallHandler
                    }
                    if (activeTransformer != null) {
                        result.error("export_busy", "Another video export is already running.", null)
                        return@setMethodCallHandler
                    }
                    if (trackedExport &&
                        (exportId == null || qualityHeight == null || qualityHeight !in listOf(480, 720, 1080))
                    ) {
                        result.error("invalid_export_settings", "The export quality is invalid.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val editedItems = clips.map { clip ->
                            val inputPath = clip["inputPath"] as? String
                            val startMs = (clip["startMs"] as? Number)?.toLong()
                            val endMs = (clip["endMs"] as? Number)?.toLong()
                            if (inputPath == null || startMs == null || endMs == null ||
                                startMs < 0 || endMs <= startMs || !File(inputPath).isFile
                            ) {
                                throw IllegalArgumentException("A timeline clip is invalid or missing.")
                            }
                            val mediaItem = MediaItem.Builder()
                                .setUri(inputPath)
                                .setClippingConfiguration(
                                    MediaItem.ClippingConfiguration.Builder()
                                        .setStartPositionMs(startMs)
                                        .setEndPositionMs(endMs)
                                        .build()
                                )
                                .build()
                            val videoEffects = mutableListOf<Effect>()
                            val rotation = (clip["rotationDegrees"] as? Number)?.toFloat() ?: 0f
                            if (rotation != 0f) {
                                videoEffects.add(
                                    ScaleAndRotateTransformation.Builder()
                                        .setRotationDegrees(rotation)
                                        .build()
                                )
                            }
                            val crop = clip["crop"] as? Map<*, *>
                            if (crop != null) {
                                val left = (crop["left"] as? Number)?.toFloat() ?: 0f
                                val top = (crop["top"] as? Number)?.toFloat() ?: 0f
                                val right = (crop["right"] as? Number)?.toFloat() ?: 1f
                                val bottom = (crop["bottom"] as? Number)?.toFloat() ?: 1f
                                if (left < 0f || top < 0f || right > 1f || bottom > 1f ||
                                    right - left < 0.05f || bottom - top < 0.05f
                                ) throw IllegalArgumentException("A timeline crop rectangle is invalid.")
                                videoEffects.add(
                                    Crop(
                                        2f * left - 1f,
                                        2f * right - 1f,
                                        1f - 2f * bottom,
                                        1f - 2f * top
                                    )
                                )
                            }
                            if (qualityHeight != null) {
                                videoEffects.add(Presentation.createForHeight(qualityHeight))
                            }
                            EditedMediaItem.Builder(mediaItem)
                                .setEffects(Effects(emptyList(), videoEffects))
                                .build()
                        }
                        File(outputPath).parentFile?.mkdirs()
                        val sequence = EditedMediaItemSequence.withAudioAndVideoFrom(editedItems)
                        val composition = Composition.Builder(sequence).build()
                        val transformer = Transformer.Builder(this)
                            .setVideoMimeType(MimeTypes.VIDEO_H264)
                            .setAudioMimeType(MimeTypes.AUDIO_AAC)
                            .addListener(object : Transformer.Listener {
                                override fun onCompleted(
                                    composition: Composition,
                                    exportResult: ExportResult
                                ) {
                                    stopProgressPolling()
                                    if (exportId != null) emitExportProgress(exportId, 1.0)
                                    clearActiveExport()
                                    result.success(outputPath)
                                }

                                override fun onError(
                                    composition: Composition,
                                    exportResult: ExportResult,
                                    exportException: ExportException
                                ) {
                                    stopProgressPolling()
                                    File(outputPath).delete()
                                    val wasCancelled = activeExportWasCancelled
                                    clearActiveExport()
                                    result.error(
                                        if (wasCancelled) "export_cancelled" else "export_failed",
                                        if (wasCancelled) "Video export was cancelled."
                                        else exportException.message ?: "Video export failed.",
                                        null
                                    )
                                }
                            })
                            .build()
                        activeTransformer = transformer
                        activeExportId = exportId
                        activeExportWasCancelled = false
                        transformer.start(composition, outputPath)
                        if (exportId != null) startProgressPolling(exportId, transformer)
                    } catch (error: Exception) {
                        clearActiveExport()
                        File(outputPath).delete()
                        result.error("export_failed", error.message ?: "Video export failed.", null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "trimVideo") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                val startMs = call.argument<Int>("startMs")
                val endMs = call.argument<Int>("endMs")
                if (inputPath == null || outputPath == null || startMs == null || endMs == null ||
                    startMs < 0 || endMs <= startMs
                ) {
                    result.error("invalid_trim_range", "The trim range is invalid.", null)
                    return@setMethodCallHandler
                }

                try {
                    if (!File(inputPath).isFile) {
                        result.error("missing_input", "The selected video file was not found.", null)
                        return@setMethodCallHandler
                    }
                    File(outputPath).parentFile?.mkdirs()
                    val mediaItem = MediaItem.Builder()
                        .setUri(inputPath)
                        .setClippingConfiguration(
                            MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionMs(startMs.toLong())
                                .setEndPositionMs(endMs.toLong())
                                .build()
                        )
                        .build()
                    val transformer = Transformer.Builder(this)
                        .addListener(object : Transformer.Listener {
                            override fun onCompleted(
                                composition: Composition,
                                exportResult: ExportResult
                            ) {
                                result.success(outputPath)
                            }

                            override fun onError(
                                composition: Composition,
                                exportResult: ExportResult,
                                exportException: ExportException
                            ) {
                                File(outputPath).delete()
                                result.error(
                                    "trim_failed",
                                    exportException.message ?: "Video trimming failed.",
                                    null
                                )
                            }
                        })
                        .build()
                    transformer.start(EditedMediaItem.Builder(mediaItem).build(), outputPath)
                } catch (error: Exception) {
                    File(outputPath).delete()
                    result.error("trim_failed", error.message ?: "Video trimming failed.", null)
                }
            }
    }

    private var progressRunnable: Runnable? = null

    private fun emitExportProgress(exportId: String, progress: Double) {
        exportEventSink?.success(mapOf(
            "exportId" to exportId,
            "type" to "progress",
            "progress" to progress.coerceIn(0.0, 1.0)
        ))
    }

    private fun startProgressPolling(exportId: String, transformer: Transformer) {
        val runnable = object : Runnable {
            override fun run() {
                if (activeExportId != exportId || activeTransformer !== transformer) return
                try {
                    val progress = ProgressHolder()
                    if (transformer.getProgress(progress) == Transformer.PROGRESS_STATE_AVAILABLE) {
                        emitExportProgress(exportId, progress.progress / 100.0)
                    }
                } catch (_: IllegalStateException) {
                    // Transformer progress is only available on its application looper.
                }
                exportHandler.postDelayed(this, 250)
            }
        }
        progressRunnable = runnable
        exportHandler.post(runnable)
    }

    private fun stopProgressPolling() {
        progressRunnable?.let { exportHandler.removeCallbacks(it) }
        progressRunnable = null
    }

    private fun clearActiveExport() {
        activeTransformer = null
        activeExportId = null
        activeExportWasCancelled = false
    }
}
