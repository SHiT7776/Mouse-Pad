package com.shi7.mouse_pad

import android.Manifest
import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppQosSettings
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

private const val REPORT_KEYBOARD = 1
private const val REPORT_MOUSE = 2

/**
 * Pointer reports go out at most this often. Measured with a phone and a laptop,
 * the link delivered ~80 reports/s with frequent slower stretches;
 * sending any faster builds a queue inside Android's Bluetooth stack and the
 * pointer trails further and further behind the finger. Staying below what
 * the link carries keeps that queue empty.
 */
private const val MOUSE_INTERVAL_MS = 15L

/**
 * With nothing to send for this long, send an empty report anyway. An idle
 * link drops into a slow power-saving rhythm, and waking it from that adds a
 * noticeable delay to the next movement.
 */
private const val KEEP_AWAKE_MS = 500L

/**
 * Makes the phone a Bluetooth touchpad + keyboard with Android's HID Device
 * profile (Android 9+). The touchpad gestures are worked out in Dart; Windows
 * just receives pointer movement, clicks and keys like from any Bluetooth
 * mouse, so the PC needs no extra software in this mode.
 *
 * Driven from Dart over the "mouse_pad/bluetooth" channels (bluetooth_link.dart).
 */
@SuppressLint("MissingPermission") // hasPermissions() is checked before any Bluetooth call
class BluetoothHidController(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methods = MethodChannel(messenger, "mouse_pad/bluetooth")
    private val events = EventChannel(messenger, "mouse_pad/bluetooth/events")
    private val main = Handler(Looper.getMainLooper())
    private val prefs = activity.getSharedPreferences("bluetooth", Context.MODE_PRIVATE)
    private val adapter: BluetoothAdapter? =
        (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    private val reports = ReportSender(::sendNow)

    private var sink: EventChannel.EventSink? = null
    private var wanted = false // Bluetooth mode is selected in the app
    private var resumed = true // the app is on screen
    @Volatile private var hid: BluetoothHidDevice? = null
    private var callback: BluetoothHidDevice.Callback? = null
    private var registered = false
    @Volatile private var host: BluetoothDevice? = null // the connected PC
    private var target: BluetoothDevice? = null // the PC we're connecting to
    private var phase = "idle"
    private var message: String? = null
    private var discoverableUntil: Long? = null
    private var listening = false
    private var reconnectAttempts = 0
    private var restartAttempts = 0
    private val reconnect = Runnable { reconnectNow() }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> { wanted = true; start() }
            "stop" -> { wanted = false; stop() }
            "pairedDevices" -> return result.success(pairedDevices())
            "connect" -> {
                // Picked by hand: that replaces any automatic retrying.
                main.removeCallbacks(reconnect)
                reconnectAttempts = 0
                if (phase == "reconnecting") phase = "ready"
                connect(call.argument<String>("address"))
            }
            "enableBluetooth" -> requestEnable()
            "makeDiscoverable" -> requestDiscoverable()
            "openAppSettings" -> openAppSettings()
            "mouse" -> queueMouse(call.arguments as IntArray)
            "keys" -> queueKeys(call.arguments as IntArray)
            "zoom" -> queueZoom(call.arguments as Int)
            else -> return result.notImplemented()
        }
        result.success(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        emit()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun onResume() {
        resumed = true
        reports.keepAwake = host != null
        if (!wanted) return
        if (hid == null || !registered) {
            start()
        } else if (host == null) {
            // Back in the app: get the PC back straight away.
            reconnectAttempts = 0
            scheduleReconnect(300)
        }
    }

    fun onPause() {
        resumed = false
        reports.keepAwake = false // let the link rest while you're in another app
    }

    fun dispose() {
        sink = null
        wanted = false
        stop()
        if (listening) {
            try {
                activity.unregisterReceiver(bluetoothChanges)
            } catch (e: IllegalArgumentException) {
                // already gone
            }
            listening = false
        }
        reports.shutdown()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    private fun start() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return update("unsupported", "Bluetooth touchpad mode needs Android 9 or newer.")
        }
        val adapter = adapter ?: return update("unsupported", "This phone has no Bluetooth.")
        if (!hasPermissions()) {
            update("starting")
            activity.requestPermissions(requiredPermissions(), REQUEST_PERMISSIONS)
            return // continues in onPermissionsResult()
        }
        listenForBluetoothChanges()
        if (!adapter.isEnabled) return update("bluetoothOff")
        when {
            hid == null -> {
                update("starting")
                if (!adapter.getProfileProxy(activity, profileListener, BluetoothProfile.HID_DEVICE)) {
                    update("unsupported", "This phone can't work as a Bluetooth touchpad.")
                }
            }
            !registered -> registerApp()
            else -> update(if (host != null) "connected" else "ready")
        }
    }

    private fun stop() {
        main.removeCallbacks(reconnect)
        reports.clear()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            hid?.let { hid ->
                host?.let { hid.disconnect(it) }
                if (registered) hid.unregisterApp()
            }
        }
        releaseProxy()
        registered = false
        host = null
        target = null
        update("idle")
    }

    // Created on first use, so phones older than Android 9 never load HID classes.
    private val profileListener by lazy {
        object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                if (profile != BluetoothProfile.HID_DEVICE) return
                hid = proxy as BluetoothHidDevice
                if (wanted) registerApp() else releaseProxy()
            }

            override fun onServiceDisconnected(profile: Int) {
                if (profile != BluetoothProfile.HID_DEVICE) return
                hid = null
                registered = false
                host = null
                reports.clear()
                // Android's Bluetooth service restarted; set up again by ourselves.
                if (wanted) {
                    update("starting")
                    main.postDelayed({ if (wanted && hid == null) start() }, 1500)
                }
            }
        }
    }

    @TargetApi(Build.VERSION_CODES.P)
    private fun registerApp() {
        val hid = hid ?: return
        update("starting")
        val sdp = BluetoothHidDeviceAppSdpSettings(
            "Mouse Pad",
            "Phone touchpad and keyboard",
            "Mouse Pad",
            BluetoothHidDevice.SUBCLASS1_COMBO,
            HidDescriptor.REPORT_MAP,
        )
        // Ask for a low-latency link, like a real mouse (values from Google's
        // WearMouse sample: 11.25 ms latency).
        val qos = BluetoothHidDeviceAppQosSettings(
            BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT,
            800,
            9,
            0,
            11250,
            BluetoothHidDeviceAppQosSettings.MAX,
        )
        val callback = callback ?: HidCallback().also { callback = it }
        if (!hid.registerApp(sdp, null, qos, activity.mainExecutor, callback)) {
            update("error", "Couldn't start the Bluetooth touchpad. Another app may be using it.")
        }
    }

    @TargetApi(Build.VERSION_CODES.P)
    private inner class HidCallback : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            this@BluetoothHidController.registered = registered
            if (!registered) {
                host = null
                reports.clear()
                if (!wanted) return
                // Android dropped us (Bluetooth restarted, another app...); try again.
                if (restartAttempts++ < 3) {
                    update("starting")
                    main.postDelayed({ if (wanted && !this@BluetoothHidController.registered) registerApp() }, 2000)
                } else {
                    update("error", "Android turned the Bluetooth touchpad off. Try again.")
                }
                return
            }
            restartAttempts = 0
            reconnectAttempts = 0
            // Reconnect to the PC used last time, so opening the app is enough;
            // keep trying if it isn't reachable yet (e.g. still waking up).
            val again = pluggedDevice ?: lastHost() ?: return update("ready")
            target = again
            update("reconnecting")
            connect(again.address)
        }

        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            when (state) {
                BluetoothProfile.STATE_CONNECTED -> {
                    main.removeCallbacks(reconnect)
                    reconnectAttempts = 0
                    reports.clear()
                    host = device
                    reports.keepAwake = resumed
                    target = null
                    prefs.edit().putString(KEY_LAST_HOST, device.address).apply()
                    update("connected")
                }
                BluetoothProfile.STATE_CONNECTING -> {
                    target = device
                    if (phase != "reconnecting") update("connecting")
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    val wasHost = host?.address == device.address
                    if (wasHost) host = null
                    if (target?.address == device.address) target = null
                    reports.clear()
                    if (!registered || host != null) return
                    if (wasHost || phase == "reconnecting") {
                        // Dropped (PC asleep, out of range...): keep trying by ourselves.
                        target = device
                        update("reconnecting")
                        scheduleReconnect(backoffMs())
                    } else {
                        update("ready", "Couldn't reach ${deviceName(device)}. Is its Bluetooth on?")
                    }
                }
            }
        }

        override fun onGetReport(device: BluetoothDevice, type: Byte, id: Byte, bufferSize: Int) {
            val hid = hid ?: return
            val size = when (id.toInt()) {
                REPORT_KEYBOARD -> 8
                REPORT_MOUSE -> 7
                else -> 0
            }
            if (type == BluetoothHidDevice.REPORT_TYPE_INPUT && size > 0) {
                hid.replyReport(device, type, id, ByteArray(size))
            } else {
                hid.reportError(device, BluetoothHidDevice.ERROR_RSP_INVALID_RPT_ID)
            }
        }

        override fun onSetReport(device: BluetoothDevice, type: Byte, id: Byte, data: ByteArray) {
            // Only the keyboard lights (Caps Lock...) get set; nothing to do.
            hid?.reportError(device, BluetoothHidDevice.ERROR_RSP_SUCCESS)
        }

        override fun onVirtualCableUnplug(device: BluetoothDevice) {
            // The PC removed us on purpose: don't keep calling it.
            main.removeCallbacks(reconnect)
            if (host?.address == device.address) host = null
            if (registered) update("ready")
        }
    }

    private fun connect(address: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        val hid = hid ?: return
        if (address == null || !registered) return
        val device = try {
            adapter?.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            null
        } ?: return
        when (hid.getConnectionState(device)) {
            BluetoothProfile.STATE_CONNECTED, BluetoothProfile.STATE_CONNECTING -> return
        }
        host?.let { if (it.address != address) hid.disconnect(it) }
        target = device
        if (!hid.connect(device)) {
            if (phase == "reconnecting") return scheduleReconnect(backoffMs())
            target = null
            update("ready", "Couldn't reach ${deviceName(device)}. Is its Bluetooth on?")
        } else if (phase != "reconnecting") {
            update("connecting")
        }
    }

    private fun scheduleReconnect(delayMs: Long) {
        main.removeCallbacks(reconnect)
        if (!wanted || !registered || host != null) return
        if (lastHost() == null) return update("ready")
        main.postDelayed(reconnect, delayMs)
    }

    private fun reconnectNow() {
        // Only while the app is on screen; it tries again when you come back.
        if (!wanted || !registered || host != null || !resumed) return
        val device = lastHost() ?: return
        reconnectAttempts++
        if (phase != "reconnecting") {
            target = device
            update("reconnecting")
        }
        connect(device.address)
    }

    /** 1, 2, 4, 8 s, then every 15 s. */
    private fun backoffMs() = (1000L shl reconnectAttempts.coerceAtMost(4)).coerceAtMost(15000L)

    private fun lastHost(): BluetoothDevice? {
        val address = prefs.getString(KEY_LAST_HOST, null) ?: return null
        return (adapter?.bondedDevices ?: emptySet()).firstOrNull { it.address == address }
    }

    private fun pairedDevices(): List<Map<String, Any?>> {
        val adapter = adapter ?: return emptyList()
        if (!hasPermissions() || !adapter.isEnabled) return emptyList()
        return (adapter.bondedDevices ?: emptySet())
            .map {
                mapOf(
                    "name" to (it.name ?: it.address),
                    "address" to it.address,
                    "isComputer" to
                        (it.bluetoothClass?.majorDeviceClass == BluetoothClass.Device.Major.COMPUTER),
                )
            }
            .sortedByDescending { it["isComputer"] as Boolean }
    }

    /** [buttons, dx, dy, wheel, pan] -> merged into the next mouse report. */
    private fun queueMouse(r: IntArray) {
        if (r.size >= 5 && host != null) reports.mouse(r[0], r[1], r[2], r[3], r[4])
    }

    /** [modifiers, key, modifiers, key, ...] -> press and release each key. */
    private fun queueKeys(codes: IntArray) {
        if (host == null) return
        for (i in 0 until codes.size / 2) {
            reports.key(byteArrayOf(codes[2 * i].toByte(), 0, codes[2 * i + 1].toByte(), 0, 0, 0, 0, 0))
            reports.key(ByteArray(8))
        }
    }

    /** Ctrl + wheel, which is what Windows itself does for a touchpad pinch. */
    private fun queueZoom(steps: Int) {
        if (host == null) return
        reports.key(byteArrayOf(0x01, 0, 0, 0, 0, 0, 0, 0)) // Ctrl down
        reports.mouse(reports.buttons, 0, 0, steps, 0)
        reports.key(ByteArray(8)) // Ctrl up
    }

    /** Runs on the report thread. */
    private fun sendNow(id: Int, report: ByteArray) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        val hid = hid ?: return
        val host = host ?: return
        try {
            hid.sendReport(host, id, report)
        } catch (e: RuntimeException) {
            // The connection dropped mid-send; the state callback will follow.
        }
    }

    private val bluetoothChanges = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothAdapter.ACTION_STATE_CHANGED ->
                    when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)) {
                        BluetoothAdapter.STATE_ON -> if (wanted) start()
                        BluetoothAdapter.STATE_OFF -> {
                            main.removeCallbacks(reconnect)
                            reports.clear()
                            releaseProxy()
                            registered = false
                            host = null
                            target = null
                            if (wanted) update("bluetoothOff")
                        }
                    }
                // A PC was just paired: let Dart refresh its list.
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> if (wanted) emit()
            }
        }
    }

    private fun listenForBluetoothChanges() {
        if (listening) return
        listening = true
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(bluetoothChanges, filter, Context.RECEIVER_EXPORTED)
        } else {
            activity.registerReceiver(bluetoothChanges, filter)
        }
    }

    private fun releaseProxy() {
        val proxy = hid ?: return
        hid = null
        adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, proxy)
    }

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
        } else {
            emptyArray() // granted at install time before Android 12
        }

    private fun hasPermissions() = requiredPermissions().all {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    fun onPermissionsResult(requestCode: Int) {
        if (requestCode != REQUEST_PERMISSIONS || !wanted) return
        if (hasPermissions()) {
            start()
        } else {
            update("needsPermission", "Allow \"Nearby devices\" so the phone can work as a Bluetooth touchpad.")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int) {
        // For a discoverability request the result code is how many seconds it lasts.
        if (requestCode != REQUEST_DISCOVERABLE || resultCode <= 0) return
        discoverableUntil = System.currentTimeMillis() + resultCode * 1000L
        emit()
        main.postDelayed({
            discoverableUntil = null
            emit()
        }, resultCode * 1000L)
    }

    private fun requestEnable() {
        if (!hasPermissions()) return start()
        try {
            activity.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_ENABLE)
        } catch (e: RuntimeException) {
            update("bluetoothOff", "Turn on Bluetooth in the phone's settings.")
        }
    }

    private fun requestDiscoverable() {
        if (!hasPermissions()) return start()
        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
            .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120)
        try {
            activity.startActivityForResult(intent, REQUEST_DISCOVERABLE)
        } catch (e: RuntimeException) {
            update(phase, "Open Bluetooth settings on the phone to make it visible.")
        }
    }

    private fun openAppSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", activity.packageName, null),
        )
        try {
            activity.startActivity(intent)
        } catch (e: RuntimeException) {
            // No settings screen; nothing else to offer.
        }
    }

    private fun update(phase: String, message: String? = null) {
        this.phase = phase
        this.message = message
        emit()
    }

    private fun emit() {
        val device = host ?: target
        val payload = mapOf(
            "phase" to phase,
            "message" to message,
            "device" to device?.let { deviceName(it) },
            "discoverableUntil" to discoverableUntil,
        )
        main.post { sink?.success(payload) }
    }

    private fun deviceName(device: BluetoothDevice): String =
        (if (hasPermissions()) device.name else null) ?: device.address

    companion object {
        private const val REQUEST_PERMISSIONS = 4101
        private const val REQUEST_ENABLE = 4102
        private const val REQUEST_DISCOVERABLE = 4103
        private const val KEY_LAST_HOST = "last_host"
    }
}

/**
 * Sends HID reports in order from one high-priority thread. Pointer movement
 * that arrives while a report is waiting its turn is merged into it, so only
 * fresh movement goes out, at most every [MOUSE_INTERVAL_MS].
 */
private class ReportSender(private val send: (id: Int, report: ByteArray) -> Unit) {
    private class Move(val buttons: Int, var dx: Int, var dy: Int, var wheel: Int, var pan: Int)
    private class Key(val report: ByteArray)

    private val lock = ReentrantLock()
    private val changed = lock.newCondition()
    private val queue = ArrayDeque<Any>()
    private var lastMouseAt = 0L
    @Volatile private var running = true

    /** Buttons held in the latest mouse report. */
    @Volatile var buttons = 0
        private set

    /** Keep the link out of its slow idle rhythm (set while the app is open and connected). */
    @Volatile var keepAwake = false

    init {
        Thread(::loop, "hid-reports").apply {
            isDaemon = true
            start()
        }
    }

    fun mouse(buttons: Int, dx: Int, dy: Int, wheel: Int, pan: Int) = lock.withLock {
        val last = queue.lastOrNull()
        if (last is Move && last.buttons == buttons) {
            last.dx += dx
            last.dy += dy
            last.wheel += wheel
            last.pan += pan
        } else {
            queue.addLast(Move(buttons, dx, dy, wheel, pan))
        }
        this.buttons = buttons
        changed.signalAll()
    }

    fun key(report: ByteArray) = lock.withLock {
        queue.addLast(Key(report))
        changed.signalAll()
    }

    /** Drops whatever hasn't gone out (the PC went away). */
    fun clear() = lock.withLock {
        queue.clear()
        buttons = 0
        keepAwake = false
    }

    fun shutdown() = lock.withLock {
        running = false
        queue.clear()
        changed.signalAll()
    }

    private fun loop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_DISPLAY)
        while (running) {
            when (val item = next()) {
                is Move -> send(REPORT_MOUSE, mouseReport(item))
                is Key -> send(REPORT_KEYBOARD, item.report)
            }
        }
    }

    /** The next report to send, or null to look again. */
    private fun next(): Any? = lock.withLock {
        if (running && queue.isEmpty()) {
            val idle = !changed.await(KEEP_AWAKE_MS, TimeUnit.MILLISECONDS)
            if (!running) return null
            if (idle && queue.isEmpty()) return if (keepAwake) Move(buttons, 0, 0, 0, 0) else null
            if (queue.isEmpty()) return null
        }
        if (!running) return null
        if (queue.first() is Move) {
            val wait = lastMouseAt + MOUSE_INTERVAL_MS - SystemClock.uptimeMillis()
            if (wait > 0) {
                // Its turn hasn't come yet; newer movement can still merge in.
                changed.await(wait, TimeUnit.MILLISECONDS)
                return null
            }
            lastMouseAt = SystemClock.uptimeMillis()
        }
        queue.removeFirst()
    }

    private fun mouseReport(m: Move): ByteArray {
        val dx = m.dx.coerceIn(-32767, 32767)
        val dy = m.dy.coerceIn(-32767, 32767)
        return byteArrayOf(
            m.buttons.toByte(),
            dx.toByte(), (dx shr 8).toByte(), // X, little-endian 16-bit
            dy.toByte(), (dy shr 8).toByte(), // Y
            m.wheel.coerceIn(-127, 127).toByte(),
            m.pan.coerceIn(-127, 127).toByte(),
        )
    }
}

/**
 * What the PC learns about us when it pairs: report 1 is a standard keyboard
 * (8 bytes), report 2 a 3-button mouse with 16-bit X/Y, a wheel and a
 * horizontal wheel (7 bytes).
 */
object HidDescriptor {
    val REPORT_MAP: ByteArray = intArrayOf(
        // Keyboard
        0x05, 0x01, // Usage Page (Generic Desktop)
        0x09, 0x06, // Usage (Keyboard)
        0xA1, 0x01, // Collection (Application)
        0x85, 0x01, //   Report ID (1)
        0x05, 0x07, //   Usage Page (Key Codes)
        0x19, 0xE0, 0x29, 0xE7, //   Usage Min/Max (Left Ctrl .. Right GUI)
        0x15, 0x00, 0x25, 0x01, //   Logical Min/Max (0, 1)
        0x75, 0x01, 0x95, 0x08, //   8 x 1 bit
        0x81, 0x02, //   Input (Data, Var, Abs): modifier bits
        0x95, 0x01, 0x75, 0x08, //   1 x 8 bits
        0x81, 0x01, //   Input (Const): reserved
        0x95, 0x05, 0x75, 0x01, //   5 x 1 bit
        0x05, 0x08, //   Usage Page (LEDs)
        0x19, 0x01, 0x29, 0x05, //   Usage Min/Max (Num Lock .. Kana)
        0x91, 0x02, //   Output (Data, Var, Abs): LEDs
        0x95, 0x01, 0x75, 0x03, //   1 x 3 bits
        0x91, 0x01, //   Output (Const): padding
        0x95, 0x06, 0x75, 0x08, //   6 x 8 bits
        0x15, 0x00, 0x25, 0x65, //   Logical Min/Max (0, 101)
        0x05, 0x07, //   Usage Page (Key Codes)
        0x19, 0x00, 0x29, 0x65, //   Usage Min/Max (0, 101)
        0x81, 0x00, //   Input (Data, Array): pressed keys
        0xC0, // End Collection

        // Mouse
        0x05, 0x01, // Usage Page (Generic Desktop)
        0x09, 0x02, // Usage (Mouse)
        0xA1, 0x01, // Collection (Application)
        0x85, 0x02, //   Report ID (2)
        0x09, 0x01, //   Usage (Pointer)
        0xA1, 0x00, //   Collection (Physical)
        0x05, 0x09, //     Usage Page (Buttons)
        0x19, 0x01, 0x29, 0x03, //     Buttons 1..3
        0x15, 0x00, 0x25, 0x01, //     Logical Min/Max (0, 1)
        0x95, 0x03, 0x75, 0x01, //     3 x 1 bit
        0x81, 0x02, //     Input (Data, Var, Abs)
        0x95, 0x01, 0x75, 0x05, //     1 x 5 bits
        0x81, 0x03, //     Input (Const): padding
        0x05, 0x01, //     Usage Page (Generic Desktop)
        0x09, 0x30, 0x09, 0x31, //     Usage (X), Usage (Y)
        0x16, 0x01, 0x80, //     Logical Min (-32767)
        0x26, 0xFF, 0x7F, //     Logical Max (32767)
        0x75, 0x10, 0x95, 0x02, //     2 x 16 bits
        0x81, 0x06, //     Input (Data, Var, Rel)
        0x09, 0x38, //     Usage (Wheel)
        0x15, 0x81, 0x25, 0x7F, //     Logical Min/Max (-127, 127)
        0x75, 0x08, 0x95, 0x01, //     1 x 8 bits
        0x81, 0x06, //     Input (Data, Var, Rel)
        0x05, 0x0C, //     Usage Page (Consumer)
        0x0A, 0x38, 0x02, //     Usage (AC Pan): horizontal wheel
        0x15, 0x81, 0x25, 0x7F, //     Logical Min/Max (-127, 127)
        0x75, 0x08, 0x95, 0x01, //     1 x 8 bits
        0x81, 0x06, //     Input (Data, Var, Rel)
        0xC0, //   End Collection
        0xC0, // End Collection
    ).map { it.toByte() }.toByteArray()
}
