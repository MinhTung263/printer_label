package com.printer.printer_label

import android.annotation.TargetApi
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import net.posprinter.IConnectListener
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.TSPLConst
import net.posprinter.TSPLPrinter
import net.posprinter.model.AlgorithmType
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import io.flutter.plugin.common.EventChannel

/** PrinterLabelPlugin — Multi-connection manager */
class PrinterLabelPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var scanEventChannel: EventChannel
    private lateinit var usbEventChannel: EventChannel
    private var CHANNEL = "flutter_printer_label"
    private val SCAN_CHANNEL = "flutter_printer_label/bt_scan"
    private val USB_CHANNEL = "flutter_printer_label/usb_events"
    var mContext: Context? = null
    private var usbEventSink: EventChannel.EventSink? = null

    // ─── Multi-connection store ───────────────────────────────────────────────
    // Key   = device id: MAC address | IP address | USB device path
    // Value = active IDeviceConnection
    private val connections = mutableMapOf<String, IDeviceConnection>()

    // Pending connect state — keyed by deviceId so parallel connects don't clash
    private data class PendingConnect(
        val result: MethodChannel.Result,
        val type: String,
        val deviceId: String
    )
    private val pendingConnects = mutableMapOf<String, PendingConnect>()

    private lateinit var usbReceiver: UsbConnectionReceiver
    private var printThermal = PrinterThermal()
    private var scanEventSink: EventChannel.EventSink? = null
    private var btScanReceiver: BroadcastReceiver? = null

    override fun onAttachedToEngine(
            @NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    ) {
        channel = MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL)
        channel.setMethodCallHandler(this)
        scanEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, SCAN_CHANNEL)
        scanEventChannel.setStreamHandler(btScanStreamHandler)
        usbEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, USB_CHANNEL)
        usbEventChannel.setStreamHandler(usbEventStreamHandler)
        mContext = flutterPluginBinding.getApplicationContext()
        POSConnect.init(mContext)
        usbReceiver = UsbConnectionReceiver(channel, this)
        val filter = IntentFilter(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        flutterPluginBinding.applicationContext.registerReceiver(usbReceiver, filter)
        registerUsbPermissionReceiver()
    }
    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scanEventChannel.setStreamHandler(null)
        usbEventChannel.setStreamHandler(null)
        stopBluetoothScan()
        connections.values.forEach { runCatching { it.close() } }
        connections.clear()
        runCatching { binding.applicationContext.unregisterReceiver(usbReceiver) }
    }

    // ─── Method dispatch ──────────────────────────────────────────────────────

    @RequiresApi(Build.VERSION_CODES.HONEYCOMB_MR1)
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "checkConnect" -> {
                val deviceId = call.argument<String>("device_id")
                if (deviceId != null) {
                    result.success(connections[deviceId]?.isConnect() ?: false)
                } else {
                    // Return all active connections as map { deviceId: true/false }
                    val map = connections.mapValues { (_, conn) -> conn.isConnect() }
                    result.success(map)
                }
            }

            "disconnect" -> {
                val deviceId = call.argument<String>("device_id")
                if (deviceId.isNullOrEmpty()) {
                    // Disconnect ALL
                    disconnectAll(result)
                } else {
                    disconnectPrinter(deviceId, result)
                }
            }

            "connect_lan" -> {
                val ipAddress = call.argument<String>("ip_address")
                if (ipAddress.isNullOrEmpty()) {
                    result.success(false)
                    return
                }
                connectNet(ipAddress, result)
            }
            "connect_bt" -> {
                val macAddress = call.argument<String>("mac_address")
                if (macAddress.isNullOrEmpty()) {
                    result.success(false)
                    return
                }
                // Gọi hàm connectBt và truyền result để trả về cho Flutter
                connectBt(macAddress, result)
            }
            "get_bluetooth_devices" -> {
                getBluetoothDevices(result)
            }
            "print_barcode" -> {
                val deviceId = call.argument<String>("device_id") ?: run {
                    result.error("NO_DEVICE_ID", "device_id is required", null); return
                }
                val conn = requireConnection(deviceId, result) ?: return
                printBarcode(call, conn, result)
            }

            "print_label" -> {
                val deviceId = call.argument<String>("device_id") ?: run {
                    result.error("NO_DEVICE_ID", "device_id is required", null); return
                }
                val conn = requireConnection(deviceId, result) ?: return
                printLabel(call, conn, result)
            }

            "print_image_esc" -> {
                val deviceId = call.argument<String>("device_id") ?: run {
                    result.error("NO_DEVICE_ID", "device_id is required", null); return
                }
                val conn = requireConnection(deviceId, result) ?: return
                printThermal.printImageESC(call, conn, result)
            }

            else -> result.notImplemented()
        }
    }

    // ─── Connection helpers ───────────────────────────────────────────────────

    /** Returns the connection or sends an error and returns null. */
    private fun requireConnection(deviceId: String, result: Result): IDeviceConnection? {
        val conn = connections[deviceId]
        if (conn == null || !conn.isConnect()) {
            result.error("NOT_CONNECTED", "No active connection for device: $deviceId", null)
            return null
        }
        return conn
    }

    /** Build a per-device IConnectListener so parallel connects don't race. */
    private fun makeConnectListener(deviceId: String): IConnectListener =
        IConnectListener { code, _, _ ->
            val pending = pendingConnects[deviceId]
            when (code) {
                POSConnect.CONNECT_SUCCESS -> {
                    pending?.result?.success(true)
                    toast("Kết nối ${pending?.type ?: deviceId} thành công!")
                    if (pending?.type == "USB") emitUsbEvent(deviceId, true)
                    pendingConnects.remove(deviceId)
                }
                POSConnect.CONNECT_FAIL, POSConnect.CONNECT_INTERRUPT -> {
                    runCatching { connections[deviceId]?.close() }
                    connections.remove(deviceId)
                    pending?.result?.success(false)
                    toast("Kết nối ${pending?.type ?: deviceId} thất bại hoặc bị gián đoạn")
                    pendingConnects.remove(deviceId)
                }
                POSConnect.SEND_FAIL -> toast("SEND_FAIL [$deviceId]")
                POSConnect.USB_DETACHED -> {
                    runCatching { connections[deviceId]?.close() }
                    connections.remove(deviceId)
                    emitUsbEvent(deviceId, false)
                    toast("USB bị ngắt kết nối [$deviceId]")
                }
                POSConnect.USB_ATTACHED -> toast("USB được gắn [$deviceId]")
            }
        }

    private fun disconnectPrinter(deviceId: String, result: Result) {
        try {
            connections[deviceId]?.close()
            connections.remove(deviceId)
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCONNECT_ERROR", e.message, null)
        }
    }

    private fun disconnectAll(result: Result) {
        try {
            connections.values.forEach { runCatching { it.close() } }
            connections.clear()
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCONNECT_ERROR", e.message, null)
        }
    }

    // ─── Connect implementations ──────────────────────────────────────────────

    fun connectUSB(pathName: String) {
        val deviceId = pathName
        try {
            pendingConnects[deviceId] = PendingConnect(
                result = NoOpResult, // USB attach is fire-and-forget from receiver
                type = "USB",
                deviceId = deviceId
            )
            runCatching { connections[deviceId]?.close() }
            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_USB) ?: run {
                pendingConnects.remove(deviceId); return
            }
            connections[deviceId] = device
            device.connect(pathName, makeConnectListener(deviceId))
        } catch (e: Exception) {
            connections.remove(deviceId)
            pendingConnects.remove(deviceId)
            Log.e("USB_CONNECT", "connectUSB failed", e)
        }
    }

    private fun connectNet(ipAddress: String, result: Result) {
        val deviceId = ipAddress
        try {
            pendingConnects[deviceId] = PendingConnect(result, "LAN", deviceId)
            runCatching { connections[deviceId]?.close() }
            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_ETHERNET) ?: run {
                pendingConnects.remove(deviceId)
                result.error("CREATE_DEVICE_FAIL", "Cannot create device", null)
                return
            }
            connections[deviceId] = device
            device.connect(ipAddress, makeConnectListener(deviceId))
        } catch (e: Exception) {
            connections.remove(deviceId)
            pendingConnects.remove(deviceId)
            result.error("CONNECT_ERROR", e.message, null)
        }
    }

    private fun connectBt(macAddress: String, result: Result) {
        val deviceId = macAddress
        try {
            if (macAddress.isEmpty()) { result.error("INVALID_MAC", "Mac address is empty", null); return }

            val adapter = getBluetoothAdapter()
            if (adapter == null || !adapter.isEnabled) {
                result.error("BT_OFF", "Bluetooth is not enabled", null); return
            }

            stopBluetoothScan()

            pendingConnects[deviceId] = PendingConnect(result, "Bluetooth", deviceId)
            runCatching { connections[deviceId]?.close() }

            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_BLUETOOTH) ?: run {
                pendingConnects.remove(deviceId)
                result.error("CREATE_DEVICE_FAIL", "Cannot create device", null)
                return
            }
            connections[deviceId] = device
            device.connect(macAddress, makeConnectListener(deviceId))
        } catch (e: Exception) {
            e.printStackTrace()
            connections.remove(deviceId)
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
                val deviceId = device?.deviceName ?: return
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
        toast("USB được gắn: ${device.deviceName}")
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
        }
    }

    fun handleUsbDeviceDetached(device: UsbDevice?) {
        val deviceId = device?.deviceName ?: return
        runCatching { connections[deviceId]?.close() }
        connections.remove(deviceId)
        emitUsbEvent(deviceId, false)
        toast("USB bị ngắt kết nối [$deviceId]")
    }

    private fun tryConnectWithDelay(device: UsbDevice, attempt: Int) {
        if (attempt > 3) {
            toast("Kết nối USB thất bại sau nhiều lần thử")
            val deviceId = device.deviceName
            pendingConnects[deviceId]?.result?.success(false)
            pendingConnects.remove(deviceId)
            return
        }
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val pathName = device.deviceName
                val deviceId = pathName
                runCatching { connections[deviceId]?.close() }

                val posDevice = POSConnect.createDevice(POSConnect.DEVICE_TYPE_USB) ?: return@postDelayed
                connections[deviceId] = posDevice

                if (pendingConnects[deviceId] == null) {
                    // Fire-and-forget from attach event — register a dummy pending so listener fires toast
                    pendingConnects[deviceId] = PendingConnect(NoOpResult, "USB", deviceId)
                }
                posDevice.connect(pathName, makeConnectListener(deviceId))
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
        }
        override fun onCancel(arguments: Any?) {
            usbEventSink = null
        }
    }

    /** Emit USB connect/disconnect events to Flutter. */
    private fun emitUsbEvent(deviceId: String, connected: Boolean) {
        Handler(Looper.getMainLooper()).post {
            usbEventSink?.success(mapOf("device_id" to deviceId, "connected" to connected))
        }
    }

    // ─── Bluetooth scan ───────────────────────────────────────────────────────

    private val btScanStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            scanEventSink = events; startBluetoothScan()
        }
        override fun onCancel(arguments: Any?) {
            stopBluetoothScan(); scanEventSink = null
        }
    }

    private fun startBluetoothScan() {
        val adapter = getBluetoothAdapter() ?: return
        if (!adapter.isEnabled) {
            scanEventSink?.error("BT_OFF", "Bluetooth is not enabled", null)
            return
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val device: BluetoothDevice? =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                            } else {
                                @Suppress("DEPRECATION")
                                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                            }
                        device?.let {
                            try {
                                val map = mapOf("name" to (it.name ?: "Unknown"), "mac" to it.address)
                                Handler(Looper.getMainLooper()).post {
                                    scanEventSink?.success(map)
                                }
                            } catch (_: SecurityException) {}
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        Handler(Looper.getMainLooper()).post {
                            scanEventSink?.endOfStream()
                        }
                        stopBluetoothScan()
                    }
                }
            }
        }
        val filter = IntentFilter(BluetoothDevice.ACTION_FOUND).apply {
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        mContext?.registerReceiver(receiver, filter)
        btScanReceiver = receiver
        try {
            if (adapter.isDiscovering) adapter.cancelDiscovery()
            adapter.startDiscovery()
        } catch (_: SecurityException) {
            scanEventSink?.error("BT_PERMISSION", "Missing BLUETOOTH_SCAN permission", null)
        }
    }

    private fun stopBluetoothScan() {
        runCatching { getBluetoothAdapter()?.cancelDiscovery() }
        runCatching { btScanReceiver?.let { mContext?.unregisterReceiver(it) } }
        btScanReceiver = null
    }

    private fun getBluetoothAdapter(): BluetoothAdapter? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            (mContext?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        else @Suppress("DEPRECATION") BluetoothAdapter.getDefaultAdapter()

    private fun getBluetoothDevices(result: MethodChannel.Result) {
        try {
            val adapter = getBluetoothAdapter()
            if (adapter == null || !adapter.isEnabled) { result.error("BT_OFF", "Bluetooth is not enabled", null); return }
            val list = adapter.bondedDevices.map { mapOf("name" to (it.name ?: "Unknown"), "mac" to it.address) }
            result.success(list)
        } catch (e: SecurityException) {
            result.error("BT_PERMISSION", "Missing BLUETOOTH_CONNECT permission", null)
        } catch (e: Exception) {
            result.error("BT_ERROR", e.message, null)
        }
    }

    // ─── Print implementations ────────────────────────────────────────────────

    private fun printBarcode(call: MethodCall, curConnect: IDeviceConnection, result: Result) {
        val size = call.argument<Map<String, Double>>("size")
        val gap = call.argument<Map<String, Double>>("gap")
        val barcode = call.argument<Map<String, Any>>("barcode")
        val textList = call.argument<List<Map<String, Any>>>("text")
        val quantity = call.argument<Int>("quantity") ?: 1
        val (sizeWidth, sizeHeight) = extractSize(size)
        val (gapWidth, gapHeight) = extractGap(gap)
        // Initialize printer
        val printer = TSPLPrinter(curConnect)
        printer.sizeMm(sizeWidth, sizeHeight)
        printer.gapMm(gapWidth, gapHeight)
        printer.cls()
        barcode?.let { processBarcode(it, printer) }

        // Process text
        textList?.forEach { text -> processText(text, printer) }

        printer.print(quantity)
        result.success("Printed Successfully")
    }

    private fun printLabel(call: MethodCall, conn: IDeviceConnection, result: Result) {
        try {
            val type = call.argument<String>("type")
            if (type != "TSPL") { result.success(false); return }

            val images: List<ByteArray>? = call.argument<List<ByteArray>>("images")
            if (images.isNullOrEmpty()) { result.success(false); return }

            val printer = TSPLPrinter(conn)
            val size = call.argument<Map<String, Int>>("size")
            val (sizeWidth, sizeHeight) = extractSizeImage(size)
            val x = call.argument<Int>("x") ?: 0
            val y = call.argument<Int>("y") ?: 0

            images.forEach { imageData ->
                val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size) ?: return@forEach
                printer.sizeMm(sizeWidth.toDouble(), sizeHeight.toDouble())
                    .cls()
                    .bitmap(x, y, TSPLConst.BMP_MODE_OVERWRITE, 900, bitmap, AlgorithmType.Threshold)
                    .print(1)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private fun extractSize(size: Map<String, Double>?) = Pair(size?.get("width") ?: 200.0, size?.get("height") ?: 30.0)
    private fun extractGap(gap: Map<String, Double>?) = Pair(gap?.get("width") ?: 0.0, gap?.get("height") ?: 0.0)
    private fun extractSizeImage(size: Map<String, Int>?) = Pair(size?.get("width") ?: 600, size?.get("height") ?: 20)

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

    private fun toast(str: String) = Toast.makeText(mContext, str, Toast.LENGTH_SHORT).show()

    companion object {
        private const val ACTION_USB_PERMISSION = "com.printer.printer_label.USB_PERMISSION"
        /** A no-op Result used for fire-and-forget connects (e.g. USB auto-attach). */
        private val NoOpResult = object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
            override fun notImplemented() {}
        }
    }
}