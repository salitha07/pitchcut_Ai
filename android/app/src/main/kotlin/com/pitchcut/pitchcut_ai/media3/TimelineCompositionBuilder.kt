package com.pitchcut.pitchcut_ai.media3

import android.media.MediaMetadataRetriever
import android.media.MediaCodecList
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Crop
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import java.io.File
import java.util.concurrent.CancellationException
import kotlin.math.roundToInt

internal data class TimelineSourceMetadata(
    val durationMs: Long, val width: Int, val height: Int,
    val rotationDegrees: Int, val hasAudio: Boolean
)

internal data class TimelineComposition(
    val composition: Composition, val width: Int, val height: Int, val hasAudio: Boolean
)

@UnstableApi
internal object TimelineCompositionBuilder {
    private fun supportsAvcCanvas(width: Int, height: Int): Boolean =
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codec ->
            codec.isEncoder && codec.supportedTypes.any { it.equals("video/avc", true) } &&
                codec.getCapabilitiesForType("video/avc").videoCapabilities
                    ?.isSizeSupported(width, height) == true
        }

    fun readMetadata(path: String): TimelineSourceMetadata {
        val file = File(path)
        if (!file.isAbsolute || !file.isFile || !file.canRead()) {
            throw TimelineExportException(ErrorCodes.FILE_NOT_FOUND, "Source is not a readable local file: $path")
        }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            fun number(key: Int): Long = retriever.extractMetadata(key)?.toLongOrNull() ?: 0L
            val duration = number(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val width = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val height = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotation = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            if (duration <= 0 || width !in 1..Int.MAX_VALUE.toLong() ||
                height !in 1..Int.MAX_VALUE.toLong() || rotation !in listOf(0L, 90L, 180L, 270L)) {
                throw TimelineExportException(ErrorCodes.UNSUPPORTED_FORMAT, "Invalid video metadata: $path")
            }
            return TimelineSourceMetadata(duration, width.toInt(), height.toInt(), rotation.toInt(),
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes")
        } catch (error: TimelineExportException) {
            throw error
        } catch (error: Exception) {
            throw TimelineExportException(ErrorCodes.UNSUPPORTED_FORMAT, "Cannot read source metadata: $path (${error.message})")
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    fun build(
        request: TimelineExportRequest,
        isCancelled: () -> Boolean = { false },
        metadataReader: (String) -> TimelineSourceMetadata = ::readMetadata,
        supportsCanvas: (Int, Int) -> Boolean = ::supportsAvcCanvas
    ): TimelineComposition {
        fun checkCancelled() {
            if (isCancelled()) throw CancellationException("Export cancelled")
        }
        val metadata = mutableMapOf<String, TimelineSourceMetadata>()
        val sources = request.items.mapIndexed { index, item ->
            checkCancelled()
            val source = metadata.getOrPut(item.path) { metadataReader(item.path) }
            if (source.durationMs <= 0 || source.width <= 0 || source.height <= 0) {
                throw TimelineExportException(ErrorCodes.UNSUPPORTED_FORMAT, "Invalid source metadata")
            }
            if (item.startMs >= source.durationMs || item.endMs > source.durationMs) {
                throw TimelineExportException(ErrorCodes.INVALID_RANGE, "items[$index] exceeds source duration ${source.durationMs} ms")
            }
            source
        }
        checkCancelled()
        // Intrinsic rotation is handled by Media3 before item effects; only account for it
        // here when choosing the display canvas. Never apply it again as an effect.
        val transformedSizes = request.items.zip(sources).map { (item, source) ->
            val swaps = (source.rotationDegrees + item.rotationDegrees) % 180 != 0
            val rotatedWidth = if (swaps) source.height else source.width
            val rotatedHeight = if (swaps) source.width else source.height
            // Match Crop.configure's float NDC calculation and pixel rounding.
            val ndc = item.crop?.toNdc()
            val width = if (ndc == null) rotatedWidth
                else (rotatedWidth * ((ndc[1] - ndc[0]) / 2f)).roundToInt()
            val height = if (ndc == null) rotatedHeight
                else (rotatedHeight * ((ndc[3] - ndc[2]) / 2f)).roundToInt()
            if (width <= 0 || height <= 0) {
                throw TimelineExportException(ErrorCodes.INVALID_RANGE, "Crop produces an empty pixel frame")
            }
            width to height
        }
        val (firstWidth, firstHeight) = transformedSizes.first()
        val aspect = firstWidth.toDouble() / firstHeight
        val requestedWidth = request.targetHeight * aspect
        if (!requestedWidth.isFinite() || requestedWidth > Int.MAX_VALUE - 2.0) {
            throw TimelineExportException(ErrorCodes.INVALID_RANGE, "Output canvas width is out of range")
        }
        // Use the nearest positive even pixel width for encoder compatibility.
        val aspectWidth = maxOf(2, (requestedWidth / 2).roundToInt() * 2)
        // Some AVC encoders support full HD but not wider 1080-line canvases.
        // Avoid Media3 scaling BOTH dimensions down: retain 1080 lines and fit
        // the un-stretched image inside a supported full-HD canvas instead.
        val width = if (request.targetHeight == 1080 && aspectWidth > 1920 &&
            !supportsCanvas(aspectWidth, 1080) && supportsCanvas(1920, 1080)) 1920
            else aspectWidth
        val edited = request.items.map { item ->
            checkCancelled()
            val clipping = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(item.startMs).setEndPositionMs(item.endMs)
                .setStartsAtKeyFrame(false).build()
            val media = MediaItem.Builder().setUri(Uri.fromFile(File(item.path)))
                .setClippingConfiguration(clipping).build()
            val effects = mutableListOf<Effect>()
            if (item.rotationDegrees != 0) {
                // Media3 1.5.1 uses counterclockwise angles; the Dart preview is clockwise.
                effects.add(ScaleAndRotateTransformation.Builder()
                    .setRotationDegrees(-item.rotationDegrees.toFloat()).build())
            }
            item.crop?.toNdc()?.let { effects.add(Crop(it[0], it[1], it[2], it[3])) }
            effects.add(Presentation.createForWidthAndHeight(width, request.targetHeight,
                Presentation.LAYOUT_SCALE_TO_FIT))
            EditedMediaItem.Builder(media).setEffects(Effects(emptyList(), effects)).build()
        }
        val hasAudio = sources.any { it.hasAudio }
        // The deprecated no-argument builder retains TRACK_TYPE_NONE. Media3
        // 1.9.2 rejects that sentinel when composition-level audio forcing copies
        // the track types. Declare the real tracks, retaining silent audio gaps.
        val trackTypes = if (hasAudio) setOf(C.TRACK_TYPE_VIDEO, C.TRACK_TYPE_AUDIO)
            else setOf(C.TRACK_TYPE_VIDEO)
        // The compile classpath still exposes 1.5.1, while plugins resolve the
        // runtime to 1.9.2. Use the newer public constructor when present without
        // changing dependencies; older runtimes support the legacy audio forcing.
        val sequenceBuilder = try {
            EditedMediaItemSequence.Builder::class.java
                .getConstructor(Set::class.java)
                .newInstance(trackTypes)
        } catch (_: NoSuchMethodException) {
            EditedMediaItemSequence.Builder()
        }
        val sequence = sequenceBuilder.addItems(edited).build()
        val composition = Composition.Builder(listOf(sequence))
            // Create silence for audio-less segments, including the first segment.
            // Do not enable transmuxing when generating silence.
            .experimentalSetForceAudioTrack(hasAudio).build()
        return TimelineComposition(composition, width, request.targetHeight, hasAudio)
    }

    fun validateOutput(path: String, expected: TimelineComposition): String? {
        val actual = readMetadata(path)
        val swaps = actual.rotationDegrees % 180 != 0
        val width = if (swaps) actual.height else actual.width
        val height = if (swaps) actual.width else actual.height
        return when {
            width != expected.width || height != expected.height ->
                "Output display canvas ${width}x$height differs from ${expected.width}x${expected.height}"
            expected.hasAudio && !actual.hasAudio -> "Output is missing the source audio track"
            else -> null
        }
    }
}
