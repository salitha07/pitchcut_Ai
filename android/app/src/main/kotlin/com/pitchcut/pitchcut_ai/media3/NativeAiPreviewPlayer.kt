package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.Size
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Native Media3 preview rendered into a Flutter texture.
 *
 * This player is separate from the timeline export pipeline.
 */
internal class NativeAiPreviewPlayer private constructor(
    private val textureEntry: TextureRegistry.SurfaceTextureEntry,
    private val surface: Surface,
    private val player: ExoPlayer
) {
    private val released = AtomicBoolean(false)

    val textureId: Long
        get() = textureEntry.id()

    val durationMs: Long
        get() = player.duration.coerceAtLeast(0L)

    val currentPositionMs: Long
        get() = player.currentPosition.coerceAtLeast(0L)

    val isPlaying: Boolean
        get() = player.isPlaying

    fun play() {
        check(!released.get()) { "Preview player is released" }
        player.play()
    }

    fun pause() {
        if (!released.get()) player.pause()
    }

    fun seekTo(positionMs: Long) {
        check(!released.get()) { "Preview player is released" }
        player.seekTo(positionMs.coerceAtLeast(0L))
    }

    fun setPlaybackListener(listener: Player.Listener) {
        check(!released.get()) { "Preview player is released" }
        player.addListener(listener)
    }

    fun removePlaybackListener(listener: Player.Listener) {
        if (!released.get()) player.removeListener(listener)
    }

    fun release() {
        if (!released.compareAndSet(false, true)) return

        try {
            player.release()
        } finally {
            try {
                surface.release()
            } finally {
                textureEntry.release()
            }
        }
    }

    companion object {
        fun create(
            context: Context,
            renderer: FlutterRenderer,
            path: String,
            rawBackground: Map<*, *>
        ): NativeAiPreviewPlayer {
            require(path.isNotBlank()) { "Video path is empty" }
            require(File(path).isFile) { "Video file was not found" }

            val backgroundType = rawBackground["type"] as? String
                ?: error("Background type is missing")

            require(backgroundType in setOf("image", "solid", "gradient", "preset")) {
                "Native preview supports image, solid, gradient and preset backgrounds"
            }

            fun color(key: String): Long? {
                val raw = rawBackground[key] ?: return null
                val number = raw as? Number
                    ?: error("$key must be numeric")
                val value = number.toLong()
                require(value in 0L..0xFFFFFFFFL) {
                    "$key must be an unsigned 32-bit color"
                }
                return value
            }

            val backgroundConfig = TimelineBackground(
                type = backgroundType,
                imagePath = rawBackground["imagePath"] as? String,
                solidColor = color("solidColor"),
                gradientStartColor = color("gradientStartColor"),
                gradientEndColor = color("gradientEndColor"),
                presetId = rawBackground["presetId"] as? String
            )

            val retriever = MediaMetadataRetriever()
            val videoWidth: Int
            val videoHeight: Int

            try {
                retriever.setDataSource(path)

                videoWidth = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
                )?.toIntOrNull() ?: error("Could not read video width")

                videoHeight = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
                )?.toIntOrNull() ?: error("Could not read video height")
            } finally {
                retriever.release()
            }

            require(videoWidth >= 256 && videoHeight >= 256) {
                "Video dimensions must be at least 256x256"
            }

            val background: Bitmap = TimelineBackgroundFactory.create(
                backgroundConfig,
                videoWidth,
                videoHeight
            ) ?: error("Could not create preview background")

            var entry: TextureRegistry.SurfaceTextureEntry? = null
            var outputSurface: Surface? = null
            var exoPlayer: ExoPlayer? = null

            try {
                entry = renderer.createSurfaceTexture()
                entry.surfaceTexture().setDefaultBufferSize(
                    videoWidth,
                    videoHeight
                )

                outputSurface = Surface(entry.surfaceTexture())

                val effect = AiBackgroundGlEffect(
                    backgroundBitmap = background,
                    rotationDegrees = 0f
                )

                exoPlayer = ExoPlayer.Builder(context).build().apply {
                    volume = 0f
                    setVideoEffects(listOf(effect))
                    setVideoSurface(outputSurface)

                    // Direct Surface output needs an explicit resolution
                    // when the Media3 video effects pipeline is enabled.
                    for (rendererIndex in 0 until rendererCount) {
                        if (getRendererType(rendererIndex) == C.TRACK_TYPE_VIDEO) {
                            createMessage(getRenderer(rendererIndex))
                                .setType(Renderer.MSG_SET_VIDEO_OUTPUT_RESOLUTION)
                                .setPayload(Size(videoWidth, videoHeight))
                                .send()
                        }
                    }

                    setMediaItem(
                        MediaItem.fromUri(Uri.fromFile(File(path)))
                    )
                    prepare()
                }

                return NativeAiPreviewPlayer(
                    textureEntry = entry,
                    surface = outputSurface,
                    player = exoPlayer
                )
            } catch (error: Exception) {
                exoPlayer?.release()
                outputSurface?.release()
                entry?.release()

                if (exoPlayer == null && !background.isRecycled) {
                    background.recycle()
                }

                throw error
            }
        }
    }
}
