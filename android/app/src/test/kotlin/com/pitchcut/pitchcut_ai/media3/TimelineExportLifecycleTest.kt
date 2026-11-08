package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class TimelineExportLifecycleTest {
    private class Callback : ExportService.Callback {
        val errors = mutableListOf<String>()
        var successes = 0
        override fun onSuccess(outputPath: String) { successes++ }
        override fun onError(errorCode: String, message: String) { errors.add(errorCode) }
    }

    private class Sink : EventChannel.EventSink {
        val errors = mutableListOf<String>()
        val events = mutableListOf<Any?>()
        var ends = 0
        override fun success(event: Any?) { events.add(event) }
        override fun error(code: String, message: String?, details: Any?) { errors.add(code) }
        override fun endOfStream() { ends++ }
    }

    private fun request() = TimelineExportRequest.parse(mapOf(
        "targetHeight" to 720,
        "items" to listOf(mapOf("path" to "/test.mp4", "startMs" to 0, "endMs" to 1000))
    ))

    private fun awaitMain(condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (!condition() && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(5)
        }
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("Timed out awaiting export callback", condition())
    }

    @Test fun timelineUsesLegacyBusyGuardAndCancellationSettlesOnlyOnce() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val context: Context = RuntimeEnvironment.getApplication()
        val service = ExportService(context) {
            entered.countDown()
            check(release.await(5, TimeUnit.SECONDS))
            TimelineSourceMetadata(2000, 1920, 1080, 0, true)
        }
        val callback = Callback()
        val sink = Sink()
        service.exportTimeline(request(), sink, callback)
        try {
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val legacyBusy = Callback()
            val timelineBusy = Callback()
            service.export(listOf("/legacy.mp4"), 720, emptyList(), sink, legacyBusy)
            service.exportTimeline(request(), sink, timelineBusy)
            awaitMain { legacyBusy.errors.size == 1 && timelineBusy.errors.size == 1 }
            assertEquals(listOf(ErrorCodes.EXPORT_FAILED), legacyBusy.errors)
            assertEquals(listOf(ErrorCodes.EXPORT_FAILED), timelineBusy.errors)
            assertTrue(sink.errors.isEmpty())
            assertEquals(0, sink.ends)
            var cancellationsSettled = 0
            service.cancelExport(sink) { cancellationsSettled++ }
            service.cancelExport(sink) { cancellationsSettled++ }
            release.countDown()
            awaitMain { cancellationsSettled == 2 }
            assertEquals(listOf(ErrorCodes.CANCELLED), callback.errors)
            assertEquals(listOf(ErrorCodes.CANCELLED), sink.errors)
            assertEquals(1, sink.ends)
            assertTrue(sink.events.isEmpty())
            assertEquals(0, callback.successes)
            // The shared guard is released only after cleanup, then legacy validation
            // still rejects 480p rather than adopting the new timeline settings.
            val legacyAfter = Callback()
            service.export(listOf("/legacy.mp4"), 480, emptyList(), null, legacyAfter)
            awaitMain { legacyAfter.errors.isNotEmpty() }
            assertEquals(listOf(ErrorCodes.INVALID_RANGE), legacyAfter.errors)
        } finally {
            release.countDown()
            service.cancelExport(null) {}
            shadowOf(Looper.getMainLooper()).idle()
        }
    }

    @Test fun metadataFailureEndsStreamAndReleasesGuardForNextRequest() {
        val context: Context = RuntimeEnvironment.getApplication()
        val service = ExportService(context) {
            throw TimelineExportException(ErrorCodes.UNSUPPORTED_FORMAT, "Unreadable media")
        }
        repeat(2) {
            val callback = Callback()
            val sink = Sink()
            service.exportTimeline(request(), sink, callback)
            awaitMain { callback.errors.isNotEmpty() }
            assertEquals(listOf(ErrorCodes.UNSUPPORTED_FORMAT), callback.errors)
            assertEquals(listOf(ErrorCodes.UNSUPPORTED_FORMAT), sink.errors)
            assertEquals(1, sink.ends)
            assertEquals(0, callback.successes)
        }
    }

    @Test fun streamCancellationSuppressesErrorAndCompletesMethodOnce() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val service = ExportService(RuntimeEnvironment.getApplication()) {
            entered.countDown()
            check(release.await(5, TimeUnit.SECONDS))
            TimelineSourceMetadata(2000, 1920, 1080, 0, false)
        }
        val callback = Callback()
        val sink = Sink()
        service.exportTimeline(request(), sink, callback)
        try {
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            service.onProgressStreamCancelled(sink)
            release.countDown()
            awaitMain { callback.errors.isNotEmpty() }
            assertEquals(listOf(ErrorCodes.CANCELLED), callback.errors)
            assertTrue(sink.errors.isEmpty())
            assertEquals(0, sink.ends)
        } finally {
            release.countDown()
            service.cancelExport(null) {}
            shadowOf(Looper.getMainLooper()).idle()
        }
    }
}
