
package com.pitchcut.pitchcut_ai.media3

import android.graphics.Bitmap
import android.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class AiBackgroundCompositorTest {

    @Test
    fun `solid background creates bitmap with requested color`() {
        val bitmap = AiBackgroundCompositor.createSolidBackground(
            width = 4,
            height = 4,
            color = Color.RED
        )

        try {
            assertEquals(4, bitmap.width)
            assertEquals(4, bitmap.height)
            assertEquals(Color.RED, bitmap.getPixel(0, 0))
            assertEquals(Color.RED, bitmap.getPixel(3, 3))
        } finally {
            bitmap.recycle()
        }
    }

    @Test
    fun `gradient background creates bitmap with requested dimensions`() {
        val bitmap = AiBackgroundCompositor.createGradientBackground(
            width = 10,
            height = 20,
            startColor = Color.RED,
            endColor = Color.BLUE
        )

        try {
            assertEquals(10, bitmap.width)
            assertEquals(20, bitmap.height)

            assertNotEquals(
                bitmap.getPixel(5, 0),
                bitmap.getPixel(5, 19)
            )
        } finally {
            bitmap.recycle()
        }
    }

    @Test
    fun `full foreground confidence preserves foreground color`() {
        val foreground = solidBitmap(2, 2, Color.RED)
        val background = solidBitmap(2, 2, Color.BLUE)

        try {
            val result = AiBackgroundCompositor.composite(
                foreground = foreground,
                mask = FloatArray(4) { 1f },
                maskWidth = 2,
                maskHeight = 2,
                background = background
            )

            try {
                assertEquals(Color.RED, result.getPixel(0, 0))
            } finally {
                result.recycle()
            }
        } finally {
            foreground.recycle()
            background.recycle()
        }
    }

    @Test
    fun `zero foreground confidence shows background color`() {
        val foreground = solidBitmap(2, 2, Color.RED)
        val background = solidBitmap(2, 2, Color.BLUE)

        try {
            val result = AiBackgroundCompositor.composite(
                foreground = foreground,
                mask = FloatArray(4) { 0f },
                maskWidth = 2,
                maskHeight = 2,
                background = background
            )

            try {
                assertEquals(Color.BLUE, result.getPixel(0, 0))
            } finally {
                result.recycle()
            }
        } finally {
            foreground.recycle()
            background.recycle()
        }
    }

    @Test
    fun `partial confidence blends foreground and background`() {
        val foreground = solidBitmap(1, 1, Color.RED)
        val background = solidBitmap(1, 1, Color.BLUE)

        try {
            val result = AiBackgroundCompositor.composite(
                foreground = foreground,
                mask = floatArrayOf(0.5f),
                maskWidth = 1,
                maskHeight = 1,
                background = background
            )

            try {
                val pixel = result.getPixel(0, 0)

                assertEquals(127, Color.red(pixel))
                assertEquals(0, Color.green(pixel))
                assertEquals(127, Color.blue(pixel))
            } finally {
                result.recycle()
            }
        } finally {
            foreground.recycle()
            background.recycle()
        }
    }

    @Test
    fun `mask dimensions must match mask array size`() {
        val foreground = solidBitmap(2, 2, Color.RED)
        val background = solidBitmap(2, 2, Color.BLUE)

        try {
            assertThrows(IllegalArgumentException::class.java) {
                AiBackgroundCompositor.composite(
                    foreground = foreground,
                    mask = FloatArray(3) { 1f },
                    maskWidth = 2,
                    maskHeight = 2,
                    background = background
                )
            }
        } finally {
            foreground.recycle()
            background.recycle()
        }
    }

    @Test
    fun `image background scales to requested dimensions`() {
        val image = solidBitmap(4, 2, Color.GREEN)

        try {
            val result = AiBackgroundCompositor.loadImageBackground(
                image = image,
                width = 8,
                height = 8
            )

            try {
                assertEquals(8, result.width)
                assertEquals(8, result.height)
                assertEquals(Color.GREEN, result.getPixel(4, 4))
            } finally {
                result.recycle()
            }
        } finally {
            image.recycle()
        }
    }

    @Test
    fun `mask dimensions must be positive`() {
        val foreground = solidBitmap(2, 2, Color.RED)
        val background = solidBitmap(2, 2, Color.BLUE)

        try {
            assertThrows(IllegalArgumentException::class.java) {
                AiBackgroundCompositor.composite(
                    foreground = foreground,
                    mask = FloatArray(0),
                    maskWidth = 0,
                    maskHeight = 2,
                    background = background
                )
            }
        } finally {
            foreground.recycle()
            background.recycle()
        }
    }

    private fun solidBitmap(
        width: Int,
        height: Int,
        color: Int
    ): Bitmap {
        return Bitmap.createBitmap(
            width,
            height,
            Bitmap.Config.ARGB_8888
        ).apply {
            eraseColor(color)
        }
    }
}
