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

internal data class TimelineExportItem(
    val path: String,
    val startMs: Long,
    val endMs: Long,
    val rotationDegrees: Int,
    val crop: TimelineCrop?
)

internal data class TimelineExportRequest(
    val items: List<TimelineExportItem>, val targetHeight: Int, val durationMs: Long
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
                val duration = end - start
                if (total > Long.MAX_VALUE / 1000 - duration) invalid("Timeline duration overflows microseconds")
                total += duration
                TimelineExportItem(path, start, end, rotation.toInt(), crop)
            }
            return TimelineExportRequest(items, height.toInt(), total)
        }
    }
}
