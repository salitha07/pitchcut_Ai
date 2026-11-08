package com.pitchcut.pitchcut_ai.media3

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrimOutputCleanupTest {
    @Test
    fun failedTrimCleanupDeletesPartialOutput() {
        val output = File.createTempFile("pitchcut-trim-test-", ".mp4")
        try {
            assertTrue(output.exists())
            deleteTrimOutput(output)
            assertFalse(output.exists())
        } finally {
            output.delete()
        }
    }

    @Test
    fun cleanupAcceptsMissingOutput() {
        deleteTrimOutput(null)
        deleteTrimOutput(File("missing-trim-output.mp4"))
    }
}
