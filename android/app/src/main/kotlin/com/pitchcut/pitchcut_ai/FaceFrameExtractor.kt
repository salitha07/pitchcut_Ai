
package com.pitchcut.pitchcut_ai

import android.media.MediaMetadataRetriever
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class FaceFrameExtractor {

    fun extractFrames(
        inputPath: String,
        outputDirectory: File,
        intervalMs: Long = 1000L
    ): List<String> {
        require(intervalMs > 0) {
            "Frame interval must be positive."
        }

        val videoFile = File(inputPath)

        require(videoFile.isFile) {
            "Video file was not found."
        }

        val frameDirectory = File(
            outputDirectory,
            "face_frames_${UUID.randomUUID()}"
        )

        if (!frameDirectory.mkdirs()) {
            throw IllegalStateException(
                "Could not create frame directory."
            )
        }

        val retriever = MediaMetadataRetriever()
        val framePaths = mutableListOf<String>()

        try {
            retriever.setDataSource(inputPath)

            val durationMs = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: 0L

            require(durationMs > 0) {
                "Invalid video duration."
            }

            var timeMs = 0L

            while (timeMs < durationMs) {
                val bitmap = retriever.getFrameAtTime(
                    timeMs * 1000L,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                )

                if (bitmap != null) {
                    try {
                        val frameFile = File(
                            frameDirectory,
                            "frame_$timeMs.jpg"
                        )

                        FileOutputStream(frameFile).use { output ->
                            bitmap.compress(
                                android.graphics.Bitmap.CompressFormat.JPEG,
                                75,
                                output
                            )
                        }

                        framePaths.add(frameFile.absolutePath)
                    } finally {
                        bitmap.recycle()
                    }
                }

                timeMs += intervalMs
            }

            return framePaths
        } catch (error: Exception) {
            frameDirectory.deleteRecursively()
            throw error
        } finally {
            retriever.release()
        }
    }
}
