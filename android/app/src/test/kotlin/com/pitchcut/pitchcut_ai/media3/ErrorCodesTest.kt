package com.pitchcut.pitchcut_ai.media3

import androidx.media3.transformer.ExportException
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.util.concurrent.CancellationException
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith
import org.junit.Test
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ErrorCodesTest {
    private fun exportException(errorCode: Int) = ExportException.createForAssetLoader(
        IllegalStateException("underlying cause"),
        errorCode
    )

    @Test
    fun mapsFileNotFoundCause() {
        assertEquals(
            ErrorCodes.FILE_NOT_FOUND,
            ErrorCodes.mapThrowable(IllegalStateException("read failed", FileNotFoundException()))
        )
    }

    @Test
    fun mapsExportExceptionFileNotFound() {
        assertEquals(
            ErrorCodes.FILE_NOT_FOUND,
            ErrorCodes.mapThrowable(exportException(ExportException.ERROR_CODE_IO_FILE_NOT_FOUND))
        )
    }

    @Test
    fun mapsUnsupportedFormatExportExceptions() {
        val unsupportedFormatCodes = listOf(
            ExportException.ERROR_CODE_DECODER_INIT_FAILED,
            ExportException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            ExportException.ERROR_CODE_ENCODER_INIT_FAILED,
            ExportException.ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED
        )

        unsupportedFormatCodes.forEach { errorCode ->
            assertEquals(
                "error code $errorCode",
                ErrorCodes.UNSUPPORTED_FORMAT,
                ErrorCodes.mapThrowable(exportException(errorCode))
            )
        }
    }

    @Test
    fun mapsOtherAndUnknownExportExceptionCodesToExportFailed() {
        listOf(
            ExportException.ERROR_CODE_DECODING_FAILED,
            ExportException.ERROR_CODE_MUXING_FAILED,
            Int.MAX_VALUE
        ).forEach { errorCode ->
            assertEquals(
                "error code $errorCode",
                ErrorCodes.EXPORT_FAILED,
                ErrorCodes.mapThrowable(exportException(errorCode))
            )
        }
    }

    @Test
    fun mapsCancellation() {
        assertEquals(
            ErrorCodes.CANCELLED,
            ErrorCodes.mapThrowable(CancellationException("cancelled"))
        )
    }

    @Test
    fun mapsUnknownThrowableToExportFailure() {
        assertEquals(
            ErrorCodes.EXPORT_FAILED,
            ErrorCodes.mapThrowable(IllegalStateException("unexpected"))
        )
    }

    @Test
    fun rotateAndCropDisallowUnsupportedFormatButKeepCauseMessage() {
        assertEquals(
            ErrorCodes.EXPORT_FAILED,
            ErrorCodes.allowedCode(ErrorCodes.UNSUPPORTED_FORMAT, ErrorCodes.rotate)
        )
        assertEquals(
            ErrorCodes.EXPORT_FAILED,
            ErrorCodes.allowedCode(ErrorCodes.UNSUPPORTED_FORMAT, ErrorCodes.crop)
        )
        assertEquals(
            ErrorCodes.FILE_NOT_FOUND,
            ErrorCodes.allowedCode(ErrorCodes.FILE_NOT_FOUND, ErrorCodes.rotate)
        )
        assertEquals(
            ErrorCodes.INVALID_RANGE,
            ErrorCodes.allowedCode(ErrorCodes.INVALID_RANGE, ErrorCodes.crop)
        )

        var returnedCode: String? = null
        var returnedMessage: String? = null
        val result = object : MethodChannel.Result {
            override fun success(result: Any?) = Unit

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                returnedCode = errorCode
                returnedMessage = errorMessage
            }

            override fun notImplemented() = Unit
        }
        val causeMessage = "Unsupported input format: decoder initialization failed"
        ErrorCodes.sendMethodError(
            result,
            ErrorCodes.UNSUPPORTED_FORMAT,
            causeMessage,
            ErrorCodes.crop
        )
        assertEquals(ErrorCodes.EXPORT_FAILED, returnedCode)
        assertEquals(causeMessage, returnedMessage)
    }

    @Test
    fun unknownCodeIsNeverReturned() {
        assertEquals(ErrorCodes.EXPORT_FAILED, ErrorCodes.allowedCode("UNKNOWN"))
    }
}
