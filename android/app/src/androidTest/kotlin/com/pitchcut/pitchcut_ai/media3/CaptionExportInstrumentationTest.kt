package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaCodec.BufferInfo
import android.media.MediaCodecInfo.CodecProfileLevel
import android.media.MediaFormat.KEY_AAC_PROFILE
import android.media.MediaFormat.MIMETYPE_AUDIO_AAC
import android.net.Uri
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CaptionExportInstrumentationTest {
    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun captionsFitOutputAspectRatiosAndPreserveAudio() {
        val shapes = listOf(
            Triple("landscape", 320, 180),
            Triple("portrait", 180, 320),
            Triple("square", 240, 240),
            Triple("four-three", 320, 240)
        )
        val captionBounds = mutableListOf<PixelBounds>()

        for ((name, width, height) in shapes) {
            val source = createAudioVideoMp4WithPartialDuration(
                context.cacheDir,
                channelCount = 1,
                videoWidth = width,
                videoHeight = height,
                videoDurationMs = 7_000L
            )
            var plain: File? = null
            var captioned: File? = null
            try {
                val plainFile = export(source, emptyList())
                plain = plainFile
                val captionedFile = export(
                    source,
                    listOf(
                        mapOf("startMs" to 0L, "endMs" to 3_000L, "text" to "Hello"),
                        mapOf("startMs" to 3_000L, "endMs" to 6_000L, "text" to "PitchCut")
                    )
                )
                captioned = captionedFile

                val metadata = MediaMetadataRetriever()
                try {
                    metadata.setDataSource(captionedFile.absolutePath)
                    val expectedWidth = (width.toDouble() * 720 / height).toInt()
                    val outputWidth = metadata
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                        ?.toIntOrNull() ?: error("$name output has no width")
                    val outputHeight = metadata
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                        ?.toIntOrNull() ?: error("$name output has no height")
                    assertTrue(
                        "$name output width $outputWidth should be near $expectedWidth",
                        kotlin.math.abs(outputWidth - expectedWidth) <= 4
                    )
                    assertEquals(720, outputHeight)
                    assertEquals(
                        "yes",
                        metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)
                    )
                    assertTrue(
                        "Export duration should remain close to the source duration",
                        (metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                            ?.toLongOrNull() ?: 0L) >= 6_800L
                    )
                } finally {
                    metadata.release()
                }

                val hello = findCaptionBounds(plainFile, captionedFile, 1_500L)
                val pitchCut = findCaptionBounds(plainFile, captionedFile, 4_500L)
                assertCaptionBoundsInsideFrame(name, hello)
                assertCaptionBoundsInsideFrame(name, pitchCut)
                assertTrue(
                    "$name caption should be centered horizontally",
                    kotlin.math.abs(hello.centerX - hello.frameWidth / 2f) < hello.frameWidth * 0.04f
                )
                assertTrue("$name caption needs a dark background box", hello.darkPixels > 100)
                assertTrue("$name caption needs visible white text", hello.whitePixels > 10)
                assertTrue(
                    "$name PitchCut caption should also render",
                    pitchCut.changedPixels > 500
                )
                assertTrue(
                    "$name caption should disappear after 6000 ms",
                    countChangedCaptionPixels(plainFile, captionedFile, 6_500L) < 500
                )
                assertVideoPlaysToCompletion(captionedFile)
                captionBounds.add(hello)
            } finally {
                source.delete()
                plain?.delete()
                captioned?.delete()
            }
        }

        val landscape = captionBounds[0]
        val portrait = captionBounds[1]
        assertTrue(
            "Text and box should not stretch between landscape and portrait",
            kotlin.math.abs(landscape.aspectRatio - portrait.aspectRatio) < 0.25f
        )
        assertTrue(
            "Caption box width should be similar at the same output height",
            kotlin.math.abs(landscape.width - portrait.width) < landscape.width * 0.12f
        )
    }

    @Test
    fun multipleCaptionsIncludingBackToBackCaptionsRenderOnlyWithinTheirIntervals() {
        val source = createSolidColorVideo(context.cacheDir)
        var plainExport: File? = null
        var captionExport: File? = null

        try {
            plainExport = export(source, emptyList())
            captionExport = export(
                source,
                listOf(
                    mapOf("startMs" to 1_000L, "endMs" to 2_000L, "text" to "First caption"),
                    mapOf("startMs" to 2_000L, "endMs" to 3_000L, "text" to "Second caption"),
                    mapOf("startMs" to 4_000L, "endMs" to 5_000L, "text" to "Third caption")
                )
            )

            val beforeCaption = countChangedCaptionPixels(plainExport, captionExport, 500L)
            val firstCaption = countChangedCaptionPixels(plainExport, captionExport, 1_500L)
            val backToBackCaption = countChangedCaptionPixels(plainExport, captionExport, 2_500L)
            val thirdCaption = countChangedCaptionPixels(plainExport, captionExport, 4_500L)
            val afterCaption = countChangedCaptionPixels(plainExport, captionExport, 5_500L)

            assertTrue("First caption should render inside its interval: $firstCaption", firstCaption > 500)
            assertTrue("Back-to-back caption should render inside its interval: $backToBackCaption", backToBackCaption > 500)
            assertTrue("Third caption should render inside its interval: $thirdCaption", thirdCaption > 500)
            assertTrue("Caption should not alter pixels before its interval: $beforeCaption", beforeCaption < 500)
            assertTrue("Caption should disappear after its interval: $afterCaption", afterCaption < 500)
        } finally {
            source.delete()
            plainExport?.delete()
            captionExport?.delete()
        }

    }

    @Test
    fun emptyCaptionsExportSucceedsWithoutChangingTheVideo() {
        val source = createSolidColorVideo(context.cacheDir)
        var firstExport: File? = null
        var secondExport: File? = null

        try {
            firstExport = export(source, emptyList())
            secondExport = export(source, emptyList())

            assertTrue("Empty-caption export should produce a video", firstExport.isFile && firstExport.length() > 0)
            assertTrue(
                "Empty-caption export should produce an unchanged video",
                countChangedCaptionPixels(firstExport, secondExport, 2_000L) < 500
            )
        } finally {
            source.delete()
            firstExport?.delete()
            secondExport?.delete()
        }

    }

    @Test
    fun malformedBlankAndOutOfDurationCaptionsAreSkipped() {
        val source = createSolidColorVideo(context.cacheDir)
        var plain: File? = null
        var filtered: File? = null

        try {
            plain = export(source, emptyList())
            filtered = export(
                source,
                listOf(
                    mapOf("startMs" to 1_000L, "endMs" to 2_000L, "text" to ""),
                    mapOf("startMs" to "1000", "endMs" to 2_000L, "text" to "Wrong type"),
                    mapOf("startMs" to 7_000L, "endMs" to 8_000L, "text" to "After video")
                )
            )
            assertTrue(
                "Skipped captions should not change the output",
                countChangedCaptionPixels(plain, filtered, 1_500L) < 500
            )
        } finally {
            source.delete()
            plain?.delete()
            filtered?.delete()
        }
    }

    @Test
    fun longUnicodeAndOverlappingCaptionsStayInsideTheFrame() {
        val source = createSolidColorVideo(context.cacheDir)
        var plain: File? = null
        var captioned: File? = null
        try {
            val plainFile = export(source, emptyList())
            plain = plainFile
            val captionedFile = export(
                source,
                listOf(
                    mapOf(
                        "startMs" to 0L,
                        "endMs" to 5_000L,
                        "text" to "සිංහල தமிழ் 🎬"
                    ),
                    mapOf(
                        "startMs" to 0L,
                        "endMs" to 5_000L,
                        "text" to "Long caption ".repeat(100)
                    )
                )
            )
            captioned = captionedFile
            val bounds = findCaptionBounds(plainFile, captionedFile, 2_500L)
            assertCaptionBoundsInsideFrame("long Unicode", bounds)
            assertTrue(
                "Long captions must wrap to at most three lines",
                bounds.bottom - bounds.top + 1 < bounds.frameHeight * 0.22f
            )
        } finally {
            source.delete()
            plain?.delete()
            captioned?.delete()
        }
    }

    @Test
    fun rotatedSourceCaptionUsesDisplayedOutputFrame() {
        val source = createSolidColorVideo(
            context.cacheDir,
            width = 320,
            height = 180,
            rotationDegrees = 90
        )
        var plain: File? = null
        var captioned: File? = null
        try {
            plain = export(source, emptyList())
            captioned = export(
                source,
                listOf(mapOf("startMs" to 0L, "endMs" to 5_000L, "text" to "Rotated caption"))
            )
            val plainFile = requireNotNull(plain)
            val captionedFile = requireNotNull(captioned)
            val bounds = findCaptionBounds(plainFile, captionedFile, 2_500L)
            assertTrue(
                "Rotation metadata should produce a portrait displayed frame",
                bounds.frameHeight > bounds.frameWidth
            )
            assertCaptionBoundsInsideFrame("rotated", bounds)
        } finally {
            source.delete()
            plain?.delete()
            captioned?.delete()
        }
    }

    @Test
    fun exportProducesAValidVideoThatPlaysToCompletion() {
        val source = createSolidColorVideo(context.cacheDir, durationMs = 1_200L)
        var exported: File? = null
        var player: ExoPlayer? = null

        try {
            val output = export(source, emptyList())
            exported = output
            assertTrue("Export output must exist and be non-empty", output.isFile && output.length() > 0L)

            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(output.absolutePath)
                assertEquals(
                    "yes",
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO)
                )
                assertTrue(
                    "Export output must have a positive duration",
                    (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull() ?: 0L) > 0L
                )
                val frame = requireNotNull(
                    retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST)
                ) { "Export output contains no decodable video frame" }
                frame.recycle()
            } finally {
                retriever.release()
            }

            val ended = CountDownLatch(1)
            var playbackError: String? = null
            val exoPlayer = ExoPlayer.Builder(context)
                .setLooper(Looper.getMainLooper())
                .build()
            player = exoPlayer
            exoPlayer.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_ENDED) ended.countDown()
                }

                override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                    playbackError = error.message ?: error.errorCodeName
                    ended.countDown()
                }
            })

            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                exoPlayer.setMediaItem(MediaItem.fromUri(Uri.fromFile(output)))
                exoPlayer.prepare()
                exoPlayer.play()
            }
            assertTrue("Exported video did not finish playback", ended.await(30, TimeUnit.SECONDS))
            assertTrue("Exported video playback failed: $playbackError", playbackError == null)
        } finally {
            player?.let { exoPlayer ->
                InstrumentationRegistry.getInstrumentation().runOnMainSync { exoPlayer.release() }
            }
            source.delete()
            exported?.delete()
        }
    }

    @Test
    fun loudnessHandlesMonoStereoFinalPartialAndSilentAudio() {
        val mono = createAudioVideoMp4WithPartialDuration(context.cacheDir, channelCount = 1)
        val stereo = createAudioVideoMp4WithPartialDuration(context.cacheDir, channelCount = 2)
        val silent = createAudioVideoMp4WithPartialDuration(
            context.cacheDir,
            channelCount = 2,
            silent = true
        )
        val noAudio = createSolidColorVideo(context.cacheDir)

        try {
            val monoSamples = getLoudnessSamples(mono)
            val stereoSamples = getLoudnessSamples(stereo)
            val silentSamples = getLoudnessSamples(silent)
            val monoDurationUs = extractAudioDurationUs(mono)
            val stereoDurationUs = extractAudioDurationUs(stereo)

            val monoExpectedCount = ((monoDurationUs + 99_999L) / 100_000L).toInt()
            val stereoExpectedCount = ((stereoDurationUs + 99_999L) / 100_000L).toInt()
            assertTrue("Test audio must have a partial 100 ms interval", monoDurationUs % 100_000L != 0L)
            assertEquals(monoExpectedCount, monoSamples.size)
            assertEquals(stereoExpectedCount, stereoSamples.size)
            assertEquals(monoSamples.size, stereoSamples.size)
            assertTrue("Mono samples must be normalized", monoSamples.all { it in 0.0..1.0 })
            assertTrue("Stereo samples must be normalized", stereoSamples.all { it in 0.0..1.0 })
            assertTrue("Final partial interval must be present", monoSamples.last() > 0.0)
            assertTrue("Silent input must produce silence", silentSamples.all { it == 0.0 })
            assertEquals(ErrorCodes.UNSUPPORTED_FORMAT, getLoudnessErrorCode(noAudio))
        } finally {
            mono.delete()
            stereo.delete()
            silent.delete()
            noAudio.delete()
        }
    }

    private fun export(source: File, captions: List<Map<String, Any>>): File {
        val latch = CountDownLatch(1)
        var exportedPath: String? = null
        var error: String? = null

        ExportService(context).export(
            clipPaths = listOf(source.absolutePath),
            targetHeight = 720,
            captions = captions,
            eventSink = null,
            callback = object : ExportService.Callback {
                override fun onSuccess(outputPath: String) {
                    exportedPath = outputPath
                    latch.countDown()
                }

                override fun onError(errorCode: String, message: String) {
                    error = "$errorCode: $message"
                    latch.countDown()
                }
            }
        )

        assertTrue("Export timed out", latch.await(3, TimeUnit.MINUTES))
        assertTrue("Export failed: $error", error == null)
        return File(requireNotNull(exportedPath))
    }

    private fun assertVideoPlaysToCompletion(file: File) {
        val ended = CountDownLatch(1)
        var playbackError: String? = null
        val player = ExoPlayer.Builder(context)
            .setLooper(Looper.getMainLooper())
            .build()
        try {
            player.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_ENDED) ended.countDown()
                }

                override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                    playbackError = error.message ?: error.errorCodeName
                    ended.countDown()
                }
            })
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                player.setMediaItem(MediaItem.fromUri(Uri.fromFile(file)))
                player.prepare()
                player.play()
            }
            assertTrue("Captioned export did not finish playback", ended.await(30, TimeUnit.SECONDS))
            assertTrue("Captioned export playback failed: $playbackError", playbackError == null)
        } finally {
            InstrumentationRegistry.getInstrumentation().runOnMainSync { player.release() }
        }
    }

    private data class PixelBounds(
        val frameWidth: Int,
        val frameHeight: Int,
        val left: Int,
        val top: Int,
        val right: Int,
        val bottom: Int,
        val changedPixels: Int,
        val darkPixels: Int,
        val whitePixels: Int
    ) {
        val width: Int get() = right - left + 1
        val aspectRatio: Float get() = width.toFloat() / (bottom - top + 1)
        val centerX: Float get() = (left + right) / 2f
    }

    private fun countChangedCaptionPixels(
        baseline: File,
        captioned: File,
        timestampMs: Long
    ): Int {
        val baselineFrame = extractFrame(baseline, timestampMs)
        val captionFrame = extractFrame(captioned, timestampMs)
        try {
            assertEquals(baselineFrame.width, captionFrame.width)
            assertEquals(baselineFrame.height, captionFrame.height)
            val left = baselineFrame.width / 4
            val right = baselineFrame.width * 3 / 4
            val top = baselineFrame.height * 3 / 4
            val bottom = baselineFrame.height * 98 / 100
            var changedPixels = 0
            for (y in top until bottom) {
                for (x in left until right) {
                    val baselinePixel = baselineFrame.getPixel(x, y)
                    val captionPixel = captionFrame.getPixel(x, y)
                    val difference = maxOf(
                        kotlin.math.abs(Color.red(baselinePixel) - Color.red(captionPixel)),
                        kotlin.math.abs(Color.green(baselinePixel) - Color.green(captionPixel)),
                        kotlin.math.abs(Color.blue(baselinePixel) - Color.blue(captionPixel))
                    )
                    if (difference >= 30) changedPixels++
                }
            }
            return changedPixels
        } finally {
            baselineFrame.recycle()
            captionFrame.recycle()
        }
    }

    private fun findCaptionBounds(
        baseline: File,
        captioned: File,
        timestampMs: Long
    ): PixelBounds {
        val baselineFrame = extractFrame(baseline, timestampMs)
        val captionFrame = extractFrame(captioned, timestampMs)
        try {
            assertEquals(baselineFrame.width, captionFrame.width)
            assertEquals(baselineFrame.height, captionFrame.height)
            var left = captionFrame.width
            var top = captionFrame.height
            var right = -1
            var bottom = -1
            var changedPixels = 0
            var darkPixels = 0
            var whitePixels = 0
            for (y in 0 until captionFrame.height) {
                for (x in 0 until captionFrame.width) {
                    val baselinePixel = baselineFrame.getPixel(x, y)
                    val captionPixel = captionFrame.getPixel(x, y)
                    val difference = maxOf(
                        kotlin.math.abs(Color.red(baselinePixel) - Color.red(captionPixel)),
                        kotlin.math.abs(Color.green(baselinePixel) - Color.green(captionPixel)),
                        kotlin.math.abs(Color.blue(baselinePixel) - Color.blue(captionPixel))
                    )
                    if (difference >= 30) {
                        left = minOf(left, x)
                        top = minOf(top, y)
                        right = maxOf(right, x)
                        bottom = maxOf(bottom, y)
                        changedPixels++
                        val brightness = (
                            Color.red(captionPixel) +
                                Color.green(captionPixel) +
                                Color.blue(captionPixel)
                            ) / 3
                        if (brightness < 70) darkPixels++
                        if (brightness > 210) whitePixels++
                    }
                }
            }
            assertTrue("No caption pixels found at $timestampMs ms", changedPixels > 500)
            return PixelBounds(
                captionFrame.width,
                captionFrame.height,
                left,
                top,
                right,
                bottom,
                changedPixels,
                darkPixels,
                whitePixels
            )
        } finally {
            baselineFrame.recycle()
            captionFrame.recycle()
        }
    }

    private fun assertCaptionBoundsInsideFrame(name: String, bounds: PixelBounds) {
        assertTrue("$name caption is clipped on the left", bounds.left > 0)
        assertTrue("$name caption is clipped on the right", bounds.right < bounds.frameWidth - 1)
        assertTrue("$name caption is clipped at the top", bounds.top > 0)
        assertTrue(
            "$name caption does not leave a bottom margin",
            bounds.bottom < bounds.frameHeight * 0.98f
        )
        assertTrue(
            "$name caption should fit within 90% of the frame",
            bounds.width < bounds.frameWidth * 0.9f
        )
    }
    private fun extractFrame(file: File, timestampMs: Long): Bitmap {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            requireNotNull(
                retriever.getFrameAtTime(timestampMs * 1_000L, MediaMetadataRetriever.OPTION_CLOSEST)
            ) { "No frame at $timestampMs ms in ${file.name}" }
        } finally {
            retriever.release()
        }
    }

    private fun extractDurationMs(file: File): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            requireNotNull(
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            ) { "No duration metadata in ${file.name}" }
        } finally {
            retriever.release()
        }

    }

    private fun extractAudioDurationUs(file: File): Long {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(file.absolutePath)
            val audioTrack = (0 until extractor.trackCount).first {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            }
            val format = extractor.getTrackFormat(audioTrack)
            require(format.containsKey(MediaFormat.KEY_DURATION)) {
                "Audio track has no duration metadata"
            }
            format.getLong(MediaFormat.KEY_DURATION)
        } finally {
            extractor.release()
        }
    }

    private fun getLoudnessSamples(file: File): List<Double> {
        val latch = CountDownLatch(1)
        var resultSamples: List<Double>? = null
        var error: String? = null

        LoudnessService(context).getLoudnessSamples(
            file.absolutePath,
            object : LoudnessService.Callback {
                override fun onSuccess(samples: List<Double>) {
                    resultSamples = samples
                    latch.countDown()
                }

                override fun onError(errorCode: String, message: String) {
                    error = "$errorCode: $message"
                    latch.countDown()
                }
            }
        )

        assertTrue("Loudness extraction timed out", latch.await(1, TimeUnit.MINUTES))
        assertTrue("Loudness extraction failed: $error", error == null)
        return requireNotNull(resultSamples)
    }

    private fun getLoudnessErrorCode(file: File): String {
        val latch = CountDownLatch(1)
        var errorCode: String? = null
        LoudnessService(context).getLoudnessSamples(
            file.absolutePath,
            object : LoudnessService.Callback {
                override fun onSuccess(samples: List<Double>) {
                    latch.countDown()
                }

                override fun onError(error: String, message: String) {
                    errorCode = error
                    latch.countDown()
                }
            }
        )
        assertTrue("Loudness extraction timed out", latch.await(1, TimeUnit.MINUTES))
        return requireNotNull(errorCode) { "Expected loudness extraction to fail" }
    }

    private fun createAudioMp4WithPartialDuration(
        directory: File,
        channelCount: Int = 1,
        silent: Boolean = false
    ): File {
        val sampleRate = 48_000
        val durationUs = 1_150_000L
        val totalFrames = (sampleRate * durationUs / 1_000_000L).toInt()
        val samplesPerInput = 1_024
        val output = File(directory, "loudness-test-${UUID.randomUUID()}.mp4")
        val encoder = MediaCodec.createEncoderByType(MIMETYPE_AUDIO_AAC)
        val format = MediaFormat.createAudioFormat(MIMETYPE_AUDIO_AAC, sampleRate, channelCount).apply {
            setInteger(KEY_AAC_PROFILE, CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 96_000 * channelCount)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, samplesPerInput * channelCount * 2)
        }
        val muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var encoderStarted = false
        var muxerStarted = false

        try {
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            encoderStarted = true
            var inputFrame = 0
            var trackIndex = -1
            var inputEnded = false
            var outputEnded = false
            val bufferInfo = BufferInfo()

            while (!outputEnded) {
                if (!inputEnded) {
                    val inputIndex = encoder.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val inputBuffer = requireNotNull(encoder.getInputBuffer(inputIndex))
                        inputBuffer.clear()
                        inputBuffer.order(ByteOrder.nativeOrder())
                        val chunkFrames = minOf(samplesPerInput, totalFrames - inputFrame)
                        if (chunkFrames > 0) {
                            repeat(chunkFrames) { offset ->
                                val timeSeconds = (inputFrame + offset).toDouble() / sampleRate
                                val value = if (silent) 0 else
                                    (Short.MAX_VALUE * 0.35 * kotlin.math.sin(2.0 * Math.PI * 440.0 * timeSeconds)).toInt()
                                repeat(channelCount) {
                                    inputBuffer.putShort(value.toShort())
                                }
                            }
                            val presentationTimeUs = inputFrame * 1_000_000L / sampleRate
                            inputFrame += chunkFrames
                            val flags = if (inputFrame == totalFrames) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0
                            encoder.queueInputBuffer(
                                inputIndex,
                                0,
                                chunkFrames * channelCount * 2,
                                presentationTimeUs,
                                flags
                            )
                            inputEnded = flags != 0
                        }
                    }
                }

                val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, 10_000)
                when {
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        trackIndex = muxer.addTrack(encoder.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                    outputIndex >= 0 -> {
                        val encodedData = requireNotNull(encoder.getOutputBuffer(outputIndex))
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                            bufferInfo.size = 0
                        }
                        if (bufferInfo.size > 0) {
                            check(muxerStarted) { "Encoder produced audio before its output format" }
                            encodedData.position(bufferInfo.offset)
                            encodedData.limit(bufferInfo.offset + bufferInfo.size)
                            muxer.writeSampleData(trackIndex, encodedData, bufferInfo)
                        }
                        outputEnded = bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        encoder.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
        } finally {
            if (encoderStarted) encoder.stop()
            encoder.release()
            if (muxerStarted) muxer.stop()
            muxer.release()
        }
        return output
    }

    private fun createAudioVideoMp4WithPartialDuration(
        directory: File,
        channelCount: Int,
        silent: Boolean = false,
        videoWidth: Int = 320,
        videoHeight: Int = 180,
        videoDurationMs: Long = 1_150L
    ): File {
        val video = createSolidColorVideo(
            directory,
            durationMs = videoDurationMs,
            width = videoWidth,
            height = videoHeight
        )
        val audio = createAudioMp4WithPartialDuration(directory, channelCount, silent)
        val output = File(directory, "loudness-video-${UUID.randomUUID()}.mp4")
        val videoExtractor = MediaExtractor()
        val audioExtractor = MediaExtractor()
        val muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxerStarted = false

        try {
            videoExtractor.setDataSource(video.absolutePath)
            audioExtractor.setDataSource(audio.absolutePath)
            val videoTrack = (0 until videoExtractor.trackCount).first {
                videoExtractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            }
            val audioTrack = (0 until audioExtractor.trackCount).first {
                audioExtractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            }
            videoExtractor.selectTrack(videoTrack)
            audioExtractor.selectTrack(audioTrack)
            val muxedVideoTrack = muxer.addTrack(videoExtractor.getTrackFormat(videoTrack))
            val muxedAudioTrack = muxer.addTrack(audioExtractor.getTrackFormat(audioTrack))
            muxer.start()
            muxerStarted = true

            val videoBuffer = java.nio.ByteBuffer.allocate(1_048_576)
            val audioBuffer = java.nio.ByteBuffer.allocate(1_048_576)
            val bufferInfo = BufferInfo()
            while (videoExtractor.sampleTrackIndex >= 0 || audioExtractor.sampleTrackIndex >= 0) {
                val writeVideo = audioExtractor.sampleTrackIndex < 0 ||
                    (videoExtractor.sampleTrackIndex >= 0 &&
                        videoExtractor.sampleTime <= audioExtractor.sampleTime)
                val extractor = if (writeVideo) videoExtractor else audioExtractor
                val buffer = if (writeVideo) videoBuffer else audioBuffer
                val track = if (writeVideo) muxedVideoTrack else muxedAudioTrack
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                check(size >= 0) { "Unable to read encoded test sample" }
                bufferInfo.set(0, size, extractor.sampleTime, extractor.sampleFlags)
                muxer.writeSampleData(track, buffer, bufferInfo)
                extractor.advance()
            }
        } finally {
            videoExtractor.release()
            audioExtractor.release()
            if (muxerStarted) muxer.stop()
            muxer.release()
            video.delete()
            audio.delete()
        }
        return output
    }

    private fun createSolidColorVideo(
        directory: File,
        durationMs: Long = 6_000L,
        width: Int = 320,
        height: Int = 180,
        rotationDegrees: Int = 0
    ): File {
        val frameRate = 15
        val frameCount = (durationMs * frameRate / 1_000L).toInt()
        val output = File(directory, "caption-test-${UUID.randomUUID()}.mp4")
        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        val supportedFormats = encoder.codecInfo
            .getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
            .colorFormats
        val colorFormat = listOf(
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar
        ).firstOrNull { it in supportedFormats }
            ?: run {
                encoder.release()
                error("No supported planar YUV420 AVC input format")
            }
        val isPlanar = colorFormat == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, colorFormat)
            setInteger(MediaFormat.KEY_BIT_RATE, 400_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        if (rotationDegrees != 0) muxer.setOrientationHint(rotationDegrees)
        var muxerStarted = false
        var encoderStarted = false

        try {
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            encoderStarted = true
            var trackIndex = -1
            var frameIndex = 0
            var inputEnded = false
            var outputEnded = false
            val bufferInfo = MediaCodec.BufferInfo()
            val frame = createYuvFrame(width, height, isPlanar)

            while (!outputEnded) {
                if (!inputEnded) {
                    val inputIndex = encoder.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val inputBuffer = requireNotNull(encoder.getInputBuffer(inputIndex))
                        inputBuffer.clear()
                        if (frameIndex < frameCount) {
                            inputBuffer.put(frame)
                            val presentationTimeUs = frameIndex * 1_000_000L / frameRate
                            encoder.queueInputBuffer(inputIndex, 0, frame.size, presentationTimeUs, 0)
                            frameIndex++
                        } else {
                            encoder.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                frameCount * 1_000_000L / frameRate,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputEnded = true
                        }
                    }
                }

                val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, 10_000)
                when {
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        trackIndex = muxer.addTrack(encoder.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                    outputIndex >= 0 -> {
                        val encodedData = requireNotNull(encoder.getOutputBuffer(outputIndex))
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                            bufferInfo.size = 0
                        }
                        if (bufferInfo.size > 0) {
                            check(muxerStarted) { "Encoder produced a frame before its output format" }
                            encodedData.position(bufferInfo.offset)
                            encodedData.limit(bufferInfo.offset + bufferInfo.size)
                            muxer.writeSampleData(trackIndex, encodedData, bufferInfo)
                        }
                        outputEnded = bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        encoder.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
        } finally {
            if (encoderStarted) {
                encoder.stop()
            }
            encoder.release()
            if (muxerStarted) {
                muxer.stop()
            }
            muxer.release()
        }
        return output
    }

    private fun createYuvFrame(width: Int, height: Int, planar: Boolean): ByteArray {
        val ySize = width * height
        val frame = ByteArray(ySize * 3 / 2)
        frame.fill(96.toByte(), 0, ySize)
        if (planar) {
            frame.fill(128.toByte(), ySize, frame.size)
        } else {
            var index = ySize
            while (index < frame.size) {
                frame[index] = 128.toByte()
                frame[index + 1] = 128.toByte()
                index += 2
            }
        }
        return frame
    }
}
