package com.pitchcut.pitchcut_ai.media3

import android.graphics.Bitmap
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.SegmentationMask
import com.google.mlkit.vision.segmentation.Segmenter
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import java.io.Closeable
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

internal data class AiSegmentationResult(
    val mask: FloatArray,
    val width: Int,
    val height: Int
)

internal class AiVideoSegmentationProcessor : Closeable {

    private val segmenter: Segmenter
    private val processing = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)

    init {
        val options = SelfieSegmenterOptions.Builder()
            .setDetectorMode(SelfieSegmenterOptions.STREAM_MODE)
            .enableRawSizeMask()
            .build()

        segmenter = Segmentation.getClient(options)
    }

    @Synchronized
    fun processFrame(
        bitmap: Bitmap,
        rotationDegrees: Int = 0
    ): Task<AiSegmentationResult> {

        check(!closed.get()) {
            "Segmentation processor is already closed"
        }

        check(!bitmap.isRecycled) {
            "Input bitmap is recycled"
        }

        require(bitmap.width >= 256 && bitmap.height >= 256) {
            "Input frame must be at least 256x256 for reliable segmentation"
        }

        require(rotationDegrees in setOf(0, 90, 180, 270)) {
            "Rotation must be 0, 90, 180, or 270"
        }

        check(processing.compareAndSet(false, true)) {
            "Wait for the previous frame before processing another frame"
        }

        try {
            val inputImage = InputImage.fromBitmap(
                bitmap,
                rotationDegrees
            )

            return segmenter.process(inputImage)
                .continueWith { completedTask ->
                    try {
                        if (!completedTask.isSuccessful) {
                            throw completedTask.exception
                                ?: IllegalStateException(
                                    "ML Kit segmentation failed"
                                )
                        }

                        convertMask(completedTask.result)
                    } finally {
                        // Reset before the returned Task completes.
                        processing.set(false)
                    }
                }
        } catch (error: Exception) {
            processing.set(false)
            throw error
        }
    }

    private fun convertMask(
        segmentationMask: SegmentationMask
    ): AiSegmentationResult {

        val width = segmentationMask.width
        val height = segmentationMask.height

        require(width > 0 && height > 0) {
            "ML Kit returned invalid mask dimensions"
        }

        val pixelCount = Math.multiplyExact(width, height)

        val buffer = segmentationMask.buffer
            .duplicate()
            .order(ByteOrder.nativeOrder())

        require(buffer.remaining() >= pixelCount * 4) {
            "ML Kit mask buffer is smaller than expected"
        }

        val values = FloatArray(pixelCount)

        for (index in values.indices) {
            val confidence = buffer.float

            values[index] = if (confidence.isFinite()) {
                confidence.coerceIn(0f, 1f)
            } else {
                0f
            }
        }

        return AiSegmentationResult(
            mask = values,
            width = width,
            height = height
        )
    }

    @Synchronized
    override fun close() {
        if (closed.get()) {
            return
        }

        check(!processing.get()) {
            "Cannot close while a frame is being processed"
        }

        if (closed.compareAndSet(false, true)) {
            segmenter.close()
        }
    }
}
