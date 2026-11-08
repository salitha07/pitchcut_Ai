package com.pitchcut.pitchcut_ai.media3

import org.junit.Assert.*
import org.junit.Test

class TimelineExportRequestTest {
    private fun item(vararg overrides: Pair<String, Any?>): Map<String, Any?> = mapOf(
        "path" to "/source.mp4", "startMs" to 0L, "endMs" to 1000L,
        "rotationDegrees" to 0
    ) + overrides

    private fun parse(items: Any? = listOf(item()), height: Any? = 720) =
        TimelineExportRequest.parse(mapOf("items" to items, "targetHeight" to height))

    private fun rejects(code: String = ErrorCodes.INVALID_RANGE, action: () -> Unit) {
        val error = assertThrows(TimelineExportException::class.java, action)
        assertEquals(code, error.code)
    }

    @Test fun acceptsAllHeightsAndRotations() {
        for (height in listOf(480, 720, 1080)) {
            val request = parse(listOf(0, 90, 180, 270).map { item("rotationDegrees" to it) }, height)
            assertEquals(height, request.targetHeight)
            assertEquals(4000L, request.durationMs)
        }
    }

    @Test fun preservesOrderRepeatedPathsAndIndependentRanges() {
        val request = parse(listOf(item(), item("path" to "/other.mp4"),
            item("startMs" to 1000L, "endMs" to 2000L)))
        assertEquals(listOf("/source.mp4", "/other.mp4", "/source.mp4"), request.items.map { it.path })
        assertEquals(listOf(0L, 0L, 1000L), request.items.map { it.startMs })
    }

    @Test fun rejectsEmptyMalformedAndUnsupportedSettings() {
        rejects { parse(emptyList<Any>()) }
        rejects { parse("wrong") }
        rejects { parse(listOf(null)) }
        for (height in listOf(null, 0, 721, 720.5, "720")) rejects { parse(height = height) }
        for (rotation in listOf(null, -90, 45, 360, 90.5, "90")) {
            rejects { parse(listOf(item("rotationDegrees" to rotation))) }
        }
        rejects(ErrorCodes.FILE_NOT_FOUND) { parse(listOf(item("path" to " "))) }
    }

    @Test fun exactIntegersDoNotLoseLongPrecision() {
        val start = 9_007_199_254_740_001L
        val request = parse(listOf(item("startMs" to start, "endMs" to start + 1)))
        assertEquals(start, request.items.single().startMs)
        assertEquals(1L, request.durationMs)
        assertEquals(1000L, parse(listOf(item("endMs" to 1000.0))).durationMs)
    }

    @Test fun rejectsInvalidAndOverflowingTimes() {
        for (end in listOf(Double.NaN, Double.POSITIVE_INFINITY, 0L, -1, 1.5, Long.MAX_VALUE,
            Long.MAX_VALUE.toDouble(), "1000")) {
            rejects { parse(listOf(item("endMs" to end))) }
        }
        rejects { parse(listOf(item("startMs" to -1))) }
        val huge = item("endMs" to Long.MAX_VALUE / 1000)
        rejects { parse(listOf(huge, huge)) }
    }

    @Test fun cropUsesRotatedTopLeftCoordinates() {
        val crop = TimelineCrop(0.1, 0.2, 0.7, 0.9)
        assertArrayEquals(floatArrayOf(-0.8f, 0.4f, -0.8f, 0.6f), crop.toNdc().toFloatArray(), 0.00001f)
        assertEquals(listOf(-1f, 1f, -1f, 1f), TimelineCrop(0.0, 0.0, 1.0, 1.0).toNdc())
    }

    @Test fun validatesEveryCropEdgeAndMinimumDimension() {
        val full = mapOf("left" to 0.0, "top" to 0.0, "right" to 1.0, "bottom" to 1.0)
        for (edge in full.keys) {
            for (value in listOf(null, Double.NaN, Double.NEGATIVE_INFINITY, -0.1, 1.1, "0")) {
                rejects { parse(listOf(item("crop" to (full + (edge to value))))) }
            }
        }
        rejects { parse(listOf(item("crop" to (full + ("right" to 0.049))))) }
        rejects { parse(listOf(item("crop" to (full + ("bottom" to 0.049))))) }
        rejects { parse(listOf(item("crop" to (full + ("left" to 1.0))))) }
        rejects { parse(listOf(item("crop" to "wrong"))) }
        val request = parse(listOf(item("crop" to (full + ("right" to 0.05)))))
        assertEquals(0.05, request.items.single().crop!!.right, 0.0)
    }
}
