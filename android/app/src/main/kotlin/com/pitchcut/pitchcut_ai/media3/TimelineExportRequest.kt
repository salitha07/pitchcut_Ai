package com.pitchcut.pitchcut_ai.media3

internal class TimelineExportException(val code: String, message: String) : Exception(message)

internal data class TimelineCrop(
    val left: Double, val top: Double, val right: Double, val bottom: Double
) {
    // Media3 uses bottom-left-origin normalized device coordinates.
    fun toNdc(): List<Float> = listOf(
        (2 * left - 1).toFloat(), (2 * right - 1).toFloat(),
        (1 - 2 * bottom).toFloat(), (1 - 2 * top).toFloat()
    )
}

internal data class TimelineBackground(
    val type: String,
    val imagePath: String? = null,
    val solidColor: Long? = null,
    val gradientStartColor: Long? = null,
    val gradientEndColor: Long? = null,
    val presetId: String? = null
)
internal data class TimelineExportItem(
    val path: String,
    val startMs: Long,
    val endMs: Long,
    val rotationDegrees: Int,
    val crop: TimelineCrop?,
    val background: TimelineBackground = TimelineBackground(type = "none")
)

internal data class TimelineExportRequest(
    val items: List<TimelineExportItem>, val targetHeight: Int, val durationMs: Long,
    val captions: List<ExportService.Caption> = emptyList()
) {
    companion object {
        private fun invalid(message: String): Nothing =
            throw TimelineExportException(ErrorCodes.INVALID_RANGE, message)

        private fun integer(raw: Any?, label: String): Long {
            if (raw is Byte || raw is Short || raw is Int || raw is Long) {
                return (raw as Number).toLong()
            }
            if (raw !is Double && raw !is Float) invalid("$label must be an integer")
            val value = (raw as Number).toDouble()
            // Long.MAX_VALUE rounds up as Double. Use an exclusive upper bound.
            if (!value.isFinite() || value % 1.0 != 0.0 ||
                value < Long.MIN_VALUE.toDouble() || value >= Long.MAX_VALUE.toDouble()) {
                invalid("$label must be an exact integer in range")
            }
            return value.toLong()
        }

        private fun parseBackground(
            raw: Any?,
            label: String
        ): TimelineBackground {
            if (raw == null) return TimelineBackground(type = "none")

            val map = raw as? Map<*, *>
                ?: invalid("$label must be a map")

            val type = map["type"] as? String
                ?: invalid("$label.type must be a string")

            if (type !in setOf("none", "image", "solid", "gradient", "preset")) {
                invalid("$label.type is not supported")
            }

            val imagePath = map["imagePath"]?.let {
                it as? String ?: invalid("$label.imagePath must be a string")
            }

            fun color(key: String): Long? {
                val rawColor = map[key] ?: return null
                val value = integer(rawColor, "$label.$key")
                if (value !in 0L..0xFFFFFFFFL) {
                    invalid("$label.$key must be an unsigned 32-bit color")
                }
                return value
            }

            val solidColor = color("solidColor")
            val gradientStartColor = color("gradientStartColor")
            val gradientEndColor = color("gradientEndColor")

            val presetId = map["presetId"]?.let {
                it as? String ?: invalid("$label.presetId must be a string")
            }

            when (type) {
                "image" -> if (imagePath.isNullOrBlank()) {
                    invalid("$label.imagePath is required for image background")
                }
                "solid" -> if (solidColor == null) {
                    invalid("$label.solidColor is required for solid background")
                }
                "gradient" -> if (
                    gradientStartColor == null || gradientEndColor == null
                ) {
                    invalid("$label requires both gradient colors")
                }
                "preset" -> if (presetId.isNullOrBlank()) {
                    invalid("$label.presetId is required for preset background")
                }
            }

            return TimelineBackground(
                type = type,
                imagePath = imagePath,
                solidColor = solidColor,
                gradientStartColor = gradientStartColor,
                gradientEndColor = gradientEndColor,
                presetId = presetId
            )
        }
        fun parse(arguments: Any?): TimelineExportRequest {
            val args = arguments as? Map<*, *> ?: invalid("Expected timeline arguments")
            val height = integer(args["targetHeight"], "targetHeight")
            if (height !in listOf(480L, 720L, 1080L)) invalid("targetHeight must be 480, 720, or 1080")
            val rawItems = args["items"] as? List<*> ?: invalid("items must be a list")
            if (rawItems.isEmpty()) invalid("items cannot be empty")
            var total = 0L
            val items = rawItems.mapIndexed { index, raw ->
                val item = raw as? Map<*, *> ?: invalid("items[$index] must be a map")
                val path = item["path"] as? String
                if (path.isNullOrBlank()) {
                    throw TimelineExportException(ErrorCodes.FILE_NOT_FOUND, "items[$index].path is required")
                }
                val start = integer(item["startMs"], "items[$index].startMs")
                val end = integer(item["endMs"], "items[$index].endMs")
                if (start < 0 || end <= start || end > Long.MAX_VALUE / 1000) {
                    invalid("items[$index] has an invalid or overflowing time range")
                }
                val rotation = integer(
                    if (item.containsKey("rotationDegrees")) item["rotationDegrees"] else 0,
                    "rotationDegrees"
                )
                if (rotation !in listOf(0L, 90L, 180L, 270L)) invalid("Invalid rotationDegrees")
                val crop = item["crop"]?.let { rawCrop ->
                    val map = rawCrop as? Map<*, *> ?: invalid("crop must be a map")
                    fun edge(key: String): Double {
                        val value = (map[key] as? Number)?.toDouble() ?: invalid("crop.$key must be numeric")
                        if (!value.isFinite() || value < 0 || value > 1) invalid("crop.$key must be in [0, 1]")
                        return value
                    }
                    TimelineCrop(edge("left"), edge("top"), edge("right"), edge("bottom")).also {
                        if (it.right - it.left < 0.05 || it.bottom - it.top < 0.05) {
                            invalid("Crop dimensions must each be at least 0.05")
                        }
                    }
                }
                val background = parseBackground(
                    item["background"],
                    "items[${index}].background"
                )

                val duration = end - start
                if (total > Long.MAX_VALUE / 1000 - duration) invalid("Timeline duration overflows microseconds")
                total += duration
                TimelineExportItem(
                    path = path,
                    startMs = start,
                    endMs = end,
                    rotationDegrees = rotation.toInt(),
                    crop = crop,
                    background = background
                )
            }
            val captions = (args["captions"] as? List<*>)?.mapIndexedNotNull { index, raw ->
                val caption = raw as? Map<*, *> ?: invalid("captions[$index] must be a map")
                val start = integer(caption["startMs"], "captions[$index].startMs")
                val end = integer(caption["endMs"], "captions[$index].endMs")
                val text = caption["text"] as? String
                    ?: invalid("captions[$index].text must be a string")
                if (start < 0 || end <= start || end > Long.MAX_VALUE / 1000 || text.isBlank()) {
                    invalid("captions[$index] has invalid timestamps or empty text")
                }
                if (start >= total) null else ExportService.Caption(start, end, text)
            }?.sortedBy { it.startMs } ?: run {
                if (args["captions"] == null) emptyList()
                else invalid("captions must be a list")
            }
            return TimelineExportRequest(items, height.toInt(), total, captions)
        }
    }
}

