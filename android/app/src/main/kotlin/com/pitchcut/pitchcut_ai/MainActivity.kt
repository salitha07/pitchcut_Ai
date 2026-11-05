package com.pitchcut.pitchcut_ai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.pitchcut.pitchcut_ai.media3.EditorMethodHandler

class MainActivity : FlutterActivity() {
    private var editorMethodHandler: EditorMethodHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        editorMethodHandler = EditorMethodHandler(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        editorMethodHandler?.dispose()
        editorMethodHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
