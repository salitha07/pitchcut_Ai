package com.pitchcut.pitchcut_ai

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.Transformer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "pitchcut_ai/video_trim"
    }

    @OptIn(UnstableApi::class)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
