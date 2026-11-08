package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodec.BufferInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import java.io.File
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil
import kotlin.math.sqrt

internal class LoudnessWindowAccumulator(
    sampleRate: Int,
    private val channelCount: Int
) {
    private val framesPerWindow: Int
    private val samples = mutableListOf<Double>()
    private var frameCount = 0L
    private var pendingChannelCount = 0
    private var pendingFrameSquares = 0.0
    private var windowFrameCount = 0
    private var windowSquares = 0.0
    private var finished = false

    init {
        require(sampleRate > 0) { "Decoder output sample rate must be positive" }
        require(channelCount > 0) { "Decoder output channel count must be positive" }
        require(sampleRate % 10 == 0) {
            "Decoder output sample rate cannot form exact 100 ms windows"
        }
        framesPerWindow = sampleRate / 10
    }

    fun addPcm16(buffer: java.nio.ByteBuffer, maxFrames: Long = Long.MAX_VALUE) {
        check(!finished) { "Loudness accumulator is already finished" }
        val pcm = buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        while (pcm.remaining() >= Short.SIZE_BYTES && frameCount < maxFrames) {
            val value = pcm.short.toDouble()
            pendingFrameSquares += value * value
            pendingChannelCount++
            if (pendingChannelCount == channelCount) {
                frameCount++
                windowSquares += pendingFrameSquares
                windowFrameCount++
                pendingFrameSquares = 0.0
                pendingChannelCount = 0
                if (windowFrameCount == framesPerWindow) emitWindow()
            }
        }
    }

    fun finish(expectedWindowCount: Int? = null): List<Double> {
        if (!finished) {
            if (pendingChannelCount != 0) {
                pendingFrameSquares = 0.0
                pendingChannelCount = 0
            }
            if (windowFrameCount > 0) emitWindow()
            if (expectedWindowCount != null) {
                while (samples.size < expectedWindowCount) samples.add(0.0)
                while (samples.size > expectedWindowCount) samples.removeAt(samples.lastIndex)
            }
            finished = true
        }
        return samples.toList()
    }

    private fun emitWindow() {
        val sampleCount = windowFrameCount.toDouble() * channelCount
        val rms = if (sampleCount == 0.0) 0.0 else sqrt(windowSquares / sampleCount)
        samples.add((rms / 32768.0).coerceIn(0.0, 1.0))
        windowSquares = 0.0
        windowFrameCount = 0
    }
}

/**
 * Decodes the first audio track and returns one normalized RMS value per 100 ms.
 * Normalization is fixed to signed 16-bit PCM full scale (32768), independent
 * of channel count or content; silence therefore remains exactly zero.
 */
class LoudnessService(private val context: Context) {

    interface Callback {
        fun onSuccess(samples: List<Double>)
        fun onError(errorCode: String, message: String)
    }

    private class LoudnessFailure(val code: String, message: String) : Exception(message)

    fun getLoudnessSamples(path: String, callback: Callback) {
        val mainHandler = Handler(Looper.getMainLooper())
        val threadId = UUID.randomUUID().toString().take(8)
        val handlerThread = HandlerThread("LoudnessThread_$threadId")
        val callbackDelivered = AtomicBoolean(false)

        fun deliverSuccess(samples: List<Double>) {
            if (callbackDelivered.compareAndSet(false, true)) {
                mainHandler.post { callback.onSuccess(samples) }
            }
            if (handlerThread.isAlive) handlerThread.quitSafely()
        }

        fun deliverError(code: String, message: String) {
            if (callbackDelivered.compareAndSet(false, true)) {
                mainHandler.post {
                    callback.onError(ErrorCodes.allowedCode(code, ErrorCodes.loudness), message)
                }
            }
            if (handlerThread.isAlive) handlerThread.quitSafely()
        }

        try {
            handlerThread.start()
        } catch (error: Exception) {
            deliverError(ErrorCodes.mapThrowable(error), error.message ?: "Failed to start loudness decoder")
            return
        }

        val backgroundHandler = Handler(handlerThread.looper)
        if (!backgroundHandler.post {
                var samples: List<Double>? = null
                var failure: Pair<String, String>? = null
                var extractor: MediaExtractor? = null
                var codec: MediaCodec? = null
                var codecStarted = false

                try {
                    val inputFile = File(path)
                    if (!inputFile.isFile) {
                        throw LoudnessFailure(ErrorCodes.FILE_NOT_FOUND, "Source file not found at: $path")
                    }

                    extractor = MediaExtractor()
                    extractor.setDataSource(path)
                    val audioTrackIndex = (0 until extractor.trackCount).firstOrNull { index ->
                        extractor.getTrackFormat(index)
                            .getString(MediaFormat.KEY_MIME)
                            ?.startsWith("audio/") == true
                    } ?: throw LoudnessFailure(
                        ErrorCodes.UNSUPPORTED_FORMAT,
                        "No audio track found in: $path"
                    )

                    extractor.selectTrack(audioTrackIndex)
                    val trackFormat = extractor.getTrackFormat(audioTrackIndex)
                    val mime = trackFormat.getString(MediaFormat.KEY_MIME)
                        ?: throw LoudnessFailure(
                            ErrorCodes.UNSUPPORTED_FORMAT,
                            "Audio track has no decoder MIME type"
                        )
                    val audioDurationUs = if (trackFormat.containsKey(MediaFormat.KEY_DURATION)) {
                        trackFormat.getLong(MediaFormat.KEY_DURATION).takeIf { it > 0L }
                    } else {
                        null
                    }

                    codec = MediaCodec.createDecoderByType(mime)
                    codec.configure(trackFormat, null, null, 0)
                    codec.start()
                    codecStarted = true

                    var accumulator: LoudnessWindowAccumulator? = null
                    var maxFrames = Long.MAX_VALUE
                    var expectedWindows: Int? = null
                    var inputEnded = false
                    var outputEnded = false
                    var lastProgressAt = SystemClock.elapsedRealtime()
                    var iterations = 0
                    val bufferInfo = BufferInfo()
                    var currentSampleRate = 0
                    var currentChannelCount = 0
                    var currentPcmEncoding = 0

                    fun initializeOutputFormat(outputFormat: MediaFormat) {
                        val outputSampleRate = if (outputFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                            outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        } else {
                            throw LoudnessFailure(
                                ErrorCodes.UNSUPPORTED_FORMAT,
                                "Decoder output format did not specify a sample rate"
                            )
                        }
                        val outputChannels = if (outputFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                            outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        } else {
                            throw LoudnessFailure(
                                ErrorCodes.UNSUPPORTED_FORMAT,
                                "Decoder output format did not specify a channel count"
                            )
                        }
                        val pcmEncoding = if (outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        } else {
                            throw LoudnessFailure(
                                ErrorCodes.UNSUPPORTED_FORMAT,
                                "Decoder output format did not specify its PCM encoding"
                            )
                        }
                        if (pcmEncoding != AudioFormat.ENCODING_PCM_16BIT) {
                            throw LoudnessFailure(
                                ErrorCodes.UNSUPPORTED_FORMAT,
                                "Unsupported decoder PCM encoding: $pcmEncoding; expected 16-bit PCM"
                            )
                        }

                        if (accumulator == null) {
                            accumulator = LoudnessWindowAccumulator(outputSampleRate, outputChannels)
                            currentSampleRate = outputSampleRate
                            currentChannelCount = outputChannels
                            currentPcmEncoding = pcmEncoding
                        } else if (outputSampleRate != currentSampleRate ||
                            outputChannels != currentChannelCount ||
                            pcmEncoding != currentPcmEncoding) {
                            throw LoudnessFailure(
                                ErrorCodes.UNSUPPORTED_FORMAT,
                                "Decoder output format changed during audio decoding"
                            )
                        }
                        if (audioDurationUs != null) {
                            maxFrames = ceil(audioDurationUs.toDouble() * outputSampleRate / 1_000_000.0)
                                .toLong()
                            expectedWindows = ceil(audioDurationUs.toDouble() / 100_000.0).toInt()
                        }
                    }

                    while (!outputEnded) {
                        iterations++
                        if (iterations > 60_000 ||
                            SystemClock.elapsedRealtime() - lastProgressAt > 30_000L) {
                            throw LoudnessFailure(
                                ErrorCodes.UNSUPPORTED_FORMAT,
                                "Timed out while waiting for decoded audio"
                            )
                        }

                        if (!inputEnded) {
                            val inputIndex = codec.dequeueInputBuffer(10_000)
                            if (inputIndex >= 0) {
                                val inputBuffer = codec.getInputBuffer(inputIndex)
                                    ?: throw IllegalStateException("Decoder returned a null input buffer")
                                inputBuffer.clear()
                                val readSize = extractor.readSampleData(inputBuffer, 0)
                                if (readSize < 0) {
                                    codec.queueInputBuffer(
                                        inputIndex,
                                        0,
                                        0,
                                        0L,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                    )
                                    inputEnded = true
                                } else {
                                    codec.queueInputBuffer(
                                        inputIndex,
                                        0,
                                        readSize,
                                        extractor.sampleTime,
                                        extractor.sampleFlags
                                    )
                                    extractor.advance()
                                }
                                lastProgressAt = SystemClock.elapsedRealtime()
                            }
                        }

                        val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
                        when {
                            outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                                initializeOutputFormat(codec.outputFormat)
                                lastProgressAt = SystemClock.elapsedRealtime()
                            }
                            outputIndex >= 0 -> {
                                try {
                                    if (accumulator == null) initializeOutputFormat(codec.outputFormat)
                                    if (bufferInfo.size > 0) {
                                        val outputBuffer = codec.getOutputBuffer(outputIndex)
                                            ?: throw IllegalStateException("Decoder returned a null output buffer")
                                        val pcm = outputBuffer.duplicate()
                                        pcm.position(bufferInfo.offset)
                                        pcm.limit(bufferInfo.offset + bufferInfo.size)
                                        requireNotNull(accumulator).addPcm16(pcm, maxFrames)
                                    }
                                    outputEnded =
                                        bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                                    lastProgressAt = SystemClock.elapsedRealtime()
                                } finally {
                                    codec.releaseOutputBuffer(outputIndex, false)
                                }
                            }
                        }
                    }

                    val outputAccumulator = accumulator ?: throw LoudnessFailure(
                        ErrorCodes.UNSUPPORTED_FORMAT,
                        "Decoder produced no PCM output format"
                    )
                    samples = outputAccumulator.finish(expectedWindows)
                } catch (error: Exception) {
                    failure = if (error is LoudnessFailure) {
                        error.code to (error.message ?: "Unsupported audio format")
                    } else {
                        ErrorCodes.mapThrowable(error) to (error.message ?: "Failed to extract loudness")
                    }
                } finally {
                    if (codecStarted) {
                        try {
                            codec?.stop()
                        } catch (_: Exception) {
                        }
                    }
                    try {
                        codec?.release()
                    } catch (_: Exception) {
                    }
                    try {
                        extractor?.release()
                    } catch (_: Exception) {
                    }
                }

                if (failure != null) {
                    deliverError(failure.first, failure.second)
                } else {
                    deliverSuccess(requireNotNull(samples))
                }
            }) {
            deliverError(ErrorCodes.EXPORT_FAILED, "Failed to schedule loudness extraction")
        }
    }
}
