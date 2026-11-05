package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

private fun deleteRotateOutput(outputFile: File?) {
    val file = outputFile ?: return
    try {
        if (file.exists() && !file.delete()) {
            try {
                android.util.Log.e(
                    "RotateService",
                    "Failed to delete partial rotation output: ${file.absolutePath}"
                )
            } catch (_: Exception) {}
        }
    } catch (error: Exception) {
        try {
            android.util.Log.e(
                "RotateService",
                "Failed to delete partial rotation output: ${file.absolutePath}",
                error
            )
        } catch (_: Exception) {}
    }
}

/**
 * Service providing video rotation using AndroidX Media3 Effects and Transformer.
 *
 * Rotates a video by 90, 180, or 270 degrees clockwise.
 * Runs on a dedicated background [HandlerThread] with a [Looper], writes output
 * to the cache directory with a unique name, and dispatches the result on the main thread.
 */
class RotateService(private val context: Context) {

    interface Callback {
        fun onSuccess(outputPath: String)
        fun onError(errorCode: String, message: String)
    }

    fun rotate(
        path: String,
        degrees: Int,
        callback: Callback
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        val threadId = UUID.randomUUID().toString().take(8)
        val handlerThread = HandlerThread("Media3RotateThread_$threadId")
        val callbackDelivered = AtomicBoolean(false)
        handlerThread.start()
        val backgroundHandler = Handler(handlerThread.looper)
        var outputFile: File? = null

        fun postErrorAndCleanup(errorCode: String, message: String) {
            if (!callbackDelivered.compareAndSet(false, true)) return
            deleteRotateOutput(outputFile)
            mainHandler.post {
                callback.onError(ErrorCodes.allowedCode(errorCode, ErrorCodes.rotate), message)
            }
            handlerThread.quitSafely()
        }

        fun postSuccessAndCleanup(outputPath: String) {
            if (!callbackDelivered.compareAndSet(false, true)) return
            mainHandler.post {
                callback.onSuccess(outputPath)
            }
            handlerThread.quitSafely()
        }

        backgroundHandler.post {
            val inputFile = File(path)
            if (!inputFile.exists() || !inputFile.isFile) {
                postErrorAndCleanup(
                    ErrorCodes.FILE_NOT_FOUND,
                    "Source video file not found at: $path"
                )
                return@post
            }

            if (degrees != 90 && degrees != 180 && degrees != 270) {
                postErrorAndCleanup(
                    ErrorCodes.INVALID_RANGE,
                    "degrees must be 90, 180, or 270 (received: $degrees)"
                )
                return@post
            }

            val retriever = MediaMetadataRetriever()
            var validationError: String? = null
            var inputWidth = 0
            var inputHeight = 0
            try {
                retriever.setDataSource(path)
                val durationStr =
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val durationMs = durationStr?.toLongOrNull()
                inputWidth = retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                    ?.toIntOrNull() ?: 0
                inputHeight = retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                    ?.toIntOrNull() ?: 0
                if (durationMs == null || durationMs <= 0L) {
                    validationError =
                        "Cannot read video duration or unsupported video format"
                } else if (inputWidth <= 0 || inputHeight <= 0) {
                    validationError = "Cannot read video dimensions or unsupported format"
                }
            } catch (e: Exception) {
                validationError = "Unsupported video format: ${e.message}"
            } finally {
                try {
                    retriever.release()
                } catch (_: Exception) {}
            }
            if (validationError != null) {
                postErrorAndCleanup(
                    ErrorCodes.UNSUPPORTED_FORMAT,
                    validationError
                )
                return@post
            }

            val rotationOutputFile = File(
                context.cacheDir,
                "rot_${degrees}_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.mp4"
            )
            outputFile = rotationOutputFile

            try {
                val mediaItem = MediaItem.fromUri(Uri.fromFile(inputFile))

                val rotationEffect: Effect = ScaleAndRotateTransformation.Builder()
                    .setRotationDegrees(degrees.toFloat())
                    .build()

                val effects = Effects(
                    /* audioProcessors = */ emptyList(),
                    /* videoEffects = */ listOf(rotationEffect)
                )

                val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                    .setEffects(effects)
                    .build()

                val transformer = Transformer.Builder(context)
                    .setLooper(handlerThread.looper)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(
                            comp: Composition,
                            exportResult: ExportResult
                        ) {
                            val validationError = validateRotationOutput(
                                rotationOutputFile,
                                inputWidth,
                                inputHeight,
                                degrees
                            )
                            if (validationError != null) {
                                postErrorAndCleanup(
                                    ErrorCodes.EXPORT_FAILED,
                                    validationError
                                )
                                return
                            }
                            postSuccessAndCleanup(rotationOutputFile.absolutePath)
                        }

                        override fun onError(
                            comp: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            val errorCode = ErrorCodes.mapThrowable(exportException)
                            postErrorAndCleanup(
                                errorCode,
                                exportException.message ?: "Rotate operation failed"
                            )
                        }
                    })
                    .build()

                transformer.start(editedMediaItem, rotationOutputFile.absolutePath)
            } catch (e: Exception) {
                postErrorAndCleanup(
                    ErrorCodes.mapThrowable(e),
                    e.message ?: "Failed to start rotate transformer"
                )
            }
        }
    }

    private fun validateRotationOutput(
        outputFile: File,
        inputWidth: Int,
        inputHeight: Int,
        degrees: Int
    ): String? {
        var retriever: MediaMetadataRetriever? = null
        return try {
            if (!outputFile.isFile || outputFile.length() <= 0L) {
                return "Transformer completed without creating a non-empty output file"
            }

            retriever = MediaMetadataRetriever()
            retriever.setDataSource(outputFile.absolutePath)
            val outputWidth = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull()
            val outputHeight = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull()
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()

            if (outputWidth == null || outputHeight == null ||
                outputWidth <= 0 || outputHeight <= 0 ||
                durationMs == null || durationMs <= 0L) {
                "Rotation output has invalid dimensions or duration"
            } else {
                val dimensionsMatch = when (degrees) {
                    90, 270 -> outputWidth == inputHeight && outputHeight == inputWidth
                    180 -> outputWidth == inputWidth && outputHeight == inputHeight
                    else -> false
                }
                if (dimensionsMatch) {
                    null
                } else {
                    "Rotation output dimensions ${outputWidth}x$outputHeight do not match " +
                        "expected dimensions for ${degrees} degrees"
                }
            }
        } catch (error: Exception) {
            "Unable to validate rotation output: ${error.message}"
        } finally {
            try {
                retriever?.release()
            } catch (_: Exception) {}
        }
    }
}
