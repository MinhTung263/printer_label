package com.printer.printer_label

import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import android.app.Activity
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import net.posprinter.IConnectListener
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.posprinterface.IStatusCallback
import net.posprinter.POSConst
import net.posprinter.POSPrinter
import net.posprinter.TSPLConst
import net.posprinter.TSPLPrinter
import net.posprinter.model.AlgorithmType

/** PrinterLabelPlugin — Multi-connection manager */
class PrinterLabelPlugin : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener {
    internal var activity: Activity? = null
    internal var activityBinding: ActivityPluginBinding? = null
    internal val bluetoothManager = BluetoothPrinterManager(this)
    internal var permissionCallback: ((Boolean) -> Unit)? = null

    private lateinit var channel: MethodChannel
    private lateinit var scanEventChannel: EventChannel
    private lateinit var usbEventChannel: EventChannel
    private var CHANNEL = "flutter_printer_label"
    private val SCAN_CHANNEL = "flutter_printer_label/bt_scan"
    private val USB_CHANNEL = "flutter_printer_label/usb_events"
    var mContext: Context? = null
    private var usbEventSink: EventChannel.EventSink? = null

    // ─── Multi-connection store ───────────────────────────────────────────────
    // Key   = device id: MAC address | IP address | stable USB id (USB:v{vid}_p{pid}_s{serial})
    // Value = active IDeviceConnection
    internal val connections = mutableMapOf<String, IDeviceConnection>()

    // Type label for each connection: "USB" | "LAN" | "BT"
    internal val connectionTypes = mutableMapOf<String, ConnectionType>()
    internal val printerModes = java.util.concurrent.ConcurrentHashMap<String, String>()

    // Maps stable USB id → actual device path (e.g. /dev/bus/usb/001/002)
    // Updated each time the device is attached so rawId() always has the current path.
    private val usbDevicePaths = mutableMapOf<String, String>()

    // Pending connect state — keyed by deviceId so parallel connects don't clash
    internal data class PendingConnect(
        val result: Result,
        val type: ConnectionType,
        val deviceId: String
    )

    internal val pendingConnects = mutableMapOf<String, PendingConnect>()

    @Volatile internal var isDetached = false

    private lateinit var usbReceiver: UsbConnectionReceiver
    internal var printThermal = PrinterThermal()
    private lateinit var methodCallHandler: PrinterMethodCallHandler

    override fun onAttachedToEngine(
        @NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    ) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        methodCallHandler = PrinterMethodCallHandler(this)
        channel.setMethodCallHandler(methodCallHandler)
        scanEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, SCAN_CHANNEL)
        scanEventChannel.setStreamHandler(bluetoothManager.btScanStreamHandler)
        usbEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, USB_CHANNEL)
        usbEventChannel.setStreamHandler(usbEventStreamHandler)
        isDetached = false
        mContext = flutterPluginBinding.applicationContext
        POSConnect.init(mContext)
        usbReceiver = UsbConnectionReceiver(channel, this)
        val filter = IntentFilter(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        flutterPluginBinding.applicationContext.registerReceiver(usbReceiver, filter)
        registerUsbPermissionReceiver()
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        isDetached = true
        channel.setMethodCallHandler(null)
        scanEventChannel.setStreamHandler(null)
        usbEventChannel.setStreamHandler(null)
        bluetoothManager.stopBluetoothScan()
        connections.values.forEach { runCatching { it.close() } }
        connections.clear()
        connectionTypes.clear()
        pendingConnects.clear()
        runCatching { binding.applicationContext.unregisterReceiver(usbReceiver) }
        runCatching { binding.applicationContext.unregisterReceiver(permissionReceiver) }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.activity = binding.activity
        this.activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        this.activity = null
        this.activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        this.activity = binding.activity
        this.activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        this.activity = null
        this.activityBinding = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == BluetoothPrinterManager.REQUEST_ENABLE_BT) {
            bluetoothManager.handleBluetoothEnableResult(resultCode)
            return true
        }
        return false
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == REQUEST_PERMISSIONS_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == android.content.pm.PackageManager.PERMISSION_GRANTED }
            permissionCallback?.invoke(allGranted)
            permissionCallback = null
            return true
        }
        return false
    }


    internal fun checkStatusESC(conn: IDeviceConnection, result: Result) {
        val handler = Handler(Looper.getMainLooper())
        var isDelivered = false

        val timeoutRunnable = Runnable {
            if (!isDelivered) {
                isDelivered = true
                result.success("unknown")
            }
        }
        handler.postDelayed(timeoutRunnable, 2000)

        try {
            val posPrinter = POSPrinter(conn)
            posPrinter.printerStatus { code ->
                if (!isDelivered) {
                    isDelivered = true
                    handler.removeCallbacks(timeoutRunnable)
                    val status = when (code) {
                        0 -> "normal"
                        1 -> "headOpened" // Cover open
                        2 -> "paperJam"
                        4 -> "outOfPaper" // Paper empty
                        else -> "normal"
                    }
                    val deviceId = connections.entries.find { it.value == conn }?.key
                    if (deviceId != null) {
                        printerModes[deviceId] = "ESC"
                    }
                    handler.post {
                        result.success(status)
                    }
                }
            }
        } catch (e: Exception) {
            if (!isDelivered) {
                isDelivered = true
                handler.removeCallbacks(timeoutRunnable)
                result.success("normal")
            }
        }
    }

    internal fun checkStatusTSPL(conn: IDeviceConnection, result: Result) {
        val handler = Handler(Looper.getMainLooper())
        var isDelivered = false

        val timeoutRunnable = Runnable {
            if (!isDelivered) {
                isDelivered = true
                result.success("unknown")
            }
        }
        handler.postDelayed(timeoutRunnable, 2000)

        try {
            val tsplPrinter = TSPLPrinter(conn)
            tsplPrinter.printerStatus(1500) { code ->
                if (!isDelivered) {
                    isDelivered = true
                    handler.removeCallbacks(timeoutRunnable)
                    val status = when (code) {
                        0 -> "normal"
                        1 -> "headOpened"
                        2 -> "paperJam"
                        3 -> "paperJam"
                        4 -> "outOfPaper"
                        5 -> "outOfPaper"
                        8 -> "outOfRibbon"
                        9 -> "outOfRibbon"
                        10 -> "outOfRibbon"
                        11 -> "outOfRibbon"
                        12 -> "outOfRibbon"
                        13 -> "outOfRibbon"
                        16 -> "pause"
                        32 -> "printing"
                        else -> "normal"
                    }
                    val deviceId = connections.entries.find { it.value == conn }?.key
                    if (deviceId != null) {
                        printerModes[deviceId] = "TSPL"
                    }
                    handler.post {
                        result.success(status)
                    }
                }
            }
        } catch (e: Exception) {
            if (!isDelivered) {
                isDelivered = true
                handler.removeCallbacks(timeoutRunnable)
                result.success("normal")
            }
        }
    }

    internal fun isConnectionActive(deviceId: String): Boolean {
        val conn = connections[deviceId] ?: return false
        if (!conn.isConnect) return false
        
        // Nếu là kết nối Bluetooth mà Bluetooth adapter của hệ thống đang tắt, coi như mất kết nối
        if (connectionTypes[deviceId] == ConnectionType.BT) {
            try {
                val adapter = bluetoothManager.getBluetoothAdapter()
                if (adapter == null || !adapter.isEnabled) {
                    return false
                }
            } catch (e: Exception) {
                // Tránh lỗi bảo mật (SecurityException) trên Android 12+ khi chưa cấp quyền Bluetooth,
                // fallback trả về trạng thái kết nối mặc định của SDK máy in
                return conn.isConnect
            }
        }
        return true
    }

    internal fun getConn(call: MethodCall): IDeviceConnection? {
        val deviceId = call.argument<String>("device_id")

        if (!deviceId.isNullOrEmpty()) {
            val conn = connections[deviceId]
            if (conn != null && isConnectionActive(deviceId)) return conn
            
            // Thử khớp khóa phụ (không có tiền tố hoặc tự thêm tiền tố LAN/BT)
            val altKey = if (deviceId.contains(":")) deviceId.substringAfter(":") else deviceId
            val conn2 = connections[altKey] ?: connections["LAN:$deviceId"] ?: connections["BT:$deviceId"]
            if (conn2 != null && isConnectionActive(altKey)) return conn2
            val keyLan = "LAN:$deviceId"
            if (connections.containsKey(keyLan) && isConnectionActive(keyLan)) return connections[keyLan]
            val keyBt = "BT:$deviceId"
            if (connections.containsKey(keyBt) && isConnectionActive(keyBt)) return connections[keyBt]
        }

        val activeKey = connections.keys.firstOrNull { isConnectionActive(it) }
        return if (activeKey != null) connections[activeKey] else null
    }



    internal fun resolveConnectionsForPrint(call: MethodCall): List<IDeviceConnection> {
        val deviceId = call.argument<String>("device_id")
        val targets = mutableListOf<IDeviceConnection>()

        // 1. Nếu thiết bị hỗ trợ in trực tiếp (Built-in Printer), luôn ưu tiên kết nối và thêm nó vào targets đầu tiên
        if (isBuiltInPrinter()) {
            val isConnected = connections.values.any { bluetoothManager.isConnectionToBuiltInPrinter(it) && it.isConnect }
            if (!isConnected) {
                bluetoothManager.autoConnectBuiltInSync()
            }
            val builtInConn = connections.entries.firstOrNull { 
                bluetoothManager.isConnectionToBuiltInPrinter(it.value) && isConnectionActive(it.key) 
            }?.value
            if (builtInConn != null) {
                targets.add(builtInConn)
            }
        }

        // 2. Thêm thiết bị được chỉ định cụ thể qua deviceId (nếu có)
        if (!deviceId.isNullOrEmpty()) {
            var specificConn = connections[deviceId]
            if (specificConn == null || !isConnectionActive(deviceId)) {
                val altKey = if (deviceId.contains(":")) deviceId.substringAfter(":") else deviceId
                val conn2 = connections[altKey] ?: connections["LAN:$deviceId"] ?: connections["BT:$deviceId"]
                if (conn2 != null && isConnectionActive(altKey)) {
                    specificConn = conn2
                } else {
                    val keyLan = "LAN:$deviceId"
                    if (connections.containsKey(keyLan) && isConnectionActive(keyLan)) {
                        specificConn = connections[keyLan]
                    } else {
                        val keyBt = "BT:$deviceId"
                        if (connections.containsKey(keyBt) && isConnectionActive(keyBt)) {
                            specificConn = connections[keyBt]
                        }
                    }
                }
            }
            // Chỉ thêm nếu specificConn khác null, đang hoạt động, và không bị trùng với builtInConn đã thêm trước đó
            if (specificConn != null && specificConn.isConnect) {
                if (!targets.contains(specificConn)) {
                    targets.add(specificConn)
                }
            }
        } else {
            // 3. Nếu không chỉ định deviceId, thêm tất cả các kết nối ngoại vi khác đang hoạt động
            if (isBuiltInPrinter()) {
                connections.entries.forEach { (key, conn) ->
                    if (isConnectionActive(key) && !bluetoothManager.isConnectionToBuiltInPrinter(conn)) {
                        if (!targets.contains(conn)) {
                            targets.add(conn)
                        }
                    }
                }
            } else {
                val activeKey = connections.keys.firstOrNull { isConnectionActive(it) }
                if (activeKey != null) {
                    connections[activeKey]?.let { targets.add(it) }
                }
            }
        }

        return targets
    }

    /** Build a per-device IConnectListener so parallel connects don't race. */
    internal fun makeConnectListener(deviceId: String): IConnectListener =
        IConnectListener { code, _, _ ->
            val pending = pendingConnects[deviceId]
            val isBuiltIn = isBuiltInPrinter()

            when (code) {
                POSConnect.CONNECT_SUCCESS -> {
                    pending?.result?.success(true)
                    connections[deviceId]?.let { detectPrinterMode(deviceId, it) }
                    if (!isBuiltIn) {
                        toast("Kết nối ${pending?.type ?: deviceId} thành công!")
                    }
                    if (pending?.type == ConnectionType.USB) emitUsbEvent(deviceId, true)
                    pendingConnects.remove(deviceId)
                }

                POSConnect.CONNECT_FAIL, POSConnect.CONNECT_INTERRUPT -> {
                    runCatching { connections[deviceId]?.close() }
                    connections.remove(deviceId)
                    connectionTypes.remove(deviceId)
                    pending?.result?.success(false)
                    if (!isBuiltIn) {
                        toast("Kết nối ${pending?.type ?: deviceId} thất bại hoặc bị gián đoạn")
                    }
                    pendingConnects.remove(deviceId)
                }

                POSConnect.SEND_FAIL -> {
                    if (!isBuiltIn) {
                        toast("SEND_FAIL [$deviceId]")
                    }
                }
                POSConnect.USB_DETACHED -> {
                    runCatching { connections[deviceId]?.close() }
                    connections.remove(deviceId)
                    connectionTypes.remove(deviceId)
                    emitUsbEvent(deviceId, false)
                    if (!isBuiltIn) {
                        toast("USB bị ngắt kết nối [$deviceId]")
                    }
                }

                POSConnect.USB_ATTACHED -> {
                    if (!isBuiltIn) {
                        toast("USB được gắn [$deviceId]")
                    }
                }
            }
        }

    internal fun detectPrinterMode(deviceId: String, conn: IDeviceConnection) {
        if (bluetoothManager.isConnectionToBuiltInPrinter(conn)) {
            printerModes[deviceId] = "ESC"
            return
        }

        kotlin.concurrent.thread {
            val latch = java.util.concurrent.CountDownLatch(1)
            try {
                val posPrinter = POSPrinter(conn)
                posPrinter.printerStatus { _ ->
                    printerModes[deviceId] = "ESC"
                    latch.countDown()
                }
            } catch (_: Exception) {}
            
            val escResponded = latch.await(800, java.util.concurrent.TimeUnit.MILLISECONDS)
            if (escResponded) return@thread

            try {
                val tsplPrinter = TSPLPrinter(conn)
                val latchTspl = java.util.concurrent.CountDownLatch(1)
                tsplPrinter.printerStatus(800) { _ ->
                    printerModes[deviceId] = "TSPL"
                    latchTspl.countDown()
                }
                latchTspl.await(800, java.util.concurrent.TimeUnit.MILLISECONDS)
            } catch (_: Exception) {}
        }
    }

    internal fun getFilteredConnections(type: ConnectionType? = null): List<IDeviceConnection> =
        connections.entries
            .filter { (id, conn) ->
                conn.isConnect && (type == null || connectionTypes[id] == type)
            }
            .map { it.value }
            .also { list ->
                if (list.isEmpty())
                    Log.w("PRINTER_LOG", "Không có thiết bị phù hợp để in (filter=$type).")
            }

    internal fun disconnectPrinter(deviceId: String, result: Result) {
        try {
            connections[deviceId]?.close()
            connections.remove(deviceId)
            connectionTypes.remove(deviceId)
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCONNECT_ERROR", e.message, null)
        }
    }

    internal fun disconnectAll(result: Result) {
        try {
            connections.values.forEach { runCatching { it.close() } }
            connections.clear()
            connectionTypes.clear()
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCONNECT_ERROR", e.message, null)
        }
    }


    // For USB: returns the current device path from usbDevicePaths (updates each attach).
    // For BT/LAN: strips the "TYPE:" prefix to get the raw address.
    internal fun rawId(deviceId: String): String =
        if (deviceId.startsWith("USB:")) usbDevicePaths[deviceId] ?: deviceId.substringAfter(':')
        else deviceId.substringAfter(':')

    private fun stableUsbId(device: UsbDevice): String {
        val serial = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1)
            runCatching { device.serialNumber }.getOrNull() else null
        return if (!serial.isNullOrBlank())
            "USB:v${device.vendorId}_p${device.productId}_s$serial"
        else
            "USB:v${device.vendorId}_p${device.productId}"
    }

    internal fun scheduleConnectTimeout(deviceId: String) {
        Handler(Looper.getMainLooper()).postDelayed({
            if (isDetached || !pendingConnects.containsKey(deviceId)) return@postDelayed
            runCatching { connections[deviceId]?.close() }
            connections.remove(deviceId)
            connectionTypes.remove(deviceId)
            pendingConnects[deviceId]?.result?.success(false)
            pendingConnects.remove(deviceId)
            
            if (!isBuiltInPrinter()) {
                toast("Kết nối $deviceId hết thời gian chờ")
            }
        }, CONNECT_TIMEOUT_MS)
    }

    internal fun connectNet(ipAddress: String, result: Result) {
        val deviceId = "LAN:$ipAddress"
        try {
            pendingConnects[deviceId] = PendingConnect(result, ConnectionType.LAN, deviceId)
            runCatching { connections[deviceId]?.close() }
            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_ETHERNET) ?: run {
                pendingConnects.remove(deviceId)
                result.error("CREATE_DEVICE_FAIL", "Cannot create device", null)
                return
            }
            connections[deviceId] = device
            connectionTypes[deviceId] = ConnectionType.LAN
            device.connect(ipAddress, makeConnectListener(deviceId))
            scheduleConnectTimeout(deviceId)
        } catch (e: Exception) {
            connections.remove(deviceId)
            connectionTypes.remove(deviceId)
            pendingConnects.remove(deviceId)
            result.error("CONNECT_ERROR", e.message, null)
        }
    }

    // ─── USB permission & attach handling ────────────────────────────────────

    private val usbManager: UsbManager by lazy {
        mContext!!.getSystemService(Context.USB_SERVICE) as UsbManager
    }

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_USB_PERMISSION) return
            val device: UsbDevice? = getUsbDeviceFromIntent(intent)
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            if (granted && device != null) {
                toast("Đã cấp quyền USB cho thiết bị")
                tryConnectWithDelay(device, 0)
            } else {
                toast("Người dùng từ chối quyền USB")
                val d = device ?: return
                val deviceId = stableUsbId(d)
                pendingConnects[deviceId]?.result?.success(false)
                pendingConnects.remove(deviceId)
            }
        }
    }

    private fun getUsbDeviceFromIntent(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        else @Suppress("DEPRECATION") intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)

    private fun registerUsbPermissionReceiver() {
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            mContext?.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else
            mContext?.registerReceiver(permissionReceiver, filter)
    }

    fun handleUsbDeviceAttached(device: UsbDevice) {
        val deviceId = stableUsbId(device)
        usbDevicePaths[deviceId] = device.deviceName  // update path for this plug-in event
        toast("USB được gắn: $deviceId")
        if (usbManager.hasPermission(device)) {
            tryConnectWithDelay(device, 0)
        } else {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            else PendingIntent.FLAG_UPDATE_CURRENT
            val permIntent = PendingIntent.getBroadcast(
                mContext!!, 0,
                Intent(ACTION_USB_PERMISSION).apply { setPackage(mContext!!.packageName) },
                flags
            )
            usbManager.requestPermission(device, permIntent)
            Handler(Looper.getMainLooper()).postDelayed({
                if (!isDetached && usbManager.hasPermission(device) &&
                    connections[deviceId]?.isConnect != true) {
                    tryConnectWithDelay(device, 0)
                }
            }, 500L)
        }
    }

    fun handleUsbDeviceDetached(device: UsbDevice?) {
        if (device == null) return
        val deviceId = stableUsbId(device)
        runCatching { connections[deviceId]?.close() }
        connections.remove(deviceId)
        connectionTypes.remove(deviceId)
        usbDevicePaths.remove(deviceId)
        emitUsbEvent(deviceId, false)
        toast("USB bị ngắt kết nối [$deviceId]")
    }

    private fun tryConnectWithDelay(device: UsbDevice, attempt: Int) {
        val deviceId = stableUsbId(device)
        usbDevicePaths[deviceId] = device.deviceName  // keep path current on each attempt
        if (attempt > 3) {
            toast("Kết nối USB thất bại sau nhiều lần thử")
            pendingConnects[deviceId]?.result?.success(false)
            pendingConnects.remove(deviceId)
            return
        }
        Handler(Looper.getMainLooper()).postDelayed({
            if (isDetached) return@postDelayed
            try {
                runCatching { connections[deviceId]?.close() }
                val posDevice = POSConnect.createDevice(POSConnect.DEVICE_TYPE_USB) ?: run {
                    Log.e("USB_CONNECT", "createDevice returned null (attempt $attempt)")
                    tryConnectWithDelay(device, attempt + 1)
                    return@postDelayed
                }
                connections[deviceId] = posDevice
                connectionTypes[deviceId] = ConnectionType.USB
                if (pendingConnects[deviceId] == null) {
                    pendingConnects[deviceId] =
                        PendingConnect(NoOpResult, ConnectionType.USB, deviceId)
                }
                posDevice.connect(rawId(deviceId), makeConnectListener(deviceId))
            } catch (e: Exception) {
                Log.e("USB_CONNECT", "Attempt $attempt failed", e)
                tryConnectWithDelay(device, attempt + 1)
            }
        }, if (attempt == 0) 1200L else 800L)
    }

    // ─── USB event stream ─────────────────────────────────────────────────────

    private val usbEventStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            usbEventSink = events
            scanAndConnectExistingUsbDevices()
        }

        override fun onCancel(arguments: Any?) {
            usbEventSink = null
        }
    }

    private fun scanAndConnectExistingUsbDevices() {
        try {
            val deviceList = usbManager.deviceList
            for (device in deviceList.values) {
                if (isUsbPrinter(device)) {
                    handleUsbDeviceAttached(device)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun isUsbPrinter(device: UsbDevice): Boolean {
        if (device.deviceClass == 7) return true
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == 7) return true
        }
        return false
    }

    /** Emit USB connect/disconnect events to Flutter. */
    private fun emitUsbEvent(deviceId: String, connected: Boolean) {
        Handler(Looper.getMainLooper()).post {
            usbEventSink?.success(mapOf("device_id" to deviceId, "connected" to connected))
        }
    }

    internal fun printLabel(call: MethodCall, conn: IDeviceConnection, result: Result) {
        try {
            val type = call.argument<String>("type")
            if (type != "TSPL") {
                result.success(false); return
            }

            val images: List<ByteArray>? = call.argument<List<ByteArray>>("images")
            if (images.isNullOrEmpty()) {
                result.success(false); return
            }

            val printer = TSPLPrinter(conn)
            val size = call.argument<Map<String, Any>>("size")
            val (sizeWidth, sizeHeight) = extractSizeImage(size)
            val gap = call.argument<Map<String, Any>>("gap")
            val gapWidth = (gap?.get("width") as? Number)?.toDouble() ?: 2.0
            val gapHeight = (gap?.get("height") as? Number)?.toDouble() ?: 0.0

            val targetWidthDots = sizeWidth * 8
            val targetHeightDots = sizeHeight * 8

            images.forEach { imageData ->
                val bitmap =
                    BitmapFactory.decodeByteArray(imageData, 0, imageData.size) ?: return@forEach
                
                // Scale bitmap to exactly targetWidthDots and targetHeightDots
                val scaledBitmap = Bitmap.createScaledBitmap(bitmap, targetWidthDots, targetHeightDots, true)
 
                // Compensate for printer's 20-dot hardware offset on the left
                val shiftX = -20f
                val shifted = Bitmap.createBitmap(targetWidthDots, targetHeightDots, scaledBitmap.config ?: Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(shifted)
                canvas.drawColor(android.graphics.Color.WHITE)
                canvas.drawBitmap(scaledBitmap, shiftX, 0f, null)
                
                if (scaledBitmap != bitmap) {
                    scaledBitmap.recycle()
                }
                bitmap.recycle()
 
                printer.sizeMm(sizeWidth.toDouble(), sizeHeight.toDouble())
                    .gapMm(gapWidth, gapHeight)
                    .reference(0, 0)
                    .direction(0)
                    .cls()
                    .bitmap(
                        0,
                        0,
                        TSPLConst.BMP_MODE_OVERWRITE,
                        targetWidthDots,
                        shifted,
                        AlgorithmType.Threshold
                    )
                    .print(1)

                shifted.recycle()
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    internal fun printText(call: MethodCall, conn: IDeviceConnection, result: Result) {
        try {
            val text = call.argument<String>("text") ?: ""
            val x = call.argument<Int>("x") ?: 0
            val y = call.argument<Int>("y") ?: 0
            val fontVal = call.argument<Int>("font") ?: 0
            val rotationVal = call.argument<Int>("rotation") ?: 0
            val sizeX = call.argument<Int>("sizeX") ?: 1
            val sizeY = call.argument<Int>("sizeY") ?: 1

            val fontStr = when (fontVal) {
                1 -> "1"
                else -> "3"
            }

            val rotationStr = when (rotationVal) {
                90 -> TSPLConst.ROTATION_90
                180 -> TSPLConst.ROTATION_180
                270 -> TSPLConst.ROTATION_270
                else -> TSPLConst.ROTATION_0
            }

            val sizeWidth = call.argument<Int>("width") ?: 40
            val sizeHeight = call.argument<Int>("height") ?: 30

            val printer = TSPLPrinter(conn)
            printer.sizeMm(sizeWidth.toDouble(), sizeHeight.toDouble())
                .cls()
                .text(x, y, fontStr, rotationStr, sizeX, sizeY, text)
                .print(1)

            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    internal fun printBarcode(call: MethodCall, conn: IDeviceConnection, result: Result) {
        try {
            val code = call.argument<String>("code") ?: ""
            val x = call.argument<Int>("x") ?: 0
            val y = call.argument<Int>("y") ?: 0
            val height = call.argument<Int>("height") ?: 100
            val typeVal = call.argument<String>("type") ?: "128"
            val width = call.argument<Int>("width") ?: 40
            val heightMM = call.argument<Int>("heightMM") ?: 30

            val barcodeType = when (typeVal) {
                "39" -> TSPLConst.CODE_TYPE_39
                "93" -> TSPLConst.CODE_TYPE_93
                "128" -> TSPLConst.CODE_TYPE_128
                else -> typeVal
            }

            val printer = TSPLPrinter(conn)
            printer.sizeMm(width.toDouble(), heightMM.toDouble())
                .cls()
                .barcode(x, y, barcodeType, height, TSPLConst.READABLE_LEFT, TSPLConst.ROTATION_0, 2, 2, code)
                .print(1)

            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    internal fun printQRCode(call: MethodCall, conn: IDeviceConnection, result: Result) {
        try {
            val code = call.argument<String>("code") ?: ""
            val x = call.argument<Int>("x") ?: 0
            val y = call.argument<Int>("y") ?: 0
            val size = call.argument<Int>("size") ?: 4
            val width = call.argument<Int>("width") ?: 40
            val heightMM = call.argument<Int>("heightMM") ?: 30

            val printer = TSPLPrinter(conn)
            printer.sizeMm(width.toDouble(), heightMM.toDouble())
                .cls()
                .qrcode(x, y, TSPLConst.EC_LEVEL_L, size, TSPLConst.QRCODE_MODE_MANUAL, TSPLConst.ROTATION_0, code)
                .print(1)

            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private fun extractSize(size: Map<String, Double>?) =
        Pair(size?.get("width") ?: 200.0, size?.get("height") ?: 30.0)

    private fun extractGap(gap: Map<String, Double>?) =
        Pair(gap?.get("width") ?: 0.0, gap?.get("height") ?: 0.0)

    private fun extractSizeImage(size: Map<String, Any>?) =
        Pair(
            (size?.get("width") as? Number)?.toInt() ?: 40,
            (size?.get("height") as? Number)?.toInt() ?: 25
        )

    private fun processBarcode(barcode: Map<String, Any>, printer: TSPLPrinter) {
        printer.barcode(
            barcode["x"] as? Int ?: 0,
            barcode["y"] as? Int ?: 30,
            barcode["type"] as? String ?: TSPLConst.CODE_TYPE_93,
            barcode["height"] as? Int ?: 100,
            TSPLConst.READABLE_CENTER,
            TSPLConst.ROTATION_0,
            2, 2,
            barcode["barcodeContent"] as? String ?: ""
        )
    }

    private fun processText(text: Map<String, Any>, printer: TSPLPrinter) {
        printer.text(
            text["x"] as? Int ?: 0,
            text["y"] as? Int ?: 144,
            text["font"] as? String ?: TSPLConst.FNT_16_24,
            text["rotation"] as? Int ?: TSPLConst.ROTATION_0,
            text["sizeX"] as? Int ?: 1,
            text["sizeY"] as? Int ?: 1,
            text["data"] as? String ?: ""
        )
    }

    internal fun toast(str: String) = Toast.makeText(mContext, str, Toast.LENGTH_SHORT).show()

    companion object {
        internal const val REQUEST_PERMISSIONS_CODE = 1002
        private const val ACTION_USB_PERMISSION = "com.printer.printer_label.USB_PERMISSION"
        private const val CONNECT_TIMEOUT_MS = 5_000L

        /** A no-op Result used for fire-and-forget connects (e.g. USB auto-attach). */
        private val NoOpResult = object : Result {
            override fun success(result: Any?) {}
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
            override fun notImplemented() {}
        }
    }
}