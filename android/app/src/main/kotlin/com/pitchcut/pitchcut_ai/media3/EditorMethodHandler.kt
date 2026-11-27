package com.pitchcut.pitchcut_ai.media3

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class EditorMethodHandler(
    private val context: Context,
    private val flutterRenderer: FlutterRenderer,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL_NAME = "pitchcut/editor"
        const val EVENT_CHANNEL_NAME = "pitchcut/editor/progress"
        const val PREVIEW_EVENT_CHANNEL_NAME = "pitchcut/editor/preview"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL_NAME)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    private val previewEventChannel =
        EventChannel(messenger, PREVIEW_EVENT_CHANNEL_NAME)

    private var previewEventSink: EventChannel.EventSink? = null
    private var nativePreviewPlayer: NativeAiPreviewPlayer? = null

    private val previewProgressRunnable = object : Runnable {
        override fun run() {
            emitPreviewState()
            if (previewEventSink != null && nativePreviewPlayer != null) {
                mainHandler.postDelayed(this, 250L)
            }
        }
    }

    private fun emitPreviewState() {
        val player = nativePreviewPlayer ?: return
        previewEventSink?.success(
            mapOf(
                "type" to "state",
                "positionMs" to player.currentPositionMs,
                "durationMs" to player.durationMs,
                "isPlaying" to player.isPlaying
            )
        )
    }

    private fun startPreviewUpdates() {
        mainHandler.removeCallbacks(previewProgressRunnable)
        if (previewEventSink != null && nativePreviewPlayer != null) {
            emitPreviewState()
            mainHandler.postDelayed(previewProgressRunnable, 250L)
        }
    }

    private val trimService = TrimService(context)
    private val cutService = CutService(context, trimService)
    private val mergeService = MergeService(context)
    private val rotateService = RotateService(context)
    private val cropService = CropService(context)
    private val exportService = ExportService(context)
    private val loudnessService = LoudnessService(context)
    private val backgroundPreviewService = BackgroundPreviewService(mainHandler)

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

        previewEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(
                arguments: Any?,
                events: EventChannel.EventSink?
            ) {
                previewEventSink = events
                previewEventSink?.success(mapOf("type" to "ready"))
                startPreviewUpdates()
            }

            override fun onCancel(arguments: Any?) {
                mainHandler.removeCallbacks(previewProgressRunnable)
                previewEventSink = null
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val guardedResult = OnceMainThreadResult(result)
        try {
            when (call.method) {
                "trim" -> handleTrim(call, guardedResult)
                "cut" -> handleCut(call, guardedResult)
                "merge" -> handleMerge(call, guardedResult)
                "rotate" -> handleRotate(call, guardedResult)
                "crop" -> handleCrop(call, guardedResult)
                "export" -> handleExport(call, guardedResult)
                "exportTimeline" -> handleExportTimeline(call, guardedResult)
                "cancelExport" -> handleCancelExport(guardedResult)
                "getLoudnessSamples" -> handleGetLoudnessSamples(call, guardedResult)
                "generateBackgroundPreview" -> handleGenerateBackgroundPreview(call, guardedResult)
                "createNativePreview" -> handleCreateNativePreview(call, guardedResult)
                "playNativePreview" -> handlePlayNativePreview(guardedResult)
                "pauseNativePreview" -> handlePauseNativePreview(guardedResult)
                "seekNativePreview" -> handleSeekNativePreview(call, guardedResult)
                "disposeNativePreview" -> handleDisposeNativePreview(guardedResult)
                else -> guardedResult.notImplemented()
            }
        } catch (error: Exception) {
            ErrorCodes.sendThrowableMethodError(guardedResult, error)
        }
    }

    private fun handleCreateNativePreview(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        val path = requiredPath(call, "path", result) ?: return

        val background = argument(call, "background") as? Map<*, *> ?: run {
            sendArgumentError(result, "background must be a map")
            return
        }

        nativePreviewPlayer?.release()
        nativePreviewPlayer = null

        val player = NativeAiPreviewPlayer.create(
            context = context,
            renderer = flutterRenderer,
            path = path,
            rawBackground = background
        )

        nativePreviewPlayer = player

        result.success(
            mapOf(
                "textureId" to player.textureId,
                "durationMs" to player.durationMs,
                "positionMs" to player.currentPositionMs,
                "isPlaying" to player.isPlaying
            )
        )

        startPreviewUpdates()
    }

    private fun handlePlayNativePreview(result: MethodChannel.Result) {
        val player = nativePreviewPlayer ?: run {
            sendArgumentError(result, "Native preview is not initialized")
            return
        }

        player.play()
        result.success(null)
        emitPreviewState()
    }

    private fun handlePauseNativePreview(result: MethodChannel.Result) {
        val player = nativePreviewPlayer ?: run {
            sendArgumentError(result, "Native preview is not initialized")
            return
        }

        player.pause()
        result.success(null)
        emitPreviewState()
    }

    private fun handleSeekNativePreview(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        val player = nativePreviewPlayer ?: run {
            sendArgumentError(result, "Native preview is not initialized")
            return
        }

        val positionMs = requiredLong(call, "positionMs", result) ?: return

        player.seekTo(positionMs)
        result.success(null)
        emitPreviewState()
    }

    private fun handleDisposeNativePreview(result: MethodChannel.Result) {
        mainHandler.removeCallbacks(previewProgressRunnable)
        nativePreviewPlayer?.release()
        nativePreviewPlayer = null
        result.success(null)
    }

    private fun handleTrim(call: MethodCall, result: MethodChannel.Result) {
        val path = requiredPath(call, "path", result) ?: return
        val startMs = requiredLong(call, "startMs", result) ?: return
        val endMs = requiredLong(call, "endMs", result) ?: return

        trimService.trim(path, startMs, endMs, object : TrimService.Callback {
            override fun onSuccess(outputPath: String) = result.success(outputPath)
            override fun onError(errorCode: String, message: String) =
                ErrorCodes.sendMethodError(result, errorCode, message, ErrorCodes.mediaEdit)
        })
    }

    private fun handleCut(call: MethodCall, result: MethodChannel.Result) {
        val path = requiredPath(call, "path", result) ?: return
        val atMs = requiredLong(call, "atMs", result) ?: return

        cutService.cut(path, atMs, object : CutService.Callback {
            override fun onSuccess(outputPaths: List<String>) = result.success(outputPaths)
            override fun onError(errorCode: String, message: String) =
                ErrorCodes.sendMethodError(result, errorCode, message, ErrorCodes.mediaEdit)
        })
    }

    private fun handleMerge(call: MethodCall, result: MethodChannel.Result) {
        val paths = requiredPaths(call, "paths", result) ?: return
        if (paths.isEmpty()) {
            sendArgumentError(result, "paths cannot be empty")
            return
        }

        mergeService.merge(paths, object : MergeService.Callback {
            override fun onSuccess(outputPath: String) = result.success(outputPath)
            override fun onError(errorCode: String, message: String) =
                ErrorCodes.sendMethodError(result, errorCode, message, ErrorCodes.mediaEdit)
        })
    }

    private fun handleRotate(call: MethodCall, result: MethodChannel.Result) {
        val path = requiredPath(call, "path", result) ?: return
        val degrees = requiredInt(call, "degrees", result) ?: return

        rotateService.rotate(path, degrees, object : RotateService.Callback {
            override fun onSuccess(outputPath: String) = result.success(outputPath)
            override fun onError(errorCode: String, message: String) =
                ErrorCodes.sendMethodError(result, errorCode, message, ErrorCodes.rotate)
        })
    }

    private fun handleCrop(call: MethodCall, result: MethodChannel.Result) {
        val path = requiredPath(call, "path", result) ?: return
        val left = requiredInt(call, "left", result) ?: return
        val top = requiredInt(call, "top", result) ?: return
        val width = requiredInt(call, "width", result) ?: return
        val height = requiredInt(call, "height", result) ?: return

        cropService.crop(path, left, top, width, height, object : CropService.Callback {
            override fun onSuccess(outputPath: String) = result.success(outputPath)
            override fun onError(errorCode: String, message: String) =
                ErrorCodes.sendMethodError(result, errorCode, message, ErrorCodes.crop)
        })
    }

    private fun handleExport(call: MethodCall, result: MethodChannel.Result) {
        val clipPaths = requiredPaths(call, "clipPaths", result) ?: return
        val rawTargetHeight = argument(call, "targetHeight")
        val targetHeight = if (rawTargetHeight == null) {
            1080
        } else {
            (rawTargetHeight as? Number)?.let(::toExactInt) ?: run {
                sendArgumentError(result, "targetHeight must be numeric")
                return
            }
        }
        val captions = parseCaptions(argument(call, "captions"), result) ?: return

        exportService.export(
            clipPaths,
            targetHeight,
            captions,
            eventSink,
            object : ExportService.Callback {
                override fun onSuccess(outputPath: String) = result.success(outputPath)
                override fun onError(errorCode: String, message: String) =
                    ErrorCodes.sendMethodError(result, errorCode, message, ErrorCodes.all)
            }
        )
    }

    private fun handleExportTimeline(call: MethodCall, result: MethodChannel.Result) {
        val request = try {
            TimelineExportRequest.parse(call.arguments)
        } catch (error: TimelineExportException) {
            ErrorCodes.sendMethodError(result, error.code, error.message ?: error.code)
            return
        }
        exportService.exportTimeline(request, eventSink, object : ExportService.Callback {
            override fun onSuccess(outputPath: String) = result.success(outputPath)
            override fun onError(errorCode: String, message: String) =
                ErrorCodes.sendMethodError(result, errorCode, message, ErrorCodes.all)
        })
    }

    private fun handleCancelExport(result: MethodChannel.Result) {
        exportService.cancelExport(eventSink) {
            result.success(null)
        }
    }

    private fun handleGenerateBackgroundPreview(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        val path = requiredPath(call, "path", result) ?: return
        val timeMs = requiredLong(call, "timeMs", result) ?: return
        val background = argument(call, "background") as? Map<*, *> ?: run {
            sendArgumentError(result, "background must be a map")
            return
        }

        backgroundPreviewService.generate(path, timeMs, background) { bytes, error ->
            if (bytes != null) {
                result.success(bytes)
            } else {
                result.error(
                    "background_preview_failed",
                    error ?: "Background preview failed",
                    null
                )
            }
        }
    }
    private fun handleGetLoudnessSamples(call: MethodCall, result: MethodChannel.Result) {
        val path = requiredPath(call, "path", result) ?: return
        loudnessService.getLoudnessSamples(path, object : LoudnessService.Callback {
            override fun onSuccess(samples: List<Double>) = result.success(samples)
            override fun onError(errorCode: String, message: String) =
                ErrorCodes.sendMethodError(result, errorCode, message, ErrorCodes.loudness)
        })
    }

    private fun argument(call: MethodCall, name: String): Any? =
        (call.arguments as? Map<*, *>)?.get(name)

    private fun requiredPath(
        call: MethodCall,
        name: String,
        result: MethodChannel.Result
    ): String? {
        val raw = argument(call, name)
        if (raw == null) {
            ErrorCodes.sendMethodError(
                result,
                ErrorCodes.FILE_NOT_FOUND,
                "Argument '$name' is required"
            )
            return null
        }
        if (raw !is String) {
            sendArgumentError(result, "Argument '$name' must be a string")
            return null
        }
        if (raw.isBlank()) {
            ErrorCodes.sendMethodError(
                result,
                ErrorCodes.FILE_NOT_FOUND,
                "Argument '$name' must not be blank"
            )
            return null
        }
        return raw
    }

    private fun requiredLong(
        call: MethodCall,
        name: String,
        result: MethodChannel.Result
    ): Long? {
        val raw = argument(call, name)
        if (raw !is Number) {
            sendArgumentError(result, "Argument '$name' must be numeric")
            return null
        }
        val value = raw.toDouble()
        if (!value.isFinite() || value % 1.0 != 0.0 ||
            value < Long.MIN_VALUE.toDouble() || value > Long.MAX_VALUE.toDouble()) {
            sendArgumentError(result, "Argument '$name' must be a finite integer")
            return null
        }
        return value.toLong()
    }

    private fun requiredInt(
        call: MethodCall,
        name: String,
        result: MethodChannel.Result
    ): Int? {
        val value = requiredLong(call, name, result) ?: return null
        if (value < Int.MIN_VALUE || value > Int.MAX_VALUE) {
            sendArgumentError(result, "Argument '$name' is outside the integer range")
            return null
        }
        return value.toInt()
    }

    private fun toExactInt(number: Number): Int? {
        val value = number.toDouble()
        if (!value.isFinite() || value % 1.0 != 0.0 ||
            value < Int.MIN_VALUE.toDouble() || value > Int.MAX_VALUE.toDouble()) return null
        return value.toInt()
    }

    private fun requiredPaths(
        call: MethodCall,
        name: String,
        result: MethodChannel.Result
    ): List<String>? {
        val raw = argument(call, name)
        if (raw == null) {
            ErrorCodes.sendMethodError(
                result,
                ErrorCodes.FILE_NOT_FOUND,
                "Argument '$name' is required"
            )
            return null
        }
        if (raw !is List<*>) {
            sendArgumentError(result, "Argument '$name' must be a list of strings")
            return null
        }
        val paths = mutableListOf<String>()
        for ((index, item) in raw.withIndex()) {
            if (item !is String) {
                sendArgumentError(result, "Argument '$name[$index]' must be a string")
                return null
            }
            if (item.isBlank()) {
                ErrorCodes.sendMethodError(
                    result,
                    ErrorCodes.FILE_NOT_FOUND,
                    "Argument '$name[$index]' must not be blank"
                )
                return null
            }
            paths.add(item)
        }
        return paths
    }

    private fun parseCaptions(
        raw: Any?,
        result: MethodChannel.Result
    ): List<Map<String, Any>>? {
        if (raw == null) return emptyList()
        if (raw !is List<*>) {
            sendArgumentError(result, "Argument 'captions' must be a list")
            return null
        }
        val captions = mutableListOf<Map<String, Any>>()
        for ((index, item) in raw.withIndex()) {
            if (item !is Map<*, *>) {
                sendArgumentError(result, "Caption[$index] must be a map")
                return null
            }
            val caption = mutableMapOf<String, Any>()
            for ((key, value) in item) {
                if (key is String && value != null) caption[key] = value
            }
            captions.add(caption)
        }
        return captions
    }

    private fun sendArgumentError(result: MethodChannel.Result, message: String) {
        ErrorCodes.sendMethodError(result, ErrorCodes.INVALID_RANGE, message)
    }

    private inner class OnceMainThreadResult(
        private val delegate: MethodChannel.Result
    ) : MethodChannel.Result {
        private val completed = AtomicBoolean(false)

        override fun success(result: Any?) = dispatch { delegate.success(result) }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) =
            dispatch {
                delegate.error(
                    ErrorCodes.allowedCode(errorCode),
                    errorMessage ?: errorCode,
                    errorDetails
                )
            }

        override fun notImplemented() = dispatch { delegate.notImplemented() }

        private fun dispatch(action: () -> Unit) {
            if (!completed.compareAndSet(false, true)) return
            if (Looper.myLooper() == Looper.getMainLooper()) action() else mainHandler.post(action)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
        exportService.onProgressStreamListen(events)
    }

    override fun onCancel(arguments: Any?) {
        exportService.onProgressStreamCancelled(eventSink)
        this.eventSink = null
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        previewEventChannel.setStreamHandler(null)

        eventSink = null
        previewEventSink = null

        mainHandler.removeCallbacks(previewProgressRunnable)

        nativePreviewPlayer?.release()
        nativePreviewPlayer = null

        backgroundPreviewService.close()
    }
}


