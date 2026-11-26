package com.pitchcut.pitchcut_ai.media3

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.effect.Crop
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.util.concurrent.CancellationException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TimelineCompositionBuilderTest {
    private val landscape = TimelineSourceMetadata(5000, 1920, 1080, 0, true)
    private fun request(items: List<Map<String, Any?>>) = TimelineExportRequest.parse(
        mapOf("items" to items, "targetHeight" to 720))
    private fun item(path: String = "/one.mp4", rotation: Int = 0, crop: Map<String, Double>? = null) =
        mapOf("path" to path, "startMs" to 100L, "endMs" to 1100L,
            "rotationDegrees" to rotation, "crop" to crop)

    @Test fun createsIndependentClippedItemsInOrderAndReadsEachSourceOnce() {
        val reads = mutableListOf<String>()
        val built = TimelineCompositionBuilder.build(request(listOf(item(), item("/two.mp4"), item())),
            metadataReader = { reads.add(it); landscape })
        val items = built.composition.sequences.single().editedMediaItems
        assertEquals(listOf("/one.mp4", "/two.mp4", "/one.mp4").map { Uri.fromFile(File(it)) },
            items.map { it.mediaItem.localConfiguration!!.uri })
        assertNotSame(items[0], items[2])
        items.forEach {
            assertEquals(100L, it.mediaItem.clippingConfiguration.startPositionMs)
            assertEquals(1100L, it.mediaItem.clippingConfiguration.endPositionMs)
            assertFalse(it.removeAudio)
        }
        assertEquals(listOf("/one.mp4", "/two.mp4"), reads)
    }

    @Test fun rotatesClockwiseThenCropsThenFitsEveryItemToOneCanvas() {
        val crop = mapOf("left" to 0.0, "top" to 0.0, "right" to 1.0, "bottom" to 0.5)
        val built = TimelineCompositionBuilder.build(request(listOf(item(rotation = 90, crop = crop), item())),
            metadataReader = { landscape })
        assertEquals(810, built.width)
        assertEquals(720, built.height)
        val items = built.composition.sequences.single().editedMediaItems
        val effects = items.first().effects.videoEffects
        assertEquals(listOf(ScaleAndRotateTransformation::class.java, Crop::class.java, Presentation::class.java),
            effects.map { it.javaClass })
        val rotation = effects[0] as ScaleAndRotateTransformation
        assertEquals(270f, rotation.rotationDegrees, 0f)
        var size = rotation.configure(1920, 1080)
        assertEquals(1080, size.width)
        assertEquals(1920, size.height)
        size = (effects[1] as Crop).configure(size.width, size.height)
        assertEquals(1080, size.width)
        assertEquals(960, size.height)
        items.forEach { edited ->
            val presentation = edited.effects.videoEffects.last() as Presentation
            val canvas = presentation.configure(1920, 1080)
            assertEquals(810, canvas.width)
            assertEquals(720, canvas.height)
            // A landscape frame must retain equal physical X/Y scale inside this canvas.
            val matrix = FloatArray(9)
            presentation.getMatrix(0).getValues(matrix)
            assertEquals(matrix[0] * 810 / 1920, matrix[4] * 720 / 1080, 0.0001f)
        }
    }

    @Test fun intrinsicRotationOnlyAffectsCanvasAndIsNotAppliedTwice() {
        val built = TimelineCompositionBuilder.build(request(listOf(item())),
            metadataReader = { landscape.copy(rotationDegrees = 90) })
        assertEquals(406, built.width)
        assertEquals(1, built.composition.sequences.single().editedMediaItems.single().effects.videoEffects.size)
    }

    @Test fun allRotationSignsMatchClockwisePreview() {
        for (degrees in listOf(90, 180, 270)) {
            val built = TimelineCompositionBuilder.build(request(listOf(item(rotation = degrees))),
                metadataReader = { landscape })
            val effect = built.composition.sequences.single().editedMediaItems.single()
                .effects.videoEffects.first() as ScaleAndRotateTransformation
            assertEquals((360 - degrees).toFloat(), effect.rotationDegrees, 0f)
        }
    }

    @Test fun silentFirstSegmentForcesAudioWithoutTransmuxing() {
        val built = TimelineCompositionBuilder.build(request(listOf(item("/silent.mp4"), item())),
            metadataReader = { landscape.copy(hasAudio = it != "/silent.mp4") })
        assertTrue(built.hasAudio)
        assertTrue(built.composition.forceAudioTrack)
        assertFalse(built.composition.transmuxAudio)
        val silent = TimelineCompositionBuilder.build(request(listOf(item())),
            metadataReader = { landscape.copy(hasAudio = false) })
        assertFalse(silent.composition.forceAudioTrack)
    }

    @Test fun unsupportedWide1080CanvasFitsInsideSupportedFullHdWithoutReducingHeight() {
        val request = TimelineExportRequest.parse(mapOf("items" to listOf(item()), "targetHeight" to 1080))
        val source = landscape.copy(width = 1944, height = 1080)
        val built = TimelineCompositionBuilder.build(request,
            metadataReader = { source }, supportsCanvas = { w, h -> w == 1920 && h == 1080 })
        assertEquals(1920, built.width)
        assertEquals(1080, built.height)
        val presentation = built.composition.sequences.single().editedMediaItems.single()
            .effects.videoEffects.single() as Presentation
        val size = presentation.configure(1944, 1080)
        assertEquals(1920, size.width)
        assertEquals(1080, size.height)
        val matrix = FloatArray(9)
        presentation.getMatrix(0).getValues(matrix)
        assertEquals(matrix[0] * 1920 / 1944, matrix[4], 0.0001f)
        val supported = TimelineCompositionBuilder.build(request,
            metadataReader = { source }, supportsCanvas = { _, _ -> true })
        assertEquals(1944, supported.width)
        val unsupported = TimelineCompositionBuilder.build(request,
            metadataReader = { source }, supportsCanvas = { _, _ -> false })
        assertEquals(1944, unsupported.width)
    }

    @Test fun lowerResolutionsNeverQueryOrChangeCanvasForCodecFallback() {
        for (height in listOf(480, 720)) {
            val request = TimelineExportRequest.parse(mapOf("items" to listOf(item()), "targetHeight" to height))
            val built = TimelineCompositionBuilder.build(request,
                metadataReader = { landscape.copy(width = 1944, height = 1080) },
                supportsCanvas = { _, _ -> error("Lower resolution must not query codec fallback") })
            assertEquals(if (height == 480) 864 else 1296, built.width)
            assertEquals(height, built.height)
        }
    }

    @Test fun constructedSequencesContainOnlyRealAudioVideoTrackTypes() {
        // This regression concerns the newer runtime constructor. Keep the test
        // source compilable against the app's unchanged 1.5.1 compile classpath.
        assumeTrue(androidx.media3.transformer.EditedMediaItemSequence.Builder::class.java
            .constructors.any { it.parameterTypes.contentEquals(arrayOf(Set::class.java)) })
        for (audio in listOf(listOf(false, false), listOf(false, true),
            listOf(true, false), listOf(true, true))) {
            val built = TimelineCompositionBuilder.build(
                request(listOf(item("/first.mp4"), item("/second.mp4"))),
                metadataReader = { landscape.copy(hasAudio = audio[if (it == "/first.mp4") 0 else 1]) }
            )
            val expected = if (audio.any { it }) setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO)
                else setOf(C.TRACK_TYPE_VIDEO)
            val sequence = built.composition.sequences.single()
            val actual = sequence.javaClass.getField("trackTypes").get(sequence) as Set<*>
            assertEquals(expected, actual)
            assertFalse(actual.contains(C.TRACK_TYPE_NONE))
            assertEquals(audio.any { it }, built.composition.forceAudioTrack)
            assertFalse(built.composition.transmuxAudio)
        }
    }

    @Test fun rejectsEndBeyondActualDurationAndUnknownMetadata() {
        val error = assertThrows(TimelineExportException::class.java) {
            TimelineCompositionBuilder.build(request(listOf(item())), metadataReader = { landscape.copy(durationMs = 1099) })
        }
        assertEquals(ErrorCodes.INVALID_RANGE, error.code)
        TimelineCompositionBuilder.build(request(listOf(item())),
            metadataReader = { landscape.copy(durationMs = 1100) })
        assertThrows(TimelineExportException::class.java) {
            TimelineCompositionBuilder.build(request(listOf(item())), metadataReader = { landscape.copy(durationMs = 0) })
        }
    }

    @Test fun missingDirectoryAndRelativeSourcesAreRejected() {
        for (path in listOf("relative.mp4", "/missing-source.mp4", System.getProperty("java.io.tmpdir"))) {
            val error = assertThrows(TimelineExportException::class.java) {
                TimelineCompositionBuilder.readMetadata(path)
            }
            assertEquals(ErrorCodes.FILE_NOT_FOUND, error.code)
        }
    }

    @Test fun cancelledValidationNeverReadsAnotherSource() {
        var cancelled = false
        val reads = mutableListOf<String>()
        assertThrows(CancellationException::class.java) {
            TimelineCompositionBuilder.build(request(listOf(item(), item("/two.mp4"))),
                isCancelled = { cancelled }, metadataReader = {
                    reads.add(it); cancelled = true; landscape
                })
        }
        assertEquals(listOf("/one.mp4"), reads)
    }

    @Test fun rejectsCropThatRoundsToAnEmptyPixelFrame() {
        val crop = mapOf("left" to 0.0, "top" to 0.0, "right" to 0.05, "bottom" to 1.0)
        val error = assertThrows(TimelineExportException::class.java) {
            TimelineCompositionBuilder.build(request(listOf(item(crop = crop))),
                metadataReader = { landscape.copy(width = 2, height = 2) })
        }
        assertEquals(ErrorCodes.INVALID_RANGE, error.code)
    }
}
