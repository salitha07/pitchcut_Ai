package com.pitchcut.pitchcut_ai.media3

import android.graphics.Bitmap
import android.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class TimelineBackgroundFactoryTest {

    @Test
    fun `none background returns null`() {
        val result = TimelineBackgroundFactory.create(
            TimelineBackground("none"),
            100,
            100
        )

        assertNull(result)
    }

    @Test
    fun `solid background creates requested color`() {
        val result = TimelineBackgroundFactory.create(
            TimelineBackground(
                type = "solid",
                solidColor = Color.RED.toLong() and 0xFFFFFFFFL
            ),
            4,
            4
        )!!

        try {
            assertEquals(4, result.width)
            assertEquals(4, result.height)
            assertEquals(Color.RED, result.getPixel(0, 0))
        } finally {
            result.recycle()
        }
    }

    @Test
    fun `gradient background creates requested dimensions`() {
        val result = TimelineBackgroundFactory.create(
            TimelineBackground(
                type = "gradient",
                gradientStartColor = Color.RED.toLong() and 0xFFFFFFFFL,
                gradientEndColor = Color.BLUE.toLong() and 0xFFFFFFFFL
            ),
            10,
            20
        )!!

        try {
            assertEquals(10, result.width)
            assertEquals(20, result.height)
            assertEquals(
                false,
                result.getPixel(5, 0) == result.getPixel(5, 19)
            )
        } finally {
            result.recycle()
        }
    }

    @Test
    fun `image background decodes and scales image file`() {
        val source = Bitmap.createBitmap(
            4,
            2,
            Bitmap.Config.ARGB_8888
        ).apply {
            eraseColor(Color.GREEN)
        }

        val file = File.createTempFile("background", ".png")

        try {
            file.outputStream().use {
                source.compress(Bitmap.CompressFormat.PNG, 100, it)
            }

            val result = TimelineBackgroundFactory.create(
                TimelineBackground(
                    type = "image",
                    imagePath = file.absolutePath
                ),
                8,
                8
            )!!

            try {
                assertEquals(8, result.width)
                assertEquals(8, result.height)
                assertEquals(Color.GREEN, result.getPixel(4, 4))
            } finally {
                result.recycle()
            }
        } finally {
            source.recycle()
            file.delete()
        }
    }

    @Test
    fun `missing image file returns file not found`() {
        val error = assertThrows(TimelineExportException::class.java) {
            TimelineBackgroundFactory.create(
                TimelineBackground(
                    type = "image",
                    imagePath = File(
                        System.getProperty("java.io.tmpdir"),
                        "missing-background-image.png"
                    ).absolutePath
                ),
                8,
                8
            )
        }

        assertEquals(ErrorCodes.FILE_NOT_FOUND, error.code)
    }

    @Test
    fun `invalid image file returns unsupported format`() {
        val file = File.createTempFile("invalid-background", ".png")

        try {
            file.writeText("not an image")

            val error = assertThrows(TimelineExportException::class.java) {
                TimelineBackgroundFactory.create(
                    TimelineBackground(
                        type = "image",
                        imagePath = file.absolutePath
                    ),
                    8,
                    8
                )
            }

            assertEquals(ErrorCodes.UNSUPPORTED_FORMAT, error.code)
        } finally {
            file.delete()
        }
    }

    @Test
    fun `all supported presets create gradient backgrounds`() {
        val presetIds = listOf("studio", "sunset", "ocean", "forest")

        for (presetId in presetIds) {
            val result = TimelineBackgroundFactory.create(
                TimelineBackground(
                    type = "preset",
                    presetId = presetId
                ),
                16,
                24
            )!!

            try {
                assertEquals(16, result.width)
                assertEquals(24, result.height)
                assertNotEquals(
                    result.getPixel(8, 0),
                    result.getPixel(8, 23)
                )
            } finally {
                result.recycle()
            }
        }
    }

    @Test
    fun `unknown preset is rejected`() {
        val error = assertThrows(TimelineExportException::class.java) {
            TimelineBackgroundFactory.create(
                TimelineBackground(
                    type = "preset",
                    presetId = "unknown"
                ),
                8,
                8
            )
        }

        assertEquals(ErrorCodes.INVALID_RANGE, error.code)
    }
    @Test
    fun `invalid dimensions are rejected`() {
        val error = assertThrows(TimelineExportException::class.java) {
            TimelineBackgroundFactory.create(
                TimelineBackground(
                    type = "solid",
                    solidColor = Color.RED.toLong()
                ),
                0,
                8
            )
        }

        assertEquals(ErrorCodes.INVALID_RANGE, error.code)
    }
}

