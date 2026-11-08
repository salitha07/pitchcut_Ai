package com.pitchcut.pitchcut_ai.media3

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LoudnessWindowAccumulatorTest {
    @Test
    fun oneSecondOfInterleavedStereoProducesTenWindowsAcrossBuffers() {
        val accumulator = LoudnessWindowAccumulator(sampleRate = 48_000, channelCount = 2)
        var framesWritten = 0
        while (framesWritten < 48_000) {
            val chunkFrames = minOf(137, 48_000 - framesWritten)
            val chunk = ByteBuffer.allocate(chunkFrames * 2 * Short.SIZE_BYTES)
                .order(ByteOrder.LITTLE_ENDIAN)
            repeat(chunkFrames) { frame ->
                val value = ((framesWritten + frame) % 20_000 - 10_000).toShort()
                chunk.putShort(value)
                chunk.putShort(value)
            }
            chunk.flip()
            accumulator.addPcm16(chunk)
            framesWritten += chunkFrames
        }

        val samples = accumulator.finish()
        assertEquals(10, samples.size)
        assertTrue(samples.all { it in 0.0..1.0 && !it.isNaN() })
    }

    @Test
    fun finalPartialWindowIsIncludedAndSilenceIsZero() {
        val accumulator = LoudnessWindowAccumulator(sampleRate = 48_000, channelCount = 1)
        val pcm = ByteBuffer.allocate(48_000 / 10 * 2 + 48_000 / 20 * 2)
            .order(ByteOrder.LITTLE_ENDIAN)
        repeat(48_000 / 10 + 48_000 / 20) { pcm.putShort(0) }
        pcm.flip()

        val samples = accumulator.also { it.addPcm16(pcm) }.finish()

        assertEquals(2, samples.size)
        assertTrue(samples.all { it == 0.0 })
    }
}
