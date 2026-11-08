package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.effect.Crop
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Composition
import androidx.media3.transformer.Transformer
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

private fun deleteCropOutput(outputFile: File?) {
    val file = outputFile ?: return
    try {
        if (file.exists() && !file.delete()) {
            try {
                android.util.Log.e(
                    "CropService",
                    "Failed to delete partial crop output: ${file.absolutePath}"
                )
            } catch (_: Exception) {}
        }
    } catch (error: Exception) {
        try {
            android.util.Log.e(
                "CropService",
                "Failed to delete partial crop output: ${file.absolutePath}",
                error
            )
        } catch (_: Exception) {}
    }
}

/**
 * Service providing video cropping using AndroidX Media3 Crop effect and Transformer.
 *
 * Arguments are pixel coordinates: left, top, width, height.
 * The service validates arguments, converts them to normalized device coordinates,
 * runs the transformation on a background [HandlerThread] with a [Looper], writes the
 * output to the app cache directory with a unique name, and posts the result on the
 * main thread.
 */
class CropService(private val context: Context) {

    interface Callback {
        fun onSuccess(outputPath: String)
        fun onError(errorCode: String, message: String)
    }

    fun crop(
        path: String,
        left: Int,
        top: Int,
        width: Int,
        height: Int,
        callback: Callback
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        val threadId = UUID.randomUUID().toString().take(8)
        val handlerThread = HandlerThread("Media3CropThread_$threadId")
        val callbackDelivered = AtomicBoolean(false)
        handlerThread.start()
        val backgroundHandler = Handler(handlerThread.looper)
        var outputFile: File? = null

        fun postError(errorCode: String, message: String) {
            if (!callbackDelivered.compareAndSet(false, true)) return
            deleteCropOutput(outputFile)
            mainHandler.post {
                callback.onError(errorCode, message)
            }
            handlerThread.quitSafely()
        }

        fun postSuccess(outputPath: String) {
            if (!callbackDelivered.compareAndSet(false, true)) return
            mainHandler.post {
                callback.onSuccess(outputPath)
            }
            handlerThread.quitSafely()
        }

        backgroundHandler.post {
            val inputFile = File(path)
            if (!inputFile.exists() || !inputFile.isFile) {
                postError(
                    ErrorCodes.FILE_NOT_FOUND,
                    "Source video file not found at: $path"
                )
                return@post
            }

            val retriever = MediaMetadataRetriever()
            var storedWidth = 0
            var storedHeight = 0
            var rotationDegrees = 0
            var validationError: String? = null
            var validationErrorCode = ErrorCodes.UNSUPPORTED_FORMAT
            try {
                retriever.setDataSource(path)
                val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                storedWidth = w?.toIntOrNull() ?: 0
                storedHeight = h?.toIntOrNull() ?: 0
                rotationDegrees = retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull() ?: 0
                if (storedWidth <= 0 || storedHeight <= 0) {
                    validationError =
                        "Unable to obtain video dimensions or unsupported format"
                }
            } catch (e: Exception) {
                validationError = "Unsupported video format: ${e.message}"
                validationErrorCode = ErrorCodes.mapThrowable(e).let {
                    if (it == ErrorCodes.EXPORT_FAILED) ErrorCodes.UNSUPPORTED_FORMAT else it
                }
            } finally {
                try {
                    retriever.release()
                } catch (_: Exception) {}
            }
            if (validationError != null) {
                postError(
                    validationErrorCode,
                    requireNotNull(validationError)
                )
                return@post
            }

            val isQuarterTurn = rotationDegrees == 90 || rotationDegrees == 270
            val displayedWidth = if (isQuarterTurn) storedHeight else storedWidth
            val displayedHeight = if (isQuarterTurn) storedWidth else storedHeight

            if (left < 0 || top < 0 || width <= 0 || height <= 0 ||
                left.toLong() + width > displayedWidth ||
                top.toLong() + height > displayedHeight) {
                postError(
                    ErrorCodes.INVALID_RANGE,
                    "Invalid crop rectangle: must be inside displayed video dimensions and have positive size"
                )
                return@post
            }

            val right = left.toLong() + width
            val bottom = top.toLong() + height
            val leftNorm = (left.toFloat() / displayedWidth) * 2f - 1f
            val rightNorm = (right.toFloat() / displayedWidth) * 2f - 1f
            val topNorm = 1f - (top.toFloat() / displayedHeight) * 2f
            val bottomNorm = 1f - (bottom.toFloat() / displayedHeight) * 2f

            val cropOutputFile = File(
                context.cacheDir,
                "crop_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.mp4"
            )
            outputFile = cropOutputFile

            try {
                val mediaItem = MediaItem.fromUri(Uri.fromFile(inputFile))
                val cropEffect = Crop(leftNorm, rightNorm, bottomNorm, topNorm)
                val effects = Effects(
                    /* audioProcessors = */ emptyList(),
                    /* videoEffects = */ listOf(cropEffect)
                )
                val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                    .setEffects(effects)
                    .build()

                val transformer = Transformer.Builder(context)
                    .setLooper(handlerThread.looper)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(comp: Composition, exportResult: ExportResult) {
                            val validationError = validateCropOutput(
                                cropOutputFile,
                                width,
                                height
                            )
                            if (validationError != null) {
                                postError(
                                    ErrorCodes.EXPORT_FAILED,
                                    validationError
                                )
                                return
                            }
                            postSuccess(cropOutputFile.absolutePath)
                        }

                        override fun onError(
                            comp: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            val errorCode = ErrorCodes.mapThrowable(exportException)
                            postError(errorCode, exportException.message ?: "Crop operation failed")
                        }
                    })
                    .build()

                transformer.start(editedMediaItem, cropOutputFile.absolutePath)
            } catch (e: Exception) {
                postError(
                    ErrorCodes.mapThrowable(e),
                    e.message ?: "Failed to start crop transformer"
                )
            }
        }
    }

    private fun validateCropOutput(
        outputFile: File,
        requestedWidth: Int,
        requestedHeight: Int
    ): String? {
        var retriever: MediaMetadataRetriever? = null
        return try {
            if (!outputFile.isFile || outputFile.length() <= 0L) {
                return "Transformer completed without creating a non-empty output file"
            }

            retriever = MediaMetadataRetriever()
            retriever.setDataSource(outputFile.absolutePath)
            val storedWidth = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull()
            val storedHeight = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull()
            val rotationDegrees = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            if (storedWidth == null || storedHeight == null ||
                storedWidth <= 0 || storedHeight <= 0) {
                return "Crop output has invalid dimensions"
            }

            val isQuarterTurn = rotationDegrees == 90 || rotationDegrees == 270
            val outputWidth = if (isQuarterTurn) storedHeight else storedWidth
            val outputHeight = if (isQuarterTurn) storedWidth else storedHeight
            val widthDifference = kotlin.math.abs(outputWidth - requestedWidth)
            val heightDifference = kotlin.math.abs(outputHeight - requestedHeight)
            if (widthDifference <= 2 && heightDifference <= 2) {
                null
            } else {
                "Crop output dimensions ${outputWidth}x$outputHeight do not match " +
                    "requested dimensions ${requestedWidth}x$requestedHeight"
            }
        } catch (error: Exception) {
            "Unable to validate crop output: ${error.message}"
        } finally {
            try {
                retriever?.release()
            } catch (_: Exception) {}
        }
    }
}
