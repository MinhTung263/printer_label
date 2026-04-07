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

/** SamplePluginFlutterPlugin */
class PrinterLabelPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var scanEventChannel: EventChannel
    private var CHANNEL = "flutter_printer_label"
    private val SCAN_CHANNEL = "flutter_printer_label/bt_scan"
    public var mContext: Context? = null
    var curConnect: IDeviceConnection? = null
    private var pendingConnectResult: MethodChannel.Result? = null
    private var pendingConnectType: String? = null
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
        mContext = flutterPluginBinding.getApplicationContext()
        POSConnect.init(mContext)
        usbReceiver = UsbConnectionReceiver(channel, this)
        val filter = IntentFilter(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        flutterPluginBinding.applicationContext.registerReceiver(usbReceiver, filter)
        registerUsbPermissionReceiver()
    }

    @RequiresApi(Build.VERSION_CODES.HONEYCOMB_MR1)
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "checkConnect" -> {
                result.success(curConnect?.isConnect() ?: false)
            }
            "disconnect" -> {
                disconnectPrinter(result)
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
                printBarcode(call, result)
            }
            "print_label" -> {
                printLabel(call, result)
            }
            "print_image_esc" -> {
                printThermal.printImageESC(call, curConnect!!, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun disconnectPrinter(result: MethodChannel.Result) {
        try {
            curConnect?.close()
            curConnect = null
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCONNECT_ERROR", e.message, null)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scanEventChannel.setStreamHandler(null)
        stopBluetoothScan()
        curConnect?.close()
        curConnect = null
        try {
            binding.applicationContext.unregisterReceiver(usbReceiver)
        } catch (_: Exception) {}
    }

    private val btScanStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            scanEventSink = events
            startBluetoothScan()
        }
        override fun onCancel(arguments: Any?) {
            stopBluetoothScan()
            scanEventSink = null
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
        try { getBluetoothAdapter()?.cancelDiscovery() } catch (_: Exception) {}
        try { btScanReceiver?.let { mContext?.unregisterReceiver(it) } } catch (_: Exception) {}
        btScanReceiver = null
    }

    private val connectListener = IConnectListener { code, _, _ ->

        // Lưu lại type tại thời điểm callback
        val type = pendingConnectType

        when (code) {
            POSConnect.CONNECT_SUCCESS -> {
                // Chỉ accept nếu đang chờ connect
                if (type != null) {
                    pendingConnectResult?.success(true)
                    toast("Kết nối $type thành công!")
                }

                // Clear trạng thái chờ
                pendingConnectResult = null
                pendingConnectType = null
            }
            POSConnect.CONNECT_FAIL, POSConnect.CONNECT_INTERRUPT -> {

                // Đóng và xoá connection hiện tại
                try {
                    curConnect?.close()
                } catch (_: Exception) {} finally {
                    curConnect = null
                }

                pendingConnectResult?.success(false)
                toast("Kết nối ${type ?: "UNKNOWN"} thất bại hoặc bị gián đoạn")

                pendingConnectResult = null
                pendingConnectType = null
            }
            POSConnect.SEND_FAIL -> {
                toast("SEND_FAIL")
            }
            POSConnect.USB_DETACHED -> {
                try {
                    curConnect?.close()
                } catch (_: Exception) {} finally {
                    curConnect = null
                }
                toast("USB bị ngắt kết nối")
            }
            POSConnect.USB_ATTACHED -> {
                toast("USB được gắn")
            }
        }
    }

    private fun toast(str: String) {
        Toast.makeText(mContext, str, Toast.LENGTH_SHORT).show()
    }

    fun connectUSB(pathName: String) {
        try {
            // 1️⃣ Đánh dấu loại connect đang chờ
            pendingConnectType = "USB"
            pendingConnectResult = null

            // 2️⃣ Đóng sạch connection cũ
            try {
                curConnect?.close()
            } catch (_: Exception) {} finally {
                curConnect = null
            }

            // 3️⃣ Tạo device mới
            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_USB)
            curConnect = device

            // 4️⃣ Connect
            device?.connect(pathName, connectListener)
        } catch (e: Exception) {
            curConnect = null
            pendingConnectType = null
        }
    }

    private fun connectNet(ipAddress: String, result: MethodChannel.Result) {
        try {
            // 1️⃣ Đánh dấu trạng thái
            pendingConnectType = "LAN"
            pendingConnectResult = result

            // 2️⃣ Đóng sạch connection cũ
            try {
                curConnect?.close()
            } catch (_: Exception) {} finally {
                curConnect = null
            }

            // 3️⃣ Tạo device mới
            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_ETHERNET)
            curConnect = device

            // 4️⃣ Connect
            device?.connect(ipAddress, connectListener)
        } catch (e: Exception) {
            curConnect = null
            pendingConnectType = null
            pendingConnectResult?.error("CONNECT_ERROR", e.message, null)
            pendingConnectResult = null
        }
    }

    private fun getBluetoothAdapter(): BluetoothAdapter? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            (mContext?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        } else {
            @Suppress("DEPRECATION")
            BluetoothAdapter.getDefaultAdapter()
        }
    }

    private fun getBluetoothDevices(result: MethodChannel.Result) {
        try {
            val adapter = getBluetoothAdapter()
            if (adapter == null || !adapter.isEnabled) {
                result.error("BT_OFF", "Bluetooth is not enabled", null)
                return
            }
            val list = adapter.bondedDevices.map {
                mapOf(
                    "name" to (it.name ?: "Unknown"),
                    "mac" to it.address
                )
            }
            result.success(list)
        } catch (e: SecurityException) {
            result.error("BT_PERMISSION", "Missing BLUETOOTH_CONNECT permission", null)
        } catch (e: Exception) {
            result.error("BT_ERROR", e.message, null)
        }
    }

    private fun connectBt(macAddress: String, result: MethodChannel.Result) {
        try {
            // 1. Validate MAC
            if (macAddress.isEmpty()) {
                result.error("INVALID_MAC", "Mac address is empty", null)
                return
            }

            val adapter = getBluetoothAdapter()
            if (adapter == null || !adapter.isEnabled) {
                result.error("BT_OFF", "Bluetooth is not enabled", null)
                return
            }

            // 2. Bắt buộc dừng scan trước khi connect — discovery làm nhiễu kết nối BT Classic
            stopBluetoothScan()

            // 3. Lưu trạng thái pending
            pendingConnectType = "Bluetooth"
            pendingConnectResult = result

            // 4. Đóng kết nối cũ (nếu có)
            try {
                curConnect?.close()
            } catch (_: Exception) {
            } finally {
                curConnect = null
            }

            // 5. Tạo device từ SDK
            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_BLUETOOTH)

            if (device == null) {
                pendingConnectResult?.error("CREATE_DEVICE_FAIL", "Cannot create device", null)
                pendingConnectResult = null
                return
            }

            curConnect = device

            // 6. Connect
            device.connect(macAddress, connectListener)

        } catch (e: Exception) {
            e.printStackTrace()

            curConnect = null
            pendingConnectType = null

            pendingConnectResult?.error("CONNECT_ERROR", e.message, null)
            pendingConnectResult = null
        }
    }


    private fun connectMAC(macAddress: String) {
        curConnect?.close()
        curConnect = POSConnect.connectMac(macAddress, connectListener)
    }

    private fun connectSerial(port: String, boudrate: String) {
        curConnect?.close()
        curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_SERIAL)
        curConnect!!.connect("$port,$boudrate", connectListener)
    }

    private fun printBarcode(call: MethodCall, result: MethodChannel.Result) {
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

    // Function to extract size from the map
    private fun extractSize(size: Map<String, Double>?): Pair<Double, Double> {
        val width = size?.get("width") ?: 200.0
        val height = size?.get("height") ?: 30.0
        return Pair(width, height)
    }

    // Function to extract gap from the map
    private fun extractGap(gap: Map<String, Double>?): Pair<Double, Double> {
        val width = gap?.get("width") ?: 0.0
        val height = gap?.get("height") ?: 0.0
        return Pair(width, height)
    }

    private fun extractSizeImage(size: Map<String, Int>?): Pair<Int, Int> {
        val width = size?.get("width") ?: 600
        val height = size?.get("height") ?: 20
        return Pair(width, height)
    }

    private fun processBarcode(barcode: Map<String, Any>, printer: TSPLPrinter) {
        val barcodeX = barcode["x"] as? Int ?: 0
        val barcodeY = barcode["y"] as? Int ?: 30
        val barcodeType = barcode["type"] as? String ?: TSPLConst.CODE_TYPE_93
        val barcodeHeight = barcode["height"] as? Int ?: 100
        val barcodeContent = barcode["barcodeContent"] as? String ?: ""
        printer.barcode(
                barcodeX,
                barcodeY,
                barcodeType,
                barcodeHeight,
                TSPLConst.READABLE_CENTER,
                TSPLConst.ROTATION_0,
                2,
                2,
                barcodeContent
        )
    }

    private fun processText(text: Map<String, Any>, printer: TSPLPrinter) {
        val textX = text["x"] as? Int ?: 0
        val textY = text["y"] as? Int ?: 144
        val font = text["font"] as? String ?: TSPLConst.FNT_16_24
        val rotation = text["rotation"] as? Int ?: TSPLConst.ROTATION_0
        val sizeX = text["sizeX"] as? Int ?: 1
        val sizeY = text["sizeY"] as? Int ?: 1
        val textData = text["data"] as? String ?: ""

        printer.text(textX, textY, font, rotation, sizeX, sizeY, textData)
    }

    private fun printLabel(call: MethodCall, result: MethodChannel.Result) {
        try {
            val type = call.argument<String>("type")
            if (type != "TSPL") {
                result.success(false)
                return
            }
            val images: List<ByteArray>? = call.argument<List<ByteArray>>("images")
            if (images.isNullOrEmpty()) {
                result.success(false)
                return
            }

            val printer = TSPLPrinter(curConnect)

            images.forEach { imageData ->
                val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
                if (bitmap != null) {
                    val size = call.argument<Map<String, Int>>("size")
                    val (sizeWidth, sizeHeight) = extractSizeImage(size)

                    val x = call.argument<Int>("x") ?: 0
                    val y = call.argument<Int>("y") ?: 0
                    val width = 900

                    printer.sizeMm(sizeWidth.toDouble(), sizeHeight.toDouble())
                            .cls()
                            .bitmap(
                                    x,
                                    y,
                                    TSPLConst.BMP_MODE_OVERWRITE,
                                    width,
                                    bitmap,
                                    AlgorithmType.Threshold
                            )
                            .print(1)
                }
            }

            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    private val usbManager: UsbManager by lazy {
        mContext!!.getSystemService(Context.USB_SERVICE) as UsbManager
    }

    private val permissionReceiver =
            object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action != ACTION_USB_PERMISSION) return

                    val device: UsbDevice? = getUsbDeviceFromIntent(intent)
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)

                    if (granted && device != null) {
                        toast("Đã cấp quyền USB cho thiết bị")
                        tryConnectWithDelay(device, 0)
                    } else {
                        toast("Người dùng từ chối quyền USB")
                        pendingConnectResult?.success(false)
                        clearPending()
                    }
                }
            }

    // Hàm helper lấy UsbDevice an toàn (fix lỗi getParcelableExtra)
    private fun getUsbDeviceFromIntent(intent: Intent): UsbDevice? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION") intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
    }

    // Gọi hàm này trong onAttachedToEngine() — ngay sau khi register usbReceiver
    private fun registerUsbPermissionReceiver() {
        val filter = IntentFilter(ACTION_USB_PERMISSION)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) { // Android 13+
            mContext?.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            mContext?.registerReceiver(permissionReceiver, filter)
        }
    }

    // Gọi từ UsbConnectionReceiver khi USB được gắn
    fun handleUsbDeviceAttached(device: UsbDevice) {
        toast("USB được gắn: ${device.deviceName}")

        if (usbManager.hasPermission(device)) {
            // Đã có quyền → connect ngay với delay
            tryConnectWithDelay(device, 0)
        } else {
            // Tạo PendingIntent tương thích Android 12+
            val flags =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) { // Android 12+
                        PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }

            val permissionIntent =
                    PendingIntent.getBroadcast(
                            mContext!!,
                            0,
                            Intent(ACTION_USB_PERMISSION).apply {
                                setPackage(
                                        mContext!!.packageName
                                ) // Rất quan trọng trên Android 12+
                            },
                            flags
                    )

            usbManager.requestPermission(device, permissionIntent)
        }
    }

    fun handleUsbDeviceDetached() {
        try {
            curConnect?.close()
        } catch (_: Exception) {}
        curConnect = null
        toast("USB bị ngắt kết nối")
    }

    // Connect có delay + retry (rất quan trọng cho Android < 12)
    private fun tryConnectWithDelay(device: UsbDevice, attempt: Int) {
        if (attempt > 3) {
            toast("Kết nối USB thất bại sau nhiều lần thử")
            pendingConnectResult?.success(false)
            clearPending()
            return
        }

        Handler(Looper.getMainLooper())
                .postDelayed(
                        {
                            try {
                                pendingConnectType = "USB"

                                // Đóng connection cũ
                                curConnect?.close()
                                curConnect = null

                                val posDevice = POSConnect.createDevice(POSConnect.DEVICE_TYPE_USB)
                                curConnect = posDevice

                                val pathName = device.deviceName

                                if (pathName.isNullOrEmpty()) {
                                    toast("Không lấy được đường dẫn USB")
                                    clearPending()
                                    return@postDelayed
                                }

                                posDevice?.connect(pathName, connectListener)
                            } catch (e: Exception) {
                                Log.e("USB_CONNECT", "Attempt $attempt failed", e)
                                tryConnectWithDelay(device, attempt + 1)
                            }
                        },
                        if (attempt == 0) 1200L else 800L
                )
    }

    private fun clearPending() {
        pendingConnectResult = null
        pendingConnectType = null
    }

    companion object {
        private const val ACTION_USB_PERMISSION = "com.printer.printer_label.USB_PERMISSION"
    }
}
