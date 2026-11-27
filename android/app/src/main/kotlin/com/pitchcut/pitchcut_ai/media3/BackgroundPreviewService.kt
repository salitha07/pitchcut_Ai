package com.pitchcut.pitchcut_ai.media3

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import com.google.android.gms.tasks.Tasks

/**
 * Generates individual composited frames for the editor preview.
 * Requests are serialized so ML Kit never receives overlapping frames.
 */
internal class BackgroundPreviewService(
    private val mainHandler: Handler
) {
    private val executor = Executors.newSingleThreadExecutor()
    private val closed = AtomicBoolean(false)

    private val segmentationProcessorDelegate = lazy {
        AiVideoSegmentationProcessor()
    }

    private val segmentationProcessor: AiVideoSegmentationProcessor
        get() = segmentationProcessorDelegate.value

    fun generate(
        path: String,
        timeMs: Long,
        rawBackground: Map<*, *>,
        callback: (ByteArray?, String?) -> Unit
    ) {
        if (closed.get()) {
            callback(null, "Background preview service is closed")
            return
        }

        try {
            executor.execute {
                var retriever: MediaMetadataRetriever? = null
                var frame: Bitmap? = null
                var background: Bitmap? = null
                var composited: Bitmap? = null

                try {
                    check(!closed.get()) {
                        "Background preview service is closed"
                    }

                    require(path.isNotBlank()) {
                        "Video path is empty"
                    }
                    require(timeMs >= 0L) {
                        "Preview timestamp cannot be negative"
                    }

                    val type = rawBackground["type"] as? String
                        ?: error("Background type is missing")

                    require(type in setOf("image", "solid", "gradient", "preset")) {
                        "Unsupported preview background type"
                    }

                    fun color(key: String): Long? =
                        (rawBackground[key] as? Number)?.toLong()

                    val backgroundConfig = TimelineBackground(
                        type = type,
                        imagePath = rawBackground["imagePath"] as? String,
                        solidColor = color("solidColor"),
                        gradientStartColor = color("gradientStartColor"),
                        gradientEndColor = color("gradientEndColor"),
                        presetId = rawBackground["presetId"] as? String
                    )

                    retriever = MediaMetadataRetriever().apply {
                        setDataSource(path)
                    }

                    frame = retriever.getFrameAtTime(
                        timeMs * 1000L,
                        MediaMetadataRetriever.OPTION_CLOSEST
                    ) ?: error("Could not extract the video preview frame")

                    require(frame!!.width >= 256 && frame!!.height >= 256) {
                        "Video frame is too small for background segmentation"
                    }

                    // Keep preview processing and memory usage manageable.
                    val longestSide = maxOf(frame!!.width, frame!!.height)
                    if (longestSide > 960) {
                        val scale = 960f / longestSide
                        val resized = Bitmap.createScaledBitmap(
                            frame!!,
                            (frame!!.width * scale).toInt().coerceAtLeast(256),
                            (frame!!.height * scale).toInt().coerceAtLeast(256),
                            true
                        )
                        if (resized !== frame) {
                            frame!!.recycle()
                            frame = resized
                        }
                    }

                    background = TimelineBackgroundFactory.create(
                        backgroundConfig,
                        frame!!.width,
                        frame!!.height
                    ) ?: error("Could not create the selected background")

                    val segmentation = Tasks.await(
                        segmentationProcessor.processFrame(frame!!, 0)
                    )

                    composited = AiBackgroundCompositor.composite(
                        frame!!,
                        segmentation.mask,
                        segmentation.width,
                        segmentation.height,
                        background!!
                    )

                    val output = ByteArrayOutputStream()
                    check(
                        composited!!.compress(
                            Bitmap.CompressFormat.JPEG,
                            88,
                            output
                        )
                    ) {
                        "Could not encode the background preview"
                    }

                    val bytes = output.toByteArray()
                    mainHandler.post {
                        callback(bytes, null)
                    }
                } catch (error: Exception) {
                    val message = error.message ?: "Background preview failed"
                    mainHandler.post {
                        callback(null, message)
                    }
                } finally {
                    composited?.recycle()
                    background?.recycle()
                    frame?.recycle()
                    try {
                        retriever?.release()
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (error: Exception) {
            callback(null, error.message ?: "Could not queue preview frame")
        }
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return

        // Runs after any active segmentation task because the executor is serial.
        executor.execute {
            if (segmentationProcessorDelegate.isInitialized()) {
                segmentationProcessor.close()
            }
        }
        executor.shutdown()
    }
}

