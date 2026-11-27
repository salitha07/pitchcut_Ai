package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.opengl.GLES20
import android.opengl.GLUtils
import androidx.media3.common.GlObjectsProvider
import androidx.media3.common.GlTextureInfo
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlRect
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.effect.ByteBufferGlEffect
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import com.google.android.gms.tasks.Tasks
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

internal class AiBackgroundGlEffect(
    backgroundBitmap: Bitmap,
    private val rotationDegrees: Float = 180f
) : GlEffect {

    private val processor = AiBackgroundProcessor(backgroundBitmap, rotationDegrees)
    private val delegate = ByteBufferGlEffect(processor)
    private val programCreated = AtomicBoolean(false)

    init {
        require(!backgroundBitmap.isRecycled) {
            "Background bitmap is recycled"
        }
    }

    override fun toGlShaderProgram(
        context: Context,
        useHdr: Boolean
    ): GlShaderProgram {
        check(programCreated.compareAndSet(false, true)) {
            "AI background effect can only create one shader program"
        }

        return try {
            ReleasingGlShaderProgram(
                delegate.toGlShaderProgram(context, useHdr),
                processor
            )
        } catch (error: Exception) {
            try {
                processor.release()
            } catch (releaseError: Exception) {
                error.addSuppressed(releaseError)
            }
            throw error
        }
    }
}

private data class AiBackgroundFrameResult(
    val bitmap: Bitmap
)

private class ReleasingGlShaderProgram(
    private val delegate: GlShaderProgram,
    private val processor: AiBackgroundProcessor
) : GlShaderProgram {

    private val released = AtomicBoolean(false)

    override fun setInputListener(listener: GlShaderProgram.InputListener) {
        delegate.setInputListener(listener)
    }

    override fun setOutputListener(listener: GlShaderProgram.OutputListener) {
        delegate.setOutputListener(listener)
    }

    override fun setErrorListener(
        executor: Executor,
        listener: GlShaderProgram.ErrorListener
    ) {
        delegate.setErrorListener(executor, listener)
    }

    override fun queueInputFrame(
        glObjectsProvider: GlObjectsProvider,
        inputTexture: GlTextureInfo,
        presentationTimeUs: Long
    ) {
        delegate.queueInputFrame(
            glObjectsProvider,
            inputTexture,
            presentationTimeUs
        )
    }

    override fun releaseOutputFrame(outputTexture: GlTextureInfo) {
        delegate.releaseOutputFrame(outputTexture)
    }

    override fun signalEndOfCurrentInputStream() {
        delegate.signalEndOfCurrentInputStream()
    }

    override fun flush() {
        delegate.flush()
    }

    override fun release() {
        if (!released.compareAndSet(false, true)) return

        var releaseFailure: Exception? = null

        try {
            delegate.release()
        } catch (error: Exception) {
            releaseFailure = error
        }

        try {
            processor.release()
        } catch (error: Exception) {
            if (releaseFailure == null) {
                releaseFailure = error
            } else {
                releaseFailure.addSuppressed(error)
            }
        }

        releaseFailure?.let { error ->
            if (error is VideoFrameProcessingException) throw error

            throw VideoFrameProcessingException(
                "Failed to release AI background shader program",
                error
            )
        }
    }
}

private class AiBackgroundProcessor(
    private val backgroundBitmap: Bitmap,
    private val rotationDegrees: Float
) : ByteBufferGlEffect.Processor<AiBackgroundFrameResult> {

    private val segmentationProcessor = AiVideoSegmentationProcessor()

    // CPU compositing worker.
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "pitchcut-ai-background").apply {
            isDaemon = true
        }
    }

    // ML Kit runs independently from the compositing worker.
    private val segmentationWorker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "pitchcut-ai-segmentation").apply {
            isDaemon = true
        }
    }

    private val segmentationInProgress = AtomicBoolean(false)
    private val lastSegmentationRequestNs = AtomicLong(0L)
    private val releaseStarted = AtomicBoolean(false)

    private val firstMask = CompletableFuture<AiSegmentationResult>()

    @Volatile
    private var latestMask: AiSegmentationResult? = null

    @Volatile
    private var frameWidth = 0

    @Volatile
    private var frameHeight = 0

    @Volatile
    private var released = false

    // Request a fresh segmentation approximately every 350 ms.
    private val segmentationIntervalNs =
        TimeUnit.MILLISECONDS.toNanos(350)

    override fun configure(width: Int, height: Int): Size {
        check(!released) {
            "AI background processor is released"
        }

        require(width >= 256 && height >= 256) {
            "Video dimensions must be at least 256x256"
        }

        frameWidth = width
        frameHeight = height

        return Size(width, height)
    }

    override fun getScaledRegion(presentationTimeUs: Long): GlRect {
        check(frameWidth > 0 && frameHeight > 0) {
            "Processor has not been configured"
        }

        return GlRect(frameWidth, frameHeight)
    }

    /**
     * Makes a separate, small bitmap for ML Kit.
     * The segmentation worker owns this bitmap and recycles it
     * only after ML Kit has completed processing it.
     */
    private fun createSegmentationBitmap(source: Bitmap): Bitmap {
        val longestSide = maxOf(source.width, source.height)
        val scale = minOf(1f, 640f / longestSide)

        val targetWidth =
            (source.width * scale).toInt().coerceAtLeast(1)

        val targetHeight =
            (source.height * scale).toInt().coerceAtLeast(1)

        return if (targetWidth == source.width &&
            targetHeight == source.height) {
            Bitmap.createBitmap(source)
        } else {
            Bitmap.createScaledBitmap(
                source,
                targetWidth,
                targetHeight,
                true
            )
        }
    }

    /**
     * Schedules segmentation without blocking the frame compositor.
     * Only one ML Kit request is allowed at a time.
     */
    private fun scheduleSegmentation(source: Bitmap) {
        if (released) return

        val now = System.nanoTime()
        val previous = lastSegmentationRequestNs.get()

        if (previous != 0L &&
            now - previous < segmentationIntervalNs) {
            return
        }

        if (!segmentationInProgress.compareAndSet(false, true)) {
            return
        }

        val segmentationBitmap = try {
            createSegmentationBitmap(source)
        } catch (_: Exception) {
            segmentationInProgress.set(false)
            return
        }

        try {
            segmentationWorker.execute {
                try {
                    val result = Tasks.await(
                        segmentationProcessor.processFrame(
                            segmentationBitmap,
                            rotationDegrees = 0
                        )
                    )

                    if (!released) {
                        latestMask = result
                        firstMask.complete(result)
                    }
                } catch (_: Exception) {
                    // Keep the previous valid mask.
                    // A later frame can request segmentation again.
                } finally {
                    if (!segmentationBitmap.isRecycled) {
                        segmentationBitmap.recycle()
                    }

                    lastSegmentationRequestNs.set(System.nanoTime())
                    segmentationInProgress.set(false)
                }
            }
        } catch (_: RejectedExecutionException) {
            if (!segmentationBitmap.isRecycled) {
                segmentationBitmap.recycle()
            }

            segmentationInProgress.set(false)
        }
    }

    override fun processImage(
        image: ByteBufferGlEffect.Image,
        presentationTimeUs: Long
    ): ListenableFuture<AiBackgroundFrameResult> {

        val resultFuture =
            SettableFuture.create<AiBackgroundFrameResult>()

        if (released) {
            resultFuture.setException(
                IllegalStateException(
                    "AI background processor is released"
                )
            )
            return resultFuture
        }

        // Copy while Media3's input image is still valid.
        val foregroundBitmap = try {
            image.copyToBitmap()
        } catch (error: Exception) {
            resultFuture.setException(error)
            return resultFuture
        }

        // Segmentation is scheduled independently.
        scheduleSegmentation(foregroundBitmap)

        try {
            worker.execute {
                var outputBitmap: Bitmap? = null
                var compositedBitmap: Bitmap? = null

                try {
                    // Reuse the latest completed mask.
                    // Only the initial frame waits for the first mask.
                    val mask = latestMask ?: firstMask.get(
                        30,
                        TimeUnit.SECONDS
                    )

                    if (released) {
                        throw IllegalStateException(
                            "AI background processor is released"
                        )
                    }

                    val composited = AiBackgroundCompositor.composite(
                        foreground = foregroundBitmap,
                        mask = mask.mask,
                        maskWidth = mask.width,
                        maskHeight = mask.height,
                        background = backgroundBitmap
                    )

                    compositedBitmap = composited

                    val correctedBitmap = Bitmap.createBitmap(
                        composited,
                        0,
                        0,
                        composited.width,
                        composited.height,
                        Matrix().apply {
                            setRotate(rotationDegrees)
                        },
                        true
                    )

                    if (correctedBitmap !== composited &&
                        !composited.isRecycled) {
                        composited.recycle()
                    }

                    outputBitmap = correctedBitmap

                    if (resultFuture.set(
                            AiBackgroundFrameResult(correctedBitmap)
                        )
                    ) {
                        outputBitmap = null
                    }

                } catch (error: Exception) {
                    resultFuture.setException(error)

                } finally {
                    if (!foregroundBitmap.isRecycled) {
                        foregroundBitmap.recycle()
                    }

                    compositedBitmap?.let {
                        if (!it.isRecycled) it.recycle()
                    }

                    outputBitmap?.let {
                        if (!it.isRecycled) it.recycle()
                    }
                }
            }
        } catch (error: RejectedExecutionException) {
            if (!foregroundBitmap.isRecycled) {
                foregroundBitmap.recycle()
            }

            resultFuture.setException(error)
        }

        return resultFuture
    }

    override fun finishProcessingAndBlend(
        outputTexture: GlTextureInfo,
        presentationTimeUs: Long,
        processedResult: AiBackgroundFrameResult
    ) {
        val bitmap = processedResult.bitmap
        val previousTexture = IntArray(1)

        try {
            check(!bitmap.isRecycled) {
                "Processed frame bitmap is recycled"
            }

            require(bitmap.width == outputTexture.width) {
                "Output texture width does not match processed frame"
            }

            require(bitmap.height == outputTexture.height) {
                "Output texture height does not match processed frame"
            }

            GLES20.glGetIntegerv(
                GLES20.GL_TEXTURE_BINDING_2D,
                previousTexture,
                0
            )

            GLES20.glBindTexture(
                GLES20.GL_TEXTURE_2D,
                outputTexture.texId
            )
            GlUtil.checkGlError()

            GLUtils.texSubImage2D(
                GLES20.GL_TEXTURE_2D,
                0,
                0,
                0,
                bitmap
            )
            GlUtil.checkGlError()

        } catch (error: Exception) {
            throw VideoFrameProcessingException.from(
                error,
                presentationTimeUs
            )

        } finally {
            GLES20.glBindTexture(
                GLES20.GL_TEXTURE_2D,
                previousTexture[0]
            )

            if (!bitmap.isRecycled) {
                bitmap.recycle()
            }
        }
    }

    @Synchronized
    override fun release() {
        if (!releaseStarted.compareAndSet(false, true)) return

        released = true

        worker.shutdown()
        segmentationWorker.shutdown()

        try {
            val workerStopped =
                worker.awaitTermination(60, TimeUnit.SECONDS)

            val segmentationStopped =
                segmentationWorker.awaitTermination(
                    60,
                    TimeUnit.SECONDS
                )

            if (!workerStopped || !segmentationStopped) {
                worker.shutdownNow()
                segmentationWorker.shutdownNow()

                val workerStoppedAfterInterrupt =
                    worker.awaitTermination(5, TimeUnit.SECONDS)

                val segmentationStoppedAfterInterrupt =
                    segmentationWorker.awaitTermination(
                        5,
                        TimeUnit.SECONDS
                    )

                if (!workerStoppedAfterInterrupt ||
                    !segmentationStoppedAfterInterrupt) {
                    throw VideoFrameProcessingException(
                        "Timed out waiting for AI background workers"
                    )
                }
            }

            segmentationProcessor.close()

        } catch (error: InterruptedException) {
            worker.shutdownNow()
            segmentationWorker.shutdownNow()
            Thread.currentThread().interrupt()

            throw VideoFrameProcessingException(
                "Interrupted while releasing AI background processor",
                error
            )

        } finally {
            if (worker.isTerminated &&
                segmentationWorker.isTerminated &&
                !backgroundBitmap.isRecycled) {
                backgroundBitmap.recycle()
            }
        }
    }
}
