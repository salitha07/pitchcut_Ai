
package com.pitchcut.pitchcut_ai.media3

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import kotlin.math.max

/**
 * Composites a foreground video frame over a selected background.
 *
 * The mask contains foreground confidence values in the range 0..1.
 * A higher value means the pixel is more likely to belong to the person.
 */
internal object AiBackgroundCompositor {

    fun composite(
        foreground: Bitmap,
        mask: FloatArray,
        maskWidth: Int,
        maskHeight: Int,
        background: Bitmap
    ): Bitmap {
        require(!foreground.isRecycled) {
            "Foreground bitmap is recycled"
        }
        require(!background.isRecycled) {
            "Background bitmap is recycled"
        }
        require(maskWidth > 0 && maskHeight > 0) {
            "Mask dimensions must be positive"
        }
        require(mask.size == maskWidth * maskHeight) {
            "Mask size does not match mask dimensions"
        }

        val width = foreground.width
        val height = foreground.height

        require(width > 0 && height > 0) {
            "Foreground dimensions must be positive"
        }

        val foregroundPixels = IntArray(width * height)
        val backgroundPixels = IntArray(width * height)

        foreground.getPixels(
            foregroundPixels,
            0,
            width,
            0,
            0,
            width,
            height
        )

        val scaledBackground = Bitmap.createScaledBitmap(
            background,
            width,
            height,
            true
        )

        try {
            scaledBackground.getPixels(
                backgroundPixels,
                0,
                width,
                0,
                0,
                width,
                height
            )
        } finally {
            if (scaledBackground !== background) {
                scaledBackground.recycle()
            }
        }

        val outputPixels = IntArray(width * height)

        for (y in 0 until height) {
            val maskY = minOf(
                maskHeight - 1,
                y * maskHeight / height
            )

            for (x in 0 until width) {
                val maskX = minOf(
                    maskWidth - 1,
                    x * maskWidth / width
                )

                val index = y * width + x

                val confidence = mask[
                    maskY * maskWidth + maskX
                ].takeIf { it.isFinite() }?.coerceIn(0f, 1f) ?: 0f

                outputPixels[index] = blend(
                    foregroundPixels[index],
                    backgroundPixels[index],
                    confidence
                )
            }
        }

        return Bitmap.createBitmap(
            outputPixels,
            width,
            height,
            Bitmap.Config.ARGB_8888
        )
    }

    private fun blend(
        foreground: Int,
        background: Int,
        confidence: Float
    ): Int {
        fun channel(
            foregroundValue: Int,
            backgroundValue: Int
        ): Int {
            return (
                foregroundValue * confidence +
                    backgroundValue * (1f - confidence)
                ).toInt().coerceIn(0, 255)
        }

        return Color.argb(
            255,
            channel(Color.red(foreground), Color.red(background)),
            channel(Color.green(foreground), Color.green(background)),
            channel(Color.blue(foreground), Color.blue(background))
        )
    }

    fun createSolidBackground(
        width: Int,
        height: Int,
        color: Int
    ): Bitmap {
        require(width > 0 && height > 0) {
            "Background dimensions must be positive"
        }

        return Bitmap.createBitmap(
            width,
            height,
            Bitmap.Config.ARGB_8888
        ).apply {
            eraseColor(color)
        }
    }

    fun createGradientBackground(
        width: Int,
        height: Int,
        startColor: Int,
        endColor: Int
    ): Bitmap {
        require(width > 0 && height > 0) {
            "Background dimensions must be positive"
        }

        val bitmap = Bitmap.createBitmap(
            width,
            height,
            Bitmap.Config.ARGB_8888
        )

        val canvas = Canvas(bitmap)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = android.graphics.LinearGradient(
                0f,
                0f,
                0f,
                height.toFloat(),
                startColor,
                endColor,
                android.graphics.Shader.TileMode.CLAMP
            )
        }

        canvas.drawRect(
            0f,
            0f,
            width.toFloat(),
            height.toFloat(),
            paint
        )

        paint.shader = null
        paint.reset()

        return bitmap
    }

    /**
     * Scales an image to cover the requested dimensions,
     * then center-crops it to the exact output size.
     *
     * The original image is never recycled or modified.
     */
    fun loadImageBackground(
        image: Bitmap,
        width: Int,
        height: Int
    ): Bitmap {
        require(!image.isRecycled) {
            "Background image is recycled"
        }
        require(width > 0 && height > 0) {
            "Background dimensions must be positive"
        }
        require(image.width > 0 && image.height > 0) {
            "Source image dimensions must be positive"
        }

        val scale = max(
            width.toFloat() / image.width,
            height.toFloat() / image.height
        )

        val scaledWidth = max(
            width,
            (image.width * scale).toInt()
        )

        val scaledHeight = max(
            height,
            (image.height * scale).toInt()
        )

        val scaledBitmap = Bitmap.createScaledBitmap(
            image,
            scaledWidth,
            scaledHeight,
            true
        )

        try {
            val cropX = (scaledWidth - width) / 2
            val cropY = (scaledHeight - height) / 2

            val outputPixels = IntArray(width * height)

            scaledBitmap.getPixels(
                outputPixels,
                0,
                width,
                cropX,
                cropY,
                width,
                height
            )

            return Bitmap.createBitmap(
                outputPixels,
                width,
                height,
                Bitmap.Config.ARGB_8888
            )
        } finally {
            if (scaledBitmap !== image) {
                scaledBitmap.recycle()
            }
        }
    }
}
