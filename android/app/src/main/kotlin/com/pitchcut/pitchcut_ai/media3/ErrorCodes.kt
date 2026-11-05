package com.pitchcut.pitchcut_ai.media3

import androidx.media3.transformer.ExportException
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.util.concurrent.CancellationException

object ErrorCodes {
    const val FILE_NOT_FOUND = "FILE_NOT_FOUND"
    const val INVALID_RANGE = "INVALID_RANGE"
    const val UNSUPPORTED_FORMAT = "UNSUPPORTED_FORMAT"
    const val EXPORT_FAILED = "EXPORT_FAILED"
    const val CANCELLED = "CANCELLED"

    val all = setOf(FILE_NOT_FOUND, INVALID_RANGE, UNSUPPORTED_FORMAT, EXPORT_FAILED, CANCELLED)
    val mediaEdit = setOf(FILE_NOT_FOUND, INVALID_RANGE, UNSUPPORTED_FORMAT, EXPORT_FAILED)
    val rotate = setOf(FILE_NOT_FOUND, INVALID_RANGE, EXPORT_FAILED)
    val crop = setOf(FILE_NOT_FOUND, INVALID_RANGE, EXPORT_FAILED)
    val loudness = setOf(FILE_NOT_FOUND, UNSUPPORTED_FORMAT, EXPORT_FAILED)

    fun mapThrowable(error: Throwable): String {
        var current: Throwable? = error
        val visited = mutableSetOf<Throwable>()
        while (current != null && visited.add(current)) {
            if (current is FileNotFoundException ||
                current.javaClass.simpleName == "NoSuchFileException") return FILE_NOT_FOUND
            if (current is CancellationException) return CANCELLED
            if (current is ExportException) {
                val mappedCode = mapExportException(current)
                if (mappedCode != EXPORT_FAILED) return mappedCode
            }
            current = current.cause
        }
        return EXPORT_FAILED
    }

    fun mapExportException(error: ExportException): String = when (error.errorCode) {
        ExportException.ERROR_CODE_IO_FILE_NOT_FOUND -> FILE_NOT_FOUND
        ExportException.ERROR_CODE_DECODER_INIT_FAILED,
        ExportException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
        ExportException.ERROR_CODE_ENCODER_INIT_FAILED,
        ExportException.ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED -> UNSUPPORTED_FORMAT
        else -> EXPORT_FAILED
    }

    fun allowedCode(code: String, allowedCodes: Set<String> = all): String {
        val contractCode = if (code in all) code else EXPORT_FAILED
        return if (contractCode in allowedCodes) contractCode else EXPORT_FAILED
    }

    fun sendMethodError(
        result: MethodChannel.Result,
        code: String,
        message: String,
        allowedCodes: Set<String> = all
    ) {
        result.error(allowedCode(code, allowedCodes), message, null)
    }

    fun sendThrowableMethodError(
        result: MethodChannel.Result,
        error: Throwable,
        allowedCodes: Set<String> = all
    ) {
        sendMethodError(
            result,
            mapThrowable(error),
            error.message ?: error.javaClass.simpleName,
            allowedCodes
        )
    }

    fun sendEventError(
        sink: EventChannel.EventSink?,
        code: String,
        message: String,
        allowedCodes: Set<String> = all
    ) {
        sink?.error(allowedCode(code, allowedCodes), message, null)
    }

    fun sendThrowableEventError(
        sink: EventChannel.EventSink?,
        error: Throwable,
        allowedCodes: Set<String> = all
    ) {
        sendEventError(
            sink,
            mapThrowable(error),
            error.message ?: error.javaClass.simpleName,
            allowedCodes
        )
    }
}
