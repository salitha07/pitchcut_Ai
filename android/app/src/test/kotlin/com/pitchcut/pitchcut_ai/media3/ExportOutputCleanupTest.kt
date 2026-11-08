package com.pitchcut.pitchcut_ai.media3

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExportOutputCleanupTest {
    @Test
    fun deletesTemporaryExportOutput() {
        val output = File.createTempFile("pitchcut-export-test-", ".mp4")
        try {
            assertTrue(output.exists())
            assertTrue(deleteTemporaryOutput(output))
            assertFalse(output.exists())
        } finally {
            output.delete()
        }
    }

    @Test
    fun cleanupAcceptsMissingOutput() {
        assertTrue(deleteTemporaryOutput(null))
        assertTrue(deleteTemporaryOutput(File("missing-export-output.mp4")))
    }
}
