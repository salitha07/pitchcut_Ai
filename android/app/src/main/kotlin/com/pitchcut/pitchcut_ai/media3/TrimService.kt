package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File
import java.util.UUID

internal fun deleteTrimOutput(outputFile: File?) {
    val file = outputFile ?: return
    try {
        if (file.exists() && !file.delete()) {
            android.util.Log.e("TrimService", "Failed to delete partial trim output: ${file.absolutePath}")
        }
    } catch (error: Exception) {
        try {
            android.util.Log.e("TrimService", "Failed to delete partial trim output: ${file.absolutePath}", error)
        } catch (_: Exception) {
            // Cleanup must not mask the original trim failure.
        }
    }
}

/**
 * Service providing video trimming using AndroidX Media3 Transformer.
 *
 * Runs Transformer on a dedicated background [HandlerThread] with a [Looper],
 * writes the resulting output to the application cache directory with a unique name,
 * and dispatches all results and errors back to the caller on the main thread.
 */
class TrimService(private val context: Context) {

    interface Callback {
        fun onSuccess(outputPath: String)
        fun onError(errorCode: String, message: String)
    }

    fun trim(
        path: String,
        startMs: Long,
        endMs: Long,
        callback: Callback
    ) {
        val mainHandler = Handler(Looper.getMainLooper())

        // Start a dedicated background thread with a Looper for Media3 Transformer
        val threadId = UUID.randomUUID().toString().take(8)
        val handlerThread = HandlerThread("Media3TrimThread_$threadId")
        handlerThread.start()
        val backgroundHandler = Handler(handlerThread.looper)

        backgroundHandler.post {
            var outputFile: File? = null

            fun postErrorAndCleanup(errorCode: String, message: String) {
                deleteTrimOutput(outputFile)
                mainHandler.post {
                    callback.onError(errorCode, message)
                }
                handlerThread.quitSafely()
            }

            fun postSuccessAndCleanup(outputPath: String) {
                mainHandler.post {
                    callback.onSuccess(outputPath)
                }
                handlerThread.quitSafely()
            }

            val inputFile = File(path)
            if (!inputFile.exists() || !inputFile.isFile) {
                postErrorAndCleanup(
                    ErrorCodes.FILE_NOT_FOUND,
                    "Source video file not found at: $path"
                )
                return@post
            }

            if (startMs < 0 || endMs <= startMs) {
                postErrorAndCleanup(
                    ErrorCodes.INVALID_RANGE,
                    "Invalid time range: startMs ($startMs) must be >= 0 and < endMs ($endMs)"
                )
                return@post
            }

            // Validate media readability and extract duration on background thread
            val retriever = MediaMetadataRetriever()
            var durationMs: Long? = null
            try {
                retriever.setDataSource(path)
                val durationStr =
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                durationMs = durationStr?.toLongOrNull()
            } catch (e: Exception) {
                try {
                    retriever.release()
                } catch (_: Exception) {}
                postErrorAndCleanup(
                    ErrorCodes.mapThrowable(e).let {
                        if (it == ErrorCodes.EXPORT_FAILED) ErrorCodes.UNSUPPORTED_FORMAT else it
                    },
                    "Unsupported video format or unreadable media: ${e.message}"
                )
                return@post
            } finally {
                try {
                    retriever.release()
                } catch (_: Exception) {}
            }

            // Validate that endMs does not exceed duration
            if (durationMs != null && (startMs >= durationMs || endMs > durationMs)) {
                postErrorAndCleanup(
                    ErrorCodes.INVALID_RANGE,
                    "Requested range [$startMs, $endMs] exceeds video duration ($durationMs ms)"
                )
                return@post
            }

            // Write output to the app cache dir with a unique name
            val trimOutputFile = File(
                context.cacheDir,
                "trim_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.mp4"
            )
            outputFile = trimOutputFile

            try {
                val clippingConfiguration = MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .setStartsAtKeyFrame(false)
                    .build()

                val mediaItem = MediaItem.Builder()
                    .setUri(Uri.fromFile(inputFile))
                    .setClippingConfiguration(clippingConfiguration)
                    .build()

                val editedMediaItem = EditedMediaItem.Builder(mediaItem).build()

                val transformer = Transformer.Builder(context)
                    .setLooper(handlerThread.looper)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(
                            composition: Composition,
                            exportResult: ExportResult
                        ) {
                            postSuccessAndCleanup(trimOutputFile.absolutePath)
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            val errorCode = ErrorCodes.mapThrowable(exportException)
                            postErrorAndCleanup(
                                errorCode,
                                exportException.message ?: "Trim operation failed"
                            )
                        }
                    })
                    .build()

                transformer.start(editedMediaItem, trimOutputFile.absolutePath)
            } catch (e: Exception) {
                postErrorAndCleanup(
                    ErrorCodes.mapThrowable(e),
                    e.message ?: "Failed to start trim transformer"
                )
            }
        }
    }
}
