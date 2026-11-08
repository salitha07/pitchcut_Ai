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
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

internal fun deleteMergeOutput(outputFile: File?) {
    val file = outputFile ?: return
    try {
        if (file.exists() && !file.delete()) {
            android.util.Log.e(
                "MergeService",
                "Failed to delete partial merge output: ${file.absolutePath}"
            )
        }
    } catch (error: Exception) {
        try {
            android.util.Log.e(
                "MergeService",
                "Failed to delete partial merge output: ${file.absolutePath}",
                error
            )
        } catch (_: Exception) {
            // Cleanup must not mask the original merge failure.
        }
    }
}

/**
 * Service providing video concatenation (merging) using AndroidX Media3 Composition.
 *
 * Joins clips in [paths] end-to-end in the given order into an EditedMediaItemSequence,
 * runs the Transformer on a dedicated background [HandlerThread] with a [Looper],
 * writes the output to the app cache directory with a unique name, and returns the result
 * on the main thread.
 *
 * Sensibly handles 1-item lists by copying to a unique cache output file without re-encoding.
 */
class MergeService(private val context: Context) {

    interface Callback {
        fun onSuccess(outputPath: String)
        fun onError(errorCode: String, message: String)
    }

    fun merge(
        paths: List<String>,
        callback: Callback
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        val threadId = UUID.randomUUID().toString().take(8)
        val handlerThread = HandlerThread("Media3MergeThread_$threadId")
        val callbackDelivered = AtomicBoolean(false)
        handlerThread.start()
        val backgroundHandler = Handler(handlerThread.looper)

        fun postErrorAndCleanup(
            errorCode: String,
            message: String,
            outputFile: File? = null
        ) {
            if (!callbackDelivered.compareAndSet(false, true)) return
            deleteMergeOutput(outputFile)
            mainHandler.post {
                callback.onError(errorCode, message)
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
            if (paths.isEmpty()) {
                postErrorAndCleanup(
                    ErrorCodes.INVALID_RANGE,
                    "Paths list cannot be empty"
                )
                return@post
            }

            for (path in paths) {
                val file = File(path)
                if (!file.exists() || !file.isFile) {
                    postErrorAndCleanup(
                        ErrorCodes.FILE_NOT_FOUND,
                        "Source video file not found at: $path"
                    )
                    return@post
                }
            }

            val retriever = MediaMetadataRetriever()
            try {
                for (path in paths) {
                    retriever.setDataSource(path)
                    val durationStr =
                        retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    val durationMs = durationStr?.toLongOrNull()
                    if (durationMs == null || durationMs <= 0L) {
                        postErrorAndCleanup(
                            ErrorCodes.UNSUPPORTED_FORMAT,
                            "Cannot read media duration or unsupported video format: $path"
                        )
                        return@post
                    }
                }
            } catch (e: Exception) {
                postErrorAndCleanup(
                    ErrorCodes.mapThrowable(e).let {
                        if (it == ErrorCodes.EXPORT_FAILED) ErrorCodes.UNSUPPORTED_FORMAT else it
                    },
                    "Unsupported video format or unreadable clip: ${e.message}"
                )
                return@post
            } finally {
                try {
                    retriever.release()
                } catch (_: Exception) {}
            }

            if (paths.size == 1) {
                val sourceFile = File(paths[0])
                val outputFile = File(
                    context.cacheDir,
                    "merge_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.mp4"
                )
                try {
                    sourceFile.copyTo(outputFile, overwrite = true)
                    postSuccessAndCleanup(outputFile.absolutePath)
                } catch (e: Exception) {
                    postErrorAndCleanup(
                        ErrorCodes.mapThrowable(e),
                        "Failed to copy single clip to cache: ${e.message}",
                        outputFile
                    )
                }
                return@post
            }

            val outputFile = File(
                context.cacheDir,
                "merge_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.mp4"
            )

            try {
                val editedMediaItems = paths.map { path ->
                    val file = File(path)
                    val mediaItem = MediaItem.fromUri(Uri.fromFile(file))
                    EditedMediaItem.Builder(mediaItem).build()
                }

                val sequence = EditedMediaItemSequence(editedMediaItems)
                val composition = Composition.Builder(listOf(sequence)).build()

                val transformer = Transformer.Builder(context)
                    .setLooper(handlerThread.looper)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(
                            comp: Composition,
                            exportResult: ExportResult
                        ) {
                            postSuccessAndCleanup(outputFile.absolutePath)
                        }

                        override fun onError(
                            comp: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            val errorCode = ErrorCodes.mapThrowable(exportException)
                            postErrorAndCleanup(
                                errorCode,
                                exportException.message ?: "Merge operation failed",
                                outputFile
                            )
                        }
                    })
                    .build()

                transformer.start(composition, outputFile.absolutePath)
            } catch (e: Exception) {
                postErrorAndCleanup(
                    ErrorCodes.mapThrowable(e),
                    e.message ?: "Failed to start merge transformer",
                    outputFile
                )
            }
        }
    }
}
