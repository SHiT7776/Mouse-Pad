package com.shi7.mouse_pad

import android.annotation.SuppressLint
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bluetooth: BluetoothHidController? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A touchpad shouldn't dim or lock while you're using it.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Draw behind the camera hole in landscape too (the UI keeps clear of it),
        // instead of leaving a black strip down one side.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "mouse_pad/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
        bluetooth = BluetoothHidController(this, messenger)
    }

    override fun onResume() {
        super.onResume()
        tuneForLowLatency()
        bluetooth?.onResume()
    }

    /**
     * Android normally hands touches to an app once per screen refresh; a
     * touchpad wants each one the moment it happens. Also run at the screen's
     * fastest refresh rate while the app is open.
     */
    @SuppressLint("ClickableViewAccessibility") // only observes touches, never consumes them
    private fun tuneForLowLatency() {
        findFlutterView(window.decorView)?.setOnTouchListener { view, event ->
            if (event.actionMasked == MotionEvent.ACTION_DOWN) view.requestUnbufferedDispatch(event)
            false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        @Suppress("DEPRECATION")
        val screen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay
        val current = screen?.mode ?: return
        val fastest = screen.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        if (window.attributes.preferredDisplayModeId != fastest.modeId) {
            window.attributes = window.attributes.apply { preferredDisplayModeId = fastest.modeId }
        }
    }

    private fun findFlutterView(view: View): View? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) findFlutterView(view.getChildAt(i))?.let { return it }
        }
        return null
    }

    override fun onPause() {
        bluetooth?.onPause()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bluetooth?.dispose()
        bluetooth = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bluetooth?.onPermissionsResult(requestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        bluetooth?.onActivityResult(requestCode, resultCode)
    }
}
