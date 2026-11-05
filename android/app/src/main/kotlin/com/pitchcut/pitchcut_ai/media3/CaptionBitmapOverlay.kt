package com.pitchcut.pitchcut_ai.media3

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import androidx.media3.common.util.Size
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlaySettings
import kotlin.math.ceil

internal class CaptionBitmapOverlay(
    private val captions: List<ExportService.Caption>,
    private val clipOffsetMs: Long,
    private val fontHeightRatio: Float = 0.045f,
    private val maxFrameWidthRatio: Float = 0.9f,
    private val bottomMarginRatio: Float = 0.05f,
    private val maxLines: Int = 3,
    private val maxCaptionCodePoints: Int = 8_192
) : BitmapOverlay() {
    private val bitmapLock = Any()
    private val captionBitmaps = mutableMapOf<String, Bitmap>()
    private var transparentBitmap: Bitmap? = null
    @Volatile private var frameWidth = 0
    @Volatile private var frameHeight = 0

    override fun configure(videoSize: Size) {
        synchronized(bitmapLock) {
            if (frameWidth != videoSize.width || frameHeight != videoSize.height) {
                recycleBitmapsLocked()
                frameWidth = videoSize.width
                frameHeight = videoSize.height
            }
        }
    }

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val text = activeTextAt(presentationTimeUs) ?: return getTransparentBitmap()
        return synchronized(bitmapLock) {
            captionBitmaps.getOrPut(text) { renderCaptionBitmap(text) }
        }
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
        val isCaptionActive = activeTextAt(presentationTimeUs) != null
        val height = frameHeight.coerceAtLeast(1)
        val bottomMargin = height * bottomMarginRatio
        val backgroundAnchorY = (-1f + 2f * bottomMargin / height).coerceIn(-1f, 1f)
        return OverlaySettings.Builder()
            .setAlphaScale(if (isCaptionActive) 1f else 0f)
            .setBackgroundFrameAnchor(0f, backgroundAnchorY)
            .setOverlayFrameAnchor(0f, -1f)
            .build()
    }

    fun releaseBitmaps() {
        synchronized(bitmapLock) {
            recycleBitmapsLocked()
        }
    }

    private fun activeTextAt(presentationTimeUs: Long): String? {
        val globalMs = presentationTimeUs / 1_000L + clipOffsetMs
        val active = captions.filter { globalMs >= it.startMs && globalMs < it.endMs }
        return active.takeIf { it.isNotEmpty() }?.joinToString("\n") { it.text }
    }

    private fun getTransparentBitmap(): Bitmap = synchronized(bitmapLock) {
        transparentBitmap ?: Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
            .also {
                it.eraseColor(Color.TRANSPARENT)
                transparentBitmap = it
            }
    }

    private fun renderCaptionBitmap(text: String): Bitmap {
        val outputWidth = frameWidth.coerceAtLeast(1)
        val outputHeight = frameHeight.coerceAtLeast(1)
        val fontSize = (outputHeight * fontHeightRatio).coerceAtLeast(12f)
        val horizontalPadding = fontSize * 0.45f
        val verticalPadding = fontSize * 0.22f
        val maxBoxWidth = (outputWidth * maxFrameWidthRatio).toInt().coerceAtLeast(1)
        val maxTextWidth = (maxBoxWidth - 2f * horizontalPadding).toInt().coerceAtLeast(1)
        val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = fontSize
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.LEFT
            setShadowLayer(fontSize * 0.08f, 0f, fontSize * 0.04f, Color.BLACK)
        }
        val boundedText = if (text.codePointCount(0, text.length) <= maxCaptionCodePoints) {
            text
        } else {
            val end = text.offsetByCodePoints(0, maxCaptionCodePoints - 1)
            text.substring(0, end) + "…"
        }
        val layout = createCaptionLayout(boundedText, textPaint, maxTextWidth)
        val contentWidth = (0 until layout.lineCount)
            .maxOfOrNull(layout::getLineWidth)
            ?.coerceAtLeast(fontSize) ?: fontSize
        val bitmapWidth = ceil(contentWidth + horizontalPadding * 2f)
            .toInt().coerceIn(1, maxBoxWidth)
        val bitmapHeight = ceil(layout.height + verticalPadding * 2f).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(128, 0, 0, 0)
            style = Paint.Style.FILL
        }
        canvas.drawRoundRect(
            RectF(0f, 0f, bitmapWidth.toFloat(), bitmapHeight.toFloat()),
            fontSize * 0.2f,
            fontSize * 0.2f,
            backgroundPaint
        )
        canvas.save()
        canvas.translate((bitmapWidth - layout.width) / 2f, verticalPadding)
        layout.draw(canvas)
        canvas.restore()
        return bitmap
    }

    private fun createCaptionLayout(text: String, paint: TextPaint, width: Int): StaticLayout {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
                .setAlignment(Layout.Alignment.ALIGN_CENTER)
                .setIncludePad(false)
                .setMaxLines(maxLines)
                .setEllipsize(TextUtils.TruncateAt.END)
                .build()
        }

        fun legacyLayout(value: String) = StaticLayout(
            value,
            paint,
            width,
            Layout.Alignment.ALIGN_CENTER,
            1f,
            0f,
            false
        )

        var candidate = text
        var layout = legacyLayout(candidate)
        if (layout.lineCount <= maxLines) return layout
        candidate = candidate.substring(0, layout.getLineEnd(maxLines - 1)).trimEnd()
        while (candidate.isNotEmpty()) {
            val truncated = legacyLayout("$candidate…")
            if (truncated.lineCount <= maxLines) return truncated
            val previousCodePoint = Character.offsetByCodePoints(candidate, candidate.length, -1)
            candidate = candidate.substring(0, previousCodePoint).trimEnd()
        }
        return legacyLayout("…")
    }

    private fun recycleBitmapsLocked() {
        captionBitmaps.values.forEach { bitmap ->
            if (!bitmap.isRecycled) bitmap.recycle()
        }
        captionBitmaps.clear()
        transparentBitmap?.let { if (!it.isRecycled) it.recycle() }
        transparentBitmap = null
    }
}
