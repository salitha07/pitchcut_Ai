package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Service providing video cutting (splitting) using Media3 clipping.
 *
 * Directly reuses [TrimService] to export:
 * Part 1: [0, atMs]
 * Part 2: [atMs, durationMs]
 *
 * Avoids any duplication of Media3 Transformer pipelines, clipping configuration,
 * background threading, or cache directory management.
 */
class CutService(
    context: Context,
    private val trimService: TrimService = TrimService(context)
) {

    interface Callback {
        fun onSuccess(outputPaths: List<String>)
        fun onError(errorCode: String, message: String)
    }

    fun cut(
        path: String,
        atMs: Long,
        callback: Callback
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        val callbackDelivered = AtomicBoolean(false)
        val threadId = UUID.randomUUID().toString().take(8)
        val validationThread = HandlerThread("Media3CutValidationThread_$threadId")
        validationThread.start()

        fun deliverSuccess(outputPaths: List<String>) {
            mainHandler.post {
                if (callbackDelivered.compareAndSet(false, true)) {
                    callback.onSuccess(outputPaths)
                }
            }
        }

        fun deliverError(errorCode: String, message: String) {
            mainHandler.post {
                if (callbackDelivered.compareAndSet(false, true)) {
                    callback.onError(errorCode, message)
                }
            }
        }

        Handler(validationThread.looper).post {
            var durationMs = -1L
            var errorCode: String? = null
            var errorMessage: String? = null
            val inputFile = File(path)

            if (!inputFile.exists() || !inputFile.isFile) {
                errorCode = ErrorCodes.FILE_NOT_FOUND
                errorMessage = "Source video file not found at: $path"
            } else {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(path)
                    val durationStr =
                        retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    durationMs = durationStr?.toLongOrNull() ?: -1L
                } catch (error: Exception) {
                    errorCode = ErrorCodes.mapThrowable(error).let {
                        if (it == ErrorCodes.EXPORT_FAILED) ErrorCodes.UNSUPPORTED_FORMAT else it
                    }
                    errorMessage =
                        "Unsupported video format or unreadable media: ${error.message}"
                } finally {
                    try {
                        retriever.release()
                    } catch (_: Exception) {
                    }
                }

                if (errorCode == null && durationMs <= 0L) {
                    errorCode = ErrorCodes.UNSUPPORTED_FORMAT
                    errorMessage = "Unable to determine video duration"
                }
            }

            if (errorCode == null && (atMs <= 0 || atMs >= durationMs)) {
                errorCode = ErrorCodes.INVALID_RANGE
                errorMessage =
                    "Split point atMs ($atMs ms) must be > 0 and < video duration ($durationMs ms)"
            }

            validationThread.quitSafely()
            mainHandler.post {
                if (errorCode != null) {
                    if (callbackDelivered.compareAndSet(false, true)) {
                        callback.onError(errorCode, errorMessage ?: "Cut operation failed")
                    }
                    return@post
                }

                // Step 1: Reuse TrimService for Part 1 (0 to atMs).
                try {
                    trimService.trim(path, 0L, atMs, object : TrimService.Callback {
                        override fun onSuccess(outputPath: String) {
                            val part1Path = outputPath
                            // Step 2: Reuse TrimService for Part 2 (atMs to durationMs).
                            try {
                                trimService.trim(path, atMs, durationMs, object : TrimService.Callback {
                                    override fun onSuccess(outputPath: String) {
                                        val part2Path = outputPath
                                        deliverSuccess(listOf(part1Path, part2Path))
                                    }

                                    override fun onError(errorCode: String, message: String) {
                                        deleteTrimOutput(File(part1Path))
                                        deliverError(errorCode, message)
                                    }
                                })
                            } catch (error: Exception) {
                                deleteTrimOutput(File(part1Path))
                                deliverError(
                                    ErrorCodes.mapThrowable(error),
                                    error.message ?: "Failed to start second trim"
                                )
                            }
                        }

                        override fun onError(errorCode: String, message: String) {
                            deliverError(errorCode, message)
                        }
                    })
                } catch (error: Exception) {
                    deliverError(
                        ErrorCodes.mapThrowable(error),
                        error.message ?: "Failed to start first trim"
                    )
                }
            }
        }
    }
}
