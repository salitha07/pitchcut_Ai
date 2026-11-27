
package com.pitchcut.pitchcut_ai.media3

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File

/**
 * Creates a background bitmap from a timeline background configuration.
 *
 * The caller owns the returned bitmap and must recycle it when finished.
 */
internal object TimelineBackgroundFactory {

    fun create(
        background: TimelineBackground,
        width: Int,
        height: Int
    ): Bitmap? {
        if (background.type == "none") {
            return null
        }

        if (width <= 0 || height <= 0) {
            invalid("Background dimensions must be positive")
        }

        return when (background.type) {
            "solid" -> {
                val color = background.solidColor
                    ?: invalid("Solid background color is required")

                AiBackgroundCompositor.createSolidBackground(
                    width = width,
                    height = height,
                    color = color.toInt()
                )
            }

            "gradient" -> {
                val startColor = background.gradientStartColor
                    ?: invalid("Gradient start color is required")

                val endColor = background.gradientEndColor
                    ?: invalid("Gradient end color is required")

                AiBackgroundCompositor.createGradientBackground(
                    width = width,
                    height = height,
                    startColor = startColor.toInt(),
                    endColor = endColor.toInt()
                )
            }

            "image" -> createImage(background, width, height)

            "preset" -> createPreset(background, width, height)
            else -> invalid("Unsupported background type: ${background.type}")
        }
    }


    private fun createPreset(
        background: TimelineBackground,
        width: Int,
        height: Int
    ): Bitmap {
        val colors = when (background.presetId) {
            "studio" -> Pair(0xFF111827.toInt(), 0xFF374151.toInt())
            "sunset" -> Pair(0xFF7C2D12.toInt(), 0xFFEC4899.toInt())
            "ocean" -> Pair(0xFF082F49.toInt(), 0xFF0EA5E9.toInt())
            "forest" -> Pair(0xFF052E16.toInt(), 0xFF22C55E.toInt())
            else -> invalid("Unknown background preset: ${background.presetId}")
        }

        return AiBackgroundCompositor.createGradientBackground(
            width = width,
            height = height,
            startColor = colors.first,
            endColor = colors.second
        )
    }
    private fun createImage(
        background: TimelineBackground,
        width: Int,
        height: Int
    ): Bitmap {
        val path = background.imagePath

        if (path.isNullOrBlank()) {
            invalid("Image background path is required")
        }

        val file = File(path)

        if (!file.exists() || !file.isFile) {
            throw TimelineExportException(
                ErrorCodes.FILE_NOT_FOUND,
                "Background image file was not found"
            )
        }

        if (!hasSupportedImageSignature(file)) {
            throw TimelineExportException(
                ErrorCodes.UNSUPPORTED_FORMAT,
                "Background image has an invalid or unsupported format"
            )
        }

        val decoded = BitmapFactory.decodeFile(file.absolutePath)
            ?: throw TimelineExportException(
                ErrorCodes.UNSUPPORTED_FORMAT,
                "Background image could not be decoded"
            )

        try {
            return AiBackgroundCompositor.loadImageBackground(
                image = decoded,
                width = width,
                height = height
            )
        } finally {
            decoded.recycle()
        }
    }

    /**
     * Checks common image file signatures before decoding.
     * Supported signatures: PNG, JPEG, GIF and WebP.
     */
    private fun hasSupportedImageSignature(file: File): Boolean {
        val header = ByteArray(12)

        val count = file.inputStream().use { input ->
            var offset = 0

            while (offset < header.size) {
                val read = input.read(
                    header,
                    offset,
                    header.size - offset
                )

                if (read <= 0) break
                offset += read
            }

            offset
        }

        fun matches(vararg bytes: Int): Boolean {
            return count >= bytes.size &&
                bytes.indices.all { index ->
                    (header[index].toInt() and 0xFF) == bytes[index]
                }
        }

        val isPng = matches(
            0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A
        )

        val isJpeg = matches(
            0xFF, 0xD8, 0xFF
        )

        val isGif = matches(
            0x47, 0x49, 0x46, 0x38
        ) && (
            matches(0x47, 0x49, 0x46, 0x38, 0x37, 0x61) ||
                matches(0x47, 0x49, 0x46, 0x38, 0x39, 0x61)
            )

        val isWebP = count >= 12 &&
            matches(0x52, 0x49, 0x46, 0x46) &&
            matchesAt(
                offset = 8,
                header = header,
                count = count,
                bytes = intArrayOf(0x57, 0x45, 0x42, 0x50)
            )

        return isPng || isJpeg || isGif || isWebP
    }

    private fun matchesAt(
        offset: Int,
        header: ByteArray,
        count: Int,
        bytes: IntArray
    ): Boolean {
        return count >= offset + bytes.size &&
            bytes.indices.all { index ->
                (header[offset + index].toInt() and 0xFF) == bytes[index]
            }
    }

    private fun invalid(message: String): Nothing {
        throw TimelineExportException(
            ErrorCodes.INVALID_RANGE,
            message
        )
    }
}

