package com.example.plan_zajec_uek

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.view.ScrollCaptureCallback
import android.view.ScrollCaptureSession
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterView
import java.util.function.Consumer
import android.util.Log
import kotlin.math.roundToInt

@RequiresApi(31)
class ScrollCaptureBridge(private val activity: Activity, messenger: BinaryMessenger) : ScrollCaptureCallback {
    private val channel = MethodChannel(messenger, "uek_plan/scroll_capture")
    private val handler = Handler(Looper.getMainLooper())
    private var generation = 0
    private val decor = activity.window.decorView
    private var registered = false
    private var captureView: FlutterView? = null
    private var closed = false
    private var started = false
    private val layoutListener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> register() }
    private val attachmentListener = object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) { decor.post { register() } }
        override fun onViewDetachedFromWindow(view: View) {
            registered = false
            generation++
            started = false
        }
    }

    init {
        // configureFlutterEngine runs before the window has a ViewRootImpl.
        decor.addOnAttachStateChangeListener(attachmentListener)
        decor.addOnLayoutChangeListener(layoutListener)
        decor.post { register() }
    }

    private fun register() {
        if (closed || !decor.isAttachedToWindow) return
        val flutter = findFlutterView(decor)
        if (flutter != null) {
            if (captureView === flutter) return
            captureView?.setScrollCaptureCallback(null)
            if (registered) {
                activity.window.unregisterScrollCaptureCallback(this)
                registered = false
            }
            // OEM capture tools must discover the actual rendering view.
            flutter.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_INCLUDE
            flutter.setScrollCaptureCallback(this)
            captureView = flutter
        } else if (!registered) {
            activity.window.registerScrollCaptureCallback(this)
            registered = true
        }
    }

    private fun request(method: String, arguments: Any? = null, done: (Any?) -> Unit) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { request(method, arguments, done) }
            return
        }
        var completed = false
        lateinit var timeout: Runnable
        fun finish(value: Any?) {
            if (completed) return
            completed = true
            handler.removeCallbacks(timeout)
            done(value)
        }
        timeout = Runnable {
            Log.w("UEKScrollCapture", "Timeout: $method")
            finish(null)
        }
        handler.postDelayed(timeout, if (method == "search") 800L else 2900L)
        try { channel.invokeMethod(method, arguments, object : MethodChannel.Result {
            override fun success(result: Any?) = finish(result)
            override fun error(code: String, message: String?, details: Any?) {
                Log.w("UEKScrollCapture", "Flutter capture failed: $method ($code)")
                finish(null)
            }
            override fun notImplemented() = finish(null)
        }) } catch (error: RuntimeException) {
            Log.w("UEKScrollCapture", "Capture channel unavailable: $method", error)
            finish(null)
        }
    }

    override fun onScrollCaptureSearch(signal: CancellationSignal, onReady: Consumer<Rect>) {
        if (closed) { onReady.accept(Rect()); return }
        request("search") { value ->
            val data = value as? Map<*, *>
            val bounds = rect(data) ?: Rect()
            Log.d("UEKScrollCapture", "Search bounds=$bounds")
            if (captureView == null && !bounds.isEmpty) {
                val flutterView = findFlutterView(activity.window.decorView)
                if (flutterView != null) {
                    val origin = IntArray(2)
                    val rootOrigin = IntArray(2)
                    flutterView.getLocationInWindow(origin)
                    activity.window.decorView.getLocationInWindow(rootOrigin)
                    bounds.offset(origin[0] - rootOrigin[0], origin[1] - rootOrigin[1])
                }
            }
            if (!signal.isCanceled) onReady.accept(bounds)
        }
    }

    override fun onScrollCaptureStart(session: ScrollCaptureSession, signal: CancellationSignal, onReady: Runnable) {
        val current = ++generation
        request("start") { result ->
            if (!signal.isCanceled && current == generation) {
                started = result == true
                Log.d("UEKScrollCapture", "Start ready=$started bounds=${session.scrollBounds}")
                onReady.run()
            }
        }
    }

    override fun onScrollCaptureImageRequest(session: ScrollCaptureSession, signal: CancellationSignal,
        captureArea: Rect, onComplete: Consumer<Rect>) {
        if (!started || closed || signal.isCanceled) {
            if (!signal.isCanceled) onComplete.accept(Rect())
            return
        }
        val current = generation
        val requested = Rect(captureArea)
        request("capture", mapOf("left" to requested.left, "top" to requested.top,
            "right" to requested.right, "bottom" to requested.bottom)) { value ->
            if (signal.isCanceled || current != generation) return@request
            val data = value as? Map<*, *>
            val bytes = data?.get("rgba") as? ByteArray
            val area = rect(data) ?: Rect()
            val width = (data?.get("width") as? Number)?.toInt() ?: 0
            val height = (data?.get("height") as? Number)?.toInt() ?: 0
            if (bytes == null || area.isEmpty || !requested.contains(area) ||
                width != area.width() || height != area.height() ||
                width <= 0 || height <= 0 || width.toLong() * height > 8_000_000L ||
                width.toLong() * height * 4 != bytes.size.toLong()) {
                Log.w("UEKScrollCapture", "Invalid tile requested=$requested actual=$area size=${width}x$height bytes=${bytes?.size}")
                onComplete.accept(Rect())
                return@request
            }
            var bitmap: Bitmap? = null
            try {
                // Explicit ARGB conversion avoids device-specific native byte order.
                val pixels = IntArray(width * height)
                for (index in pixels.indices) {
                    val offset = index * 4
                    pixels[index] = Color.argb(bytes[offset + 3].toInt() and 255,
                        bytes[offset].toInt() and 255, bytes[offset + 1].toInt() and 255,
                        bytes[offset + 2].toInt() and 255)
                }
                bitmap = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
                val destination = Rect(0, 0, width, height)
                // Synchronous software upload, as used by Chromium's scroll capture.
                val canvas = session.surface.lockCanvas(destination)
                try {
                    // lockCanvas may expand the dirty rectangle to the whole
                    // buffer. Do not stretch a partial tile to that rectangle.
                    canvas.drawColor(Color.WHITE)
                    canvas.drawBitmap(bitmap, 0f, 0f, null)
                } finally { session.surface.unlockCanvasAndPost(canvas) }
                onComplete.accept(area)
                Log.d("UEKScrollCapture", "Captured area=$area size=${width}x$height")
            } catch (error: Exception) {
                Log.w("UEKScrollCapture", "Nie udalo sie przekazac fragmentu zrzutu", error)
                onComplete.accept(Rect())
            } catch (error: OutOfMemoryError) {
                Log.w("UEKScrollCapture", "Not enough memory for capture tile")
                onComplete.accept(Rect())
            } finally { bitmap?.recycle() }
        }
    }

    override fun onScrollCaptureEnd(onReady: Runnable) {
        generation++
        started = false
        request("end") { onReady.run() }
    }

    private fun rect(data: Map<*, *>?): Rect? {
        if (data == null) return null
        val values = listOf("left", "top", "right", "bottom").map {
            (data[it] as? Number)?.toDouble() ?: return null
        }
        if (values.any { !it.isFinite() || it < Int.MIN_VALUE || it > Int.MAX_VALUE }) return null
        return Rect(values[0].roundToInt(), values[1].roundToInt(),
            values[2].roundToInt(), values[3].roundToInt())
    }

    private fun findFlutterView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findFlutterView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    fun close() {
        closed = true
        generation++
        started = false
        decor.removeOnAttachStateChangeListener(attachmentListener)
        decor.removeOnLayoutChangeListener(layoutListener)
        captureView?.setScrollCaptureCallback(null)
        captureView = null
        if (registered && decor.isAttachedToWindow) {
            activity.window.unregisterScrollCaptureCallback(this)
        }
        registered = false
        request("end") {}
    }
}
