package com.example.plan_zajec_uek

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import android.os.Build

class MainActivity : FlutterActivity() {
    // Samsung's screenshot compositor also needs the Flutter pixels in the
    // regular view hierarchy, not in a separate SurfaceView layer.
    override fun getRenderMode(): RenderMode =
        if (Build.MANUFACTURER.equals("samsung", ignoreCase = true)) RenderMode.texture
        else RenderMode.surface

    private var updateBridge: AppUpdateBridge? = null
    private var captureBridge: ScrollCaptureBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updateBridge = AppUpdateBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        if (Build.VERSION.SDK_INT >= 31) {
            captureBridge = ScrollCaptureBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        updateBridge?.close()
        updateBridge = null
        if (Build.VERSION.SDK_INT >= 31) captureBridge?.close()
        captureBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
