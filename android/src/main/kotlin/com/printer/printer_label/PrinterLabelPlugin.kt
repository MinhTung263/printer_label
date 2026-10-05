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
    //
    // ConcurrentHashMap: kết nối nhiều máy in song song (VD Future.wait ở tầng Dart)
    // ghi vào các map này từ nhiều luồng cùng lúc. LinkedHashMap thường sẽ hỏng cấu
    // trúc nội bộ khi ghi đồng thời -> mất kết nối của máy khác.
    internal val connections = java.util.concurrent.ConcurrentHashMap<String, IDeviceConnection>()

    // Type label for each connection: "USB" | "LAN" | "BT"
    internal val connectionTypes = java.util.concurrent.ConcurrentHashMap<String, ConnectionType>()
    internal var isBuiltInPrinterDisabled = false

    // Tập deviceId được đánh dấu tường minh là MÁY IN TÍCH HỢP ngay khi kết nối.
    // Đây là nguồn nhận diện CHÍNH (chính xác cho mọi hãng), thay vì đoán lại
    // qua tên Bluetooth. Nhận diện theo tên chỉ còn là lớp dự phòng.
    internal val builtInDeviceIds = java.util.Collections.synchronizedSet(mutableSetOf<String>())

    // Maps stable USB id → actual device path (e.g. /dev/bus/usb/001/002)
    // Updated each time the device is attached so rawId() always has the current path.
    private val usbDevicePaths = mutableMapOf<String, String>()

    // deviceName (đường dẫn /dev/bus/usb/...) của các máy đang xếp hàng / đang có
    // dialog xin quyền USB CHỜ người dùng phản hồi.
    //
    // `handleUsbDeviceAttached` (broadcast ATTACHED lúc cắm dây) và `connectUsb`
    // (Dart gọi khi bấm in) đều có thể tự `requestPermission()` độc lập cho CÙNG
    // deviceId nếu cả hai chạy gần nhau — đúng kịch bản "cắm USB lần đầu rồi bấm in
    // ngay". Android xử lý 2 lời gọi `requestPermission()` chồng nhau bằng cách
    // hiện dialog nhiều lần/che nhau, mỗi lần dialog che màn hình app đều tính là
    // app mất foreground -> quan sát được "Application backgrounded" 2 lần trong
    // log, và ngay sau đó driver USB bị hệ điều hành đóng (`UsbDeviceConnectionJNI
    // close`) — kết nối tạo SAU đó dựng trên một USB session vừa bị xáo trộn, nên
    // gói đầu tiên gửi luôn thất bại dù đã retry nhiều lần (retry không cứu được vì
    // đây không phải "chưa kịp sẵn sàng" mà là session vừa bị hệ thống can thiệp).
    private val pendingPermissionRequests =
        java.util.Collections.synchronizedSet(mutableSetOf<String>())

    // Pending connect state — keyed by deviceId so parallel connects don't clash
    // xử lý trường hợp người dùng connect từ 2 máy in ble cùng lúc
    // thay vì chỉ chờ 1 result, ta chờ nhiều result trong cùng 1 tiến trình kết nối
    // để không phá vỡ tiến trình connect đang chạy
    internal data class PendingConnect(
        val results: MutableList<Result>,
        val type: ConnectionType,
        val deviceId: String
    ) {
        constructor(result: Result, type: ConnectionType, deviceId: String) :
            this(java.util.Collections.synchronizedList(mutableListOf(result)), type, deviceId)

        /** Trả [value] cho mọi lệnh đang chờ, đảm bảo mỗi result chỉ gọi một lần. */
        fun complete(value: Boolean) {
            synchronized(results) {
                results.forEach { runCatching { it.success(value) } }
                results.clear()
            }
        }
    }

    internal val pendingConnects =
        java.util.concurrent.ConcurrentHashMap<String, PendingConnect>()

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
        synchronized(Companion) { if (usbOwner == null) usbOwner = this }
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
        synchronized(Companion) { if (usbOwner === this) usbOwner = null }
    }

    /**
     * Plugin có thể bị tạo NHIỀU instance trong cùng process: mỗi `FlutterEngine` tự
     * đăng ký lại mọi plugin, VD `dual_screen_view` dựng engine riêng cho màn hình phụ.
     * Nếu instance nào cũng tự kết nối khi cắm USB / khởi động, thì mỗi máy in bị xin
     * quyền nhiều lần (popup lặp lại) và 2 instance cùng mở rồi đóng kết nối của nhau
     * trên cùng một máy in (in chập chờn). Chỉ MỘT instance ("owner") được tự kết nối;
     * instance khác chỉ kết nối khi chính Dart của nó gọi `connectUsb`.
     *
     * Owner = instance có Dart nghe `usbDeviceStream` GẦN NHẤT (xem [takeUsbOwnership]),
     * KHÔNG phải instance đăng ký đầu tiên: khi app được tích "Luôn mở ... khi kết nối",
     * cắm máy in vào là Android mở `MainActivity` bằng intent USB_DEVICE_ATTACHED — nếu
     * việc đó dựng MainActivity + FlutterEngine MỚI thì UI đang hiện thuộc engine mới.
     * Giữ owner là engine cũ thì sự kiện "USB connected" bắn vào stream của engine cũ,
     * engine mới không nhận được -> không hiện màn tạo máy in.
     */
    private val isUsbOwner: Boolean get() = usbOwner === this

    private fun takeUsbOwnership() {
        val previous = synchronized(Companion) {
            usbOwner.also { usbOwner = this }
        }
        if (previous != null && previous !== this) previous.releaseUsbConnections()
    }

    /** Nhả kết nối USB khi instance khác thành owner, tránh 2 instance cùng giữ 1 máy in. */
    private fun releaseUsbConnections() {
        connectionTypes.filterValues { it == ConnectionType.USB }.keys.forEach { id ->
            runCatching { connections[id]?.close() }
            connections.remove(id)
            connectionTypes.remove(id)
            pendingConnects.remove(id)?.complete(false)
        }
        permissionQueue.clear()
        pendingPermissionRequests.clear()
        permissionWaiters.clear()
        permissionInFlight = null
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

    /// Trạng thái báo về Dart cho checkConnect / check_printer_status.
    ///
    /// KHÁC với [isConnectionActive]: hàm kia hỏi "socket có đang mở không" (dùng để
    /// quyết định có cần mở lại), còn hàm này hỏi "có in được không". Với máy in LAN dùng
    /// chung, socket được NHẢ sau khi in xong nên `isConnect` = false là chuyện bình
    /// thường — nếu lấy nó trả lời checkConnect thì máy in vừa in xong sẽ hiện offline và
    /// Dart chặn không cho in nữa.
    internal fun isPrinterAvailable(deviceId: String): Boolean {
        if (isConnectionActive(deviceId)) return true
        return registeredLanPrinters.contains(rawId(deviceId))
    }

    /// Danh sách deviceId để báo trạng thái: kết nối đang mở + máy in LAN đã ghép nối
    /// nhưng đang nhả socket.
    internal fun statusKeys(): Set<String> =
        connections.keys + registeredLanPrinters.map { "LAN:$it" }

    internal fun getConn(call: MethodCall): IDeviceConnection? {
        val deviceId = call.argument<String>("device_id")

        if (!deviceId.isNullOrEmpty()) {
            val conn = connections[deviceId]
            if (conn != null && isConnectionActive(deviceId)) return conn
            
            // Thử khớp khóa phụ (không có tiền tố hoặc tự thêm tiền tố LAN/BT).
            //
            // LUÔN kiểm tra ĐÚNG khóa vừa khớp. Trước đây `conn2` lấy từ một trong ba khóa
            // nhưng chỉ hỏi `isConnectionActive(altKey)` — SAI KHÓA: với deviceId="BT:AA:BB"
            // thì altKey="AA:BB" (không tồn tại) nên trả false, bỏ qua đúng máy app yêu cầu
            // rồi rơi xuống fallback bên dưới và gửi sang MÁY KHÁC.
            val altKey = if (deviceId.contains(":")) deviceId.substringAfter(":") else deviceId
            for (key in listOf(altKey, "LAN:$deviceId", "BT:$deviceId")) {
                if (connections.containsKey(key) && isConnectionActive(key)) return connections[key]
            }

            // App ĐÃ chỉ định máy in cụ thể mà không khớp -> trả null, KHÔNG rơi xuống
            // fallback "máy đang kết nối đầu tiên".
            //
            // Fallback đó gửi lệnh sang máy KHÁC với máy app yêu cầu. Với mở két hậu quả rất
            // khó thấy: `connections` là ConcurrentHashMap (thứ tự theo hash, không theo thứ
            // tự kết nối) nên lệnh ESC p có thể bay sang máy không có két -> KÉT KHÔNG MỞ,
            // mà app vẫn nhận success. Đổi thứ tự kết nối lại thành mở được — đúng hiện
            // tượng "phải kết nối máy có két trước mới mở được".
            Log.w("PRINTER_LOG", "getConn: khong khop deviceId='$deviceId' " +
                "(dang co: ${connections.keys}) -> tra ve null")
            return null
        }

        val activeKey = connections.keys.firstOrNull { isConnectionActive(it) }
        return if (activeKey != null) connections[activeKey] else null
    }



    internal fun resolveConnectionsForPrint(call: MethodCall): List<IDeviceConnection> {
        val deviceId = call.argument<String>("device_id")
        val targets = mutableListOf<IDeviceConnection>()

        // 1. Máy in tích hợp CHỈ được in khi được chọn tường minh bằng device_id == "BUILT_IN".
        //    Trước đây built-in luôn tự động được thêm vào mọi lệnh in nên nó luôn tự in ra;
        //    nay chỉ kết nối và thêm nó khi người dùng chủ động chỉ định.
        if (deviceId == "BUILT_IN") {
            if (isBuiltInPrinter() && !isBuiltInPrinterDisabled) {
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
            // device_id là sentinel built-in — không tiếp tục xử lý như một khóa kết nối thường.
            return targets
        }

        // 2. Thêm thiết bị được chỉ định cụ thể qua deviceId (nếu có)
        if (!deviceId.isNullOrEmpty()) {
            var specificConn = connections[deviceId]
            if (specificConn == null || !isConnectionActive(deviceId)) {
                // LUÔN kiểm tra ĐÚNG khóa vừa khớp — xem getConn để biết vì sao việc hỏi
                // nhầm `isConnectionActive(altKey)` làm lệnh (nhất là MỞ KÉT) bay sang máy khác.
                val altKey = if (deviceId.contains(":")) deviceId.substringAfter(":") else deviceId
                for (key in listOf(altKey, "LAN:$deviceId", "BT:$deviceId")) {
                    if (connections.containsKey(key) && isConnectionActive(key)) {
                        specificConn = connections[key]
                        break
                    }
                }
            }
            // Máy in LAN đã ghép nối nhưng socket đã nhả sau lần in trước → mở lại.
            // Không có bước này thì mọi lần in sau lần đầu đều "không tìm thấy máy in".
            //
            // CHỈ làm khi đang bật chế độ nhả socket. Khi tắt (mặc định trên Android), SDK
            // giữ socket sẵn: gọi ensureLanConnectedSync ở đây sẽ tạo device MỚI đè lên
            // device đang dùng tốt -> SDK báo CONNECT_INTERRUPT ("kết nối gián đoạn") và
            // job in mất kết nối giữa đường.
            if (releaseLanSocketAfterPrint && (specificConn == null || !specificConn.isConnect)) {
                val ip = deviceId.substringAfter("LAN:", deviceId.substringAfter(':', deviceId))
                if (registeredLanPrinters.contains(ip)) {
                    specificConn = ensureLanConnectedSync(ip)
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
            connections.entries.forEach { (key, conn) ->
                if (isConnectionActive(key) && (!isBuiltInPrinter() || !bluetoothManager.isConnectionToBuiltInPrinter(conn))) {
                    if (!targets.contains(conn)) {
                        targets.add(conn)
                    }
                }
            }
            // Máy in LAN đã ghép nối nhưng đang nhả socket cũng phải được in, nếu không
            // lệnh in không deviceId sẽ bỏ qua chúng sau lần in đầu. Chỉ khi bật chế độ nhả
            // socket — xem lý do ở nhánh có deviceId bên trên.
            if (releaseLanSocketAfterPrint) {
                registeredLanPrinters.forEach { ip ->
                    if (!isConnectionActive("LAN:$ip")) {
                        ensureLanConnectedSync(ip)?.let { if (!targets.contains(it)) targets.add(it) }
                    }
                }
            }
        }

        return targets
    }

    /** Build a per-device IConnectListener so parallel connects don't race. */
    /**
     * [owner]: kết nối mà listener này thuộc về. Khi truyền vào, các sự kiện của một
     * kết nối CŨ (đã bị thay bằng kết nối mới cùng deviceId) bị bỏ qua.
     *
     * Lúc kết nối lại USB, `tryConnectWithDelay` `close()` kết nối cũ rồi gán kết nối
     * mới vào `connections[deviceId]`. Callback CONNECT_INTERRUPT/USB_DETACHED của kết
     * nối cũ tới SAU đó và trước đây xoá nhầm `connections`/`pendingConnects` của kết
     * nối MỚI -> CONNECT_SUCCESS của kết nối mới không còn pending nên không phát sự
     * kiện USB connected, app không hiện màn tạo máy in (VD xoá máy in rồi cắm lại).
     */
    internal fun makeConnectListener(
        deviceId: String,
        owner: (() -> IDeviceConnection?)? = null
    ): IConnectListener =
        IConnectListener { code, _, _ ->
            val isBuiltIn = isBuiltInPrinter()
            val ownerConn = owner?.invoke()
            if (ownerConn != null && connections[deviceId] !== ownerConn) {
                Log.d("USB_CONNECT", "Bỏ qua sự kiện $code của kết nối cũ [$deviceId]")
                return@IConnectListener
            }

            when (code) {
                POSConnect.CONNECT_SUCCESS -> {
                    // remove() nguyên tử ngay từ đầu: đọc rồi remove ở cuối là hai bước
                    // rời nhau, timeout handler có thể xen vào giữa và đóng kết nối này.
                    val pending = pendingConnects.remove(deviceId)
                    // Ghi nhớ máy in LAN CHỈ khi đã kết nối được thật, để lần in sau tự mở
                    // lại socket đã nhả (xem ensureLanConnectedSync).
                    if (connectionTypes[deviceId] == ConnectionType.LAN) {
                        registeredLanPrinters.add(rawId(deviceId))
                    }
                    if (!isBuiltIn) {
                        toast("Kết nối ${pending?.type ?: deviceId} thành công!")
                    }
                    // Không chỉ dựa vào `pending`: pending có thể đã bị lấy mất (kết nối
                    // song song, timeout...) nhưng kết nối USB này vẫn thành công thật.
                    val isUsb = pending?.type == ConnectionType.USB ||
                        connectionTypes[deviceId] == ConnectionType.USB
                    if (isUsb) emitUsbEvent(deviceId, true)

                    if (isUsb) {
                        // USB: SDK báo CONNECT_SUCCESS đôi khi TRƯỚC KHI driver thực sự
                        // sẵn sàng nhận ghi (lần in đầu ngay sau connect hay bị "sendSync
                        // trả -1 tại byte 0" — xem PrinterThermal.sendAllSync). Callback
                        // này chạy trên MAIN thread (Toast.show() ở trên yêu cầu main
                        // thread), nên KHÔNG được Thread.sleep ở đây trực tiếp -> chuyển
                        // việc "chờ rồi xác nhận" sang thread nền, chỉ complete(true) cho
                        // Dart sau khi đã thấy ghi thử thành công (hoặc hết thời gian chờ,
                        // để không kẹt mãi nếu máy thật sự có vấn đề khác).
                        val conn = connections[deviceId]
                        kotlin.concurrent.thread {
                            var ready = false
                            if (conn != null) {
                                repeat(5) { i ->
                                    if (ready) return@repeat
                                    if (i > 0) Thread.sleep(150L * i)
                                    ready = runCatching { conn.sendSync(byteArrayOf(0x00)) > 0 }
                                        .getOrDefault(false)
                                }
                            }
                            if (!ready) {
                                Log.w("USB_CONNECT", "USB chưa xác nhận sẵn sàng ghi sau kết nối, vẫn báo thành công")
                            }
                            pending?.complete(true)
                        }
                    } else {
                        pending?.complete(true)
                    }
                }

                POSConnect.CONNECT_FAIL, POSConnect.CONNECT_INTERRUPT -> {
                    val pending = pendingConnects.remove(deviceId)
                    runCatching { connections[deviceId]?.close() }
                    connections.remove(deviceId)
                    connectionTypes.remove(deviceId)
                    pending?.complete(false)
                    if (!isBuiltIn) {
                        toast("Kết nối ${pending?.type ?: deviceId} thất bại hoặc bị gián đoạn")
                    }
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
            if (deviceId == "BUILT_IN") {
                val builtInEntry = connections.entries.firstOrNull { 
                    bluetoothManager.isConnectionToBuiltInPrinter(it.value) 
                }
                if (builtInEntry != null) {
                    builtInEntry.value.close()
                    connections.remove(builtInEntry.key)
                    connectionTypes.remove(builtInEntry.key)
                    builtInDeviceIds.remove(builtInEntry.key)
                }
                isBuiltInPrinterDisabled = true
                result.success(true)
                return
            }
            connections[deviceId]?.close()
            connections.remove(deviceId)
            connectionTypes.remove(deviceId)
            builtInDeviceIds.remove(deviceId)
            // Người dùng chủ động ngắt → thôi ghi nhớ, không tự mở lại ở lần in sau.
            registeredLanPrinters.remove(rawId(deviceId))
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
            builtInDeviceIds.clear()
            registeredLanPrinters.clear()
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

    // Serial đã đọc được, theo đường dẫn thiết bị (/dev/bus/usb/...). Từ Android 10,
    // `serialNumber` ném SecurityException khi app CHƯA có quyền USB (và cả lúc thiết
    // bị vừa rút ra), nên nếu không nhớ lại thì id của cùng một máy in sẽ đổi từ
    // `USB:v_p` (trước khi cấp quyền / lúc DETACHED) sang `USB:v_p_s<serial>` (sau khi cấp).
    private val usbSerialByPath = java.util.concurrent.ConcurrentHashMap<String, String>()

    private fun usbModelId(device: UsbDevice): String =
        "USB:v${device.vendorId}_p${device.productId}"

    private fun stableUsbId(device: UsbDevice): String {
        val serial = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1)
            runCatching { device.serialNumber }.getOrNull() else null)
            ?.takeIf { it.isNotBlank() }
            ?.also { usbSerialByPath[device.deviceName] = it }
            ?: usbSerialByPath[device.deviceName]
        return if (!serial.isNullOrBlank()) "${usbModelId(device)}_s$serial"
        else usbModelId(device)
    }

    /**
     * [deviceId] đã lưu có thể thuộc về [device] không? Khớp chính xác, hoặc — khi
     * chưa có quyền nên chưa đọc được serial — cùng vendor/product id.
     */
    private fun usbMayMatch(device: UsbDevice, deviceId: String): Boolean {
        val id = stableUsbId(device)
        if (id == deviceId) return true
        val model = usbModelId(device)
        return id == model && (deviceId == model || deviceId.startsWith("${model}_s"))
    }

    internal fun scheduleConnectTimeout(deviceId: String, timeoutMs: Long = CONNECT_TIMEOUT_MS) {
        Handler(Looper.getMainLooper()).postDelayed({
            if (isDetached) return@postDelayed

            // remove() nguyên tử: chỉ trả về non-null nếu timeout thật sự thắng cuộc đua
            // với IConnectListener. Trước đây containsKey() rồi remove() là hai bước rời
            // nhau, nên CONNECT_SUCCESS xen vào giữa sẽ bị timeout đóng mất kết nối vừa
            // thành công — lỗi này lộ ra khi kết nối nhiều máy in song song.
            val pending = pendingConnects.remove(deviceId) ?: return@postDelayed

            runCatching { connections[deviceId]?.close() }
            connections.remove(deviceId)
            connectionTypes.remove(deviceId)
            pending.complete(false)

            if (!isBuiltInPrinter()) {
                toast("Kết nối $deviceId hết thời gian chờ")
            }
        }, timeoutMs)
    }

    // ─── Máy in LAN dùng chung nhiều thiết bị ────────────────────────────────
    // Máy in nhiệt LAN hầu hết chỉ nhận 1 kết nối TCP trên port 9100. Giữ socket thường
    // trực làm điện thoại thứ 2 không kết nối được. Ta ghi nhớ IP đã ghép nối rồi NHẢ
    // socket sau khi in, và mở lại ngay trước mỗi lần in (xem `ensureLanConnected`).
    internal val registeredLanPrinters = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    /// Nhả socket LAN sau khi in xong để nhiều thiết bị dùng chung được một máy in.
    ///
    /// Máy in chỉ cho MỘT socket in tại một thời điểm (đã kiểm chứng: nó accept nhiều socket
    /// nhưng đóng ngay các socket phụ khi có byte tới). Giữ socket thường trực làm thiết bị
    /// khác gửi được lệnh nhưng job bị máy in XẾP HÀNG, chỉ in khi app này tắt.
    ///
    /// Việc này CHỈ an toàn vì đường in LAN đã chuyển sang `sendAllSync` (đồng bộ, trả về số
    /// byte thật) — xem PrinterThermal.printImageESC. Trước đây LAN dùng
    /// `POSPrinter.printBitmap` BẤT ĐỒNG BỘ: nó chỉ xếp lệnh vào hàng đợi nội bộ rồi return,
    /// nên nhả socket lúc đó là đóng kết nối khi SDK chưa gửi được gì -> KHÔNG IN RA.
    internal var releaseLanSocketAfterPrint = true

    private val lanRetryBaseDelayMs = 400L
    private val lanMaxAttempts = 4

    /// Hết giờ (mạng yếu/mất, máy in tắt) chỉ thử lại 1 lần: mỗi lượt đã tự gửi SYN nhiều
    /// lần trong LanSocketConnection.CONNECT_TIMEOUT_MS, thử tiếp chỉ làm người dùng chờ
    /// lâu hơn. "Máy in bận" (từ chối/reset) mới đáng thử đủ lanMaxAttempts.
    private val lanMaxTimeoutAttempts = 2

    /// Lý do kết nối LAN thất bại gần nhất theo IP — để báo lỗi đúng nguyên nhân cho Dart.
    internal val lanLastFailure = java.util.concurrent.ConcurrentHashMap<String, LanSocketConnection.Failure>()

    /// Thông báo lỗi dễ hiểu theo lý do thất bại gần nhất của [ip].
    internal fun lanFailureMessage(ip: String): String = when (lanLastFailure[ip]) {
        LanSocketConnection.Failure.TIMEOUT ->
            "LAN_TIMEOUT: Không tới được máy in $ip (mạng yếu/mất hoặc máy in đang tắt)"
        LanSocketConnection.Failure.BUSY ->
            "LAN_BUSY: Máy in $ip đang bận (thiết bị khác đang in), thử lại sau ít giây"
        LanSocketConnection.Failure.UNREACHABLE ->
            "LAN_UNREACHABLE: Thiết bị không cùng mạng với máy in $ip (kiểm tra Wi-Fi)"
        LanSocketConnection.Failure.SEND_FAILED ->
            "LAN_SEND_FAILED: Mất kết nối tới máy in $ip khi đang gửi"
        else -> "No connected printer found"
    }

    /// Mở lại kết nối LAN tới [ipAddress] và CHỜ kết quả (đang ở luồng nền khi in).
    /// Thử lại có giãn nhịp: máy in đang in cho thiết bị khác sẽ từ chối kết nối, chờ
    /// một nhịp rồi thử lại thay vì báo lỗi ngay như thể máy in offline.
    internal fun ensureLanConnectedSync(ipAddress: String): IDeviceConnection? {
        val deviceId = "LAN:$ipAddress"
        if (isConnectionActive(deviceId)) return connections[deviceId]

        // Đang có lệnh connect() của người dùng chờ trên CÙNG deviceId (vừa bấm nút
        // Connect): KHÔNG được tự mở kết nối mới ở đây. Hai đường cùng ghi vào
        // connections[deviceId] sẽ đạp nhau — ta close()/remove() mất device mà connectNet
        // đang đợi, IConnectListener của nó không bao giờ được gọi -> báo "connect time
        // out"; rồi scheduleConnectTimeout đóng luôn socket giữa lúc đang in -> KHÔNG IN RA.
        // Chờ lệnh của người dùng xong rồi dùng kết quả đó.
        val pendingDeadline = System.currentTimeMillis() + LAN_CONNECT_TIMEOUT_MS
        while (pendingConnects.containsKey(deviceId) && System.currentTimeMillis() < pendingDeadline) {
            runCatching { Thread.sleep(50) }
            if (isConnectionActive(deviceId)) return connections[deviceId]
        }

        var timeouts = 0
        for (attempt in 1..lanMaxAttempts) {
            // Người dùng bấm Connect xen vào giữa các lần thử → nhường cho lệnh đó.
            if (pendingConnects.containsKey(deviceId)) return null

            // Socket tự quản thay cho cổng Ethernet của SDK (SDK chỉ chờ 1s, bóp buffer
            // 512 byte, ghi không timeout) — xem LanSocketConnection.
            val device = LanSocketConnection(mContext)
            // Chỉ đóng device CŨ sau khi đã tạo được device mới, và chỉ đóng đúng cái ta
            // đang thay thế — tránh đóng kết nối mà luồng khác vừa mở xong.
            val previous = connections.put(deviceId, device)
            if (previous != null && previous !== device) runCatching { previous.close() }
            connectionTypes[deviceId] = ConnectionType.LAN
            // connectSync: chặn ngay luồng nền này, KHÔNG cần main thread báo kết quả (bản
            // cũ chờ listener của SDK — vốn được post lên main — nên gọi từ main là treo tới
            // hết timeout). Tự giới hạn bởi LanSocketConnection.CONNECT_TIMEOUT_MS.
            val connected = runCatching {
                device.connectSync(ipAddress, IConnectListener { _, _, _ -> })
            }.getOrDefault(false)
            if (connected && device.isConnect) {
                lanLastFailure.remove(ipAddress)
                return device
            }

            val failure = device.lastFailure ?: LanSocketConnection.Failure.TIMEOUT
            lanLastFailure[ipAddress] = failure
            runCatching { device.close() }
            // remove() có điều kiện: nếu luồng khác đã thay device khác vào thì giữ nguyên.
            connections.remove(deviceId, device)

            // Không cùng mạng / Wi-Fi rớt: thử lại vô ích, báo ngay.
            if (failure == LanSocketConnection.Failure.UNREACHABLE) break
            if (failure == LanSocketConnection.Failure.TIMEOUT && ++timeouts >= lanMaxTimeoutAttempts) break

            if (attempt < lanMaxAttempts) {
                // Giãn dần 0.4s, 0.8s, 1.6s (±25% ngẫu nhiên để hai thiết bị cùng chờ một
                // máy in không thử lại đúng cùng nhịp) — nhường socket cho thiết bị đang in.
                val base = lanRetryBaseDelayMs shl (attempt - 1)
                val delay = (base * (0.75 + Math.random() * 0.5)).toLong()
                Log.i("PRINTER_LOG", "Máy in $ipAddress chưa kết nối được ($failure), thử lại sau ${delay}ms (lần ${attempt + 1}/$lanMaxAttempts)")
                runCatching { Thread.sleep(delay) }
            }
        }
        Log.w("PRINTER_LOG", "Không kết nối được máy in LAN $ipAddress: ${lanFailureMessage(ipAddress)}")
        return null
    }

    /// Số job đang dùng socket của mỗi máy in LAN (theo deviceId).
    ///
    /// In nhiều bản/nhiều máy CÙNG LÚC thì nhiều job cùng nhắm một IP. Nếu job nào xong
    /// cũng đóng socket ngay thì các job còn lại đang gửi dở bị cắt kết nối, phải mở lại
    /// và đụng đúng socket vừa bị chiếm -> "Máy in đang bận, thử lại sau ..." rồi hai dòng
    /// "Đã nhả socket" cho cùng một IP. Chỉ nhả khi job CUỐI CÙNG trên IP đó kết thúc.
    private val lanJobCount = java.util.concurrent.ConcurrentHashMap<String, java.util.concurrent.atomic.AtomicInteger>()

    /// Đánh dấu bắt đầu một job LAN trên [conn] (nếu đó là kết nối LAN).
    internal fun retainLanSocket(conn: IDeviceConnection) {
        if (!releaseLanSocketAfterPrint) return
        val entry = connections.entries.firstOrNull { it.value === conn } ?: return
        if (connectionTypes[entry.key] != ConnectionType.LAN) return
        lanJobCount.getOrPut(entry.key) { java.util.concurrent.atomic.AtomicInteger(0) }
            .incrementAndGet()
    }

    /// Nhả socket LAN sau khi in xong. Giữ IP trong [registeredLanPrinters] để
    /// checkConnect vẫn báo còn ghép nối và lần in sau tự mở lại.
    ///
    /// [closeWhenIdle] = false khi đây mới là một lô GIỮA của lượt in dài: vẫn trả bộ
    /// đếm job (không trả sẽ rò, socket không bao giờ đóng được nữa) nhưng giữ socket
    /// cho lô kế tiếp dùng lại. Xem chú thích ở runPrintJob.
    internal fun releaseLanSocket(conn: IDeviceConnection, closeWhenIdle: Boolean = true) {
        if (!releaseLanSocketAfterPrint) return
        val entry = connections.entries.firstOrNull { it.value === conn } ?: return
        if (connectionTypes[entry.key] != ConnectionType.LAN) return

        // Còn job khác đang dùng socket này -> chưa được đóng.
        val counter = lanJobCount[entry.key]
        if (counter != null && counter.decrementAndGet() > 0) {
            Log.i("PRINTER_LOG", "Giu socket ${entry.key}: con ${counter.get()} job dang in")
            return
        }

        // Lượt in còn lô tiếp theo -> giữ socket, đừng để lô sau phải mở lại.
        // Vẫn hẹn một mốc DỰ PHÒNG dài: nếu lô cuối không bao giờ tới (Dart lỗi giữa
        // chừng, app bị kill, người dùng thoát màn hình) thì socket phải tự nhả, nếu
        // không máy khác sẽ vĩnh viễn không kết nối được.
        if (!closeWhenIdle) {
            Log.i("PRINTER_LOG", "Giu socket ${entry.key}: con lo tem tiep theo")
            scheduleLanWatchdog(entry.key)
            return
        }

        // Hoãn một nhịp ngắn rồi mới đóng. In nhiều bản (quantity > 1) là NHIỀU lời gọi
        // runPrintJob liên tiếp, nên bộ đếm về 0 ở khoảng trống GIỮA các bản; đóng ngay tại
        // đó buộc bản kế tiếp mở lại socket và có thể đụng socket chưa kịp giải phóng hẳn
        // -> "Máy in đang bận, thử lại sau ...". Nếu trong nhịp chờ có job mới (bộ đếm > 0)
        // thì giữ nguyên socket.
        val key = entry.key
        cancelLanWatchdog(key)
        Handler(Looper.getMainLooper()).postDelayed({
            val c = lanJobCount[key]
            if (c != null && c.get() > 0) return@postDelayed
            lanJobCount.remove(key)
            val current = connections[key] ?: return@postDelayed
            runCatching { current.close() }
            connections.remove(key)
            Log.i("PRINTER_LOG", "Đã nhả socket $key để thiết bị khác dùng")
        }, LAN_IDLE_CLOSE_DELAY_MS)
    }

    /// Chờ trước khi đóng socket LAN rảnh — đủ để bản in kế tiếp tái dùng socket đang mở.
    private val LAN_IDLE_CLOSE_DELAY_MS = 800L

    /// Mốc dự phòng đóng socket khi lô tem CUỐI không bao giờ tới. Phải đủ dài để render
    /// lô kế tiếp (lô 10 ảnh, máy yếu) không bị cắt ngang.
    private val LAN_WATCHDOG_CLOSE_DELAY_MS = 15_000L

    private val lanWatchdogs = java.util.concurrent.ConcurrentHashMap<String, Runnable>()

    /// Hẹn giờ đóng socket phòng khi lượt in đứt giữa chừng. Mỗi lô mới gọi lại sẽ dời
    /// mốc ra xa, nên lượt in đang chạy bình thường không bao giờ chạm tới.
    private fun scheduleLanWatchdog(key: String) {
        cancelLanWatchdog(key)
        val handler = Handler(Looper.getMainLooper())
        val task = Runnable {
            lanWatchdogs.remove(key)
            if (isDetached) return@Runnable
            val c = lanJobCount[key]
            if (c != null && c.get() > 0) return@Runnable
            lanJobCount.remove(key)
            val current = connections[key] ?: return@Runnable
            runCatching { current.close() }
            connections.remove(key)
            Log.i("PRINTER_LOG", "Đã nhả socket $key (quá hạn chờ lô tem cuối)")
        }
        lanWatchdogs[key] = task
        handler.postDelayed(task, LAN_WATCHDOG_CLOSE_DELAY_MS)
    }

    private fun cancelLanWatchdog(key: String) {
        lanWatchdogs.remove(key)?.let { Handler(Looper.getMainLooper()).removeCallbacks(it) }
    }

    internal fun connectNet(ipAddress: String, result: Result) {
        val deviceId = "LAN:$ipAddress"
        // CHỈ ghi nhớ SAU khi kết nối thành công (trong makeConnectListener). Ghi nhớ ngay
        // ở đây sẽ làm guard "đã ghép nối" bên dưới trả về true cho lần bấm Connect ĐẦU
        // TIÊN tới một IP chưa từng kết nối được — báo thành công giả cho máy in không tồn tại.
        try {
            // Đã kết nối sẵn thì trả về ngay. Nếu không, đoạn close() bên dưới sẽ đóng
            // kết nối đang dùng được — khi nhiều máy connect song song, máy này có thể
            // bị ngắt giữa lúc máy khác vừa kết nối xong.
            if (isConnectionActive(deviceId)) {
                result.success(true)
                return
            }

            // Máy in LAN dùng chung: socket đã được NHẢ sau lần in trước nhưng máy in vẫn
            // đang ghép nối. Bấm Connect lúc này KHÔNG cần mở socket mới — mở ra rồi để
            // đó sẽ chiếm socket của thiết bị khác, và nếu người dùng in ngay sau đó thì
            // scheduleConnectTimeout có thể đóng socket giữa lúc đang in (-> không in ra).
            // Lần in tới ensureLanConnectedSync sẽ tự mở đúng lúc cần.
            if (releaseLanSocketAfterPrint && registeredLanPrinters.contains(ipAddress)) {
                result.success(true)
                return
            }

            // Connect trùng deviceId: gộp result vào lệnh đang chờ để cả hai cùng nhận
            // kết quả thật, thay vì ghi đè (làm mất result của lệnh trước -> Future treo
            // tới timeout, rồi timeout handler đóng luôn kết nối vừa thành công).
            val existing = pendingConnects.putIfAbsent(
                deviceId,
                PendingConnect(result, ConnectionType.LAN, deviceId)
            )
            if (existing != null) {
                synchronized(existing.results) { existing.results.add(result) }
                return
            }

            // Socket tự quản thay cho cổng Ethernet của SDK — xem LanSocketConnection.
            val device = LanSocketConnection(mContext)
            // Đóng device CŨ chỉ sau khi đã có device mới, và chỉ đúng cái đang bị thay —
            // close() trước khi tạo sẽ đóng cả kết nối mà luồng in khác vừa mở xong.
            val previousDevice = connections.put(deviceId, device)
            if (previousDevice != null && previousDevice !== device) {
                runCatching { previousDevice.close() }
            }
            connectionTypes[deviceId] = ConnectionType.LAN
            device.connect(ipAddress, makeConnectListener(deviceId))
            // Lớp chờ ngoài PHẢI dài hơn timeout connect bên trong, nếu không nó đóng socket
            // khi đang bắt tay dở.
            scheduleConnectTimeout(deviceId, LAN_CONNECT_TIMEOUT_MS)
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

    /// Chủ động kết nối lại USB theo [deviceId] đã lưu (VD sau khi app bị kill/restart:
    /// `connections` trong bộ nhớ mất hết nhưng thiết bị vẫn cắm vật lý nên hệ điều hành
    /// KHÔNG bắn lại broadcast ATTACHED — không có gì tự kích hoạt `tryConnectWithDelay`).
    /// Quét `usbManager.deviceList` tìm thiết bị có `stableUsbId()` khớp [deviceId]; nếu
    /// thiết bị không còn cắm thì báo thất bại ngay (đúng là phải rút/cắm lại thật).
    internal fun connectUsb(deviceId: String, result: Result) {
        if (isConnectionActive(deviceId)) {
            result.success(true)
            return
        }
        val attached = usbManager.deviceList.values
        val device = attached.find { stableUsbId(it) == deviceId }
        // Không khớp chính xác: có thể máy in vẫn cắm nhưng CHƯA có quyền (VD vừa bật
        // lại nguồn) nên chưa đọc được serial -> id hiện tại thiếu `_s<serial>`. Xin quyền
        // cho các máy cùng vendor/product rồi mới biết máy nào đúng là [deviceId].
        val candidates = if (device != null) emptyList()
            else attached.filter { !usbManager.hasPermission(it) && usbMayMatch(it, deviceId) }
        if (device == null && candidates.isEmpty()) {
            result.success(false)
            return
        }

        val existing = pendingConnects.putIfAbsent(
            deviceId,
            PendingConnect(result, ConnectionType.USB, deviceId)
        )
        if (existing != null) {
            synchronized(existing.results) { existing.results.add(result) }
        }

        if (device != null) {
            if (existing != null) return
            if (usbManager.hasPermission(device)) {
                tryConnectWithDelay(device, 0)
            } else {
                requestUsbPermissionOnce(device)
            }
            return
        }
        for (candidate in candidates) {
            permissionWaiters[candidate.deviceName] = deviceId
            requestUsbPermissionOnce(candidate)
        }
    }

    /**
     * Xin quyền USB cho [device], nhưng CHỈ MỘT dialog cho mỗi máy tại một
     * thời điểm — dùng [pendingPermissionRequests] để chặn lời gọi trùng.
     *
     * `handleUsbDeviceAttached` (broadcast lúc cắm dây) và `connectUsb` (Dart gọi
     * khi bấm in) đều có thể chạy tới đây gần như đồng thời ở lần cắm USB đầu
     * tiên. Không chặn trùng thì `usbManager.requestPermission()` bị gọi 2 lần,
     * Android hiện dialog xin quyền lặp/che nhau — mỗi lần dialog che app đều
     * khiến app mất foreground ("Application backgrounded" trong log) và kéo
     * theo hệ điều hành đóng USB session đang mở (`UsbDeviceConnectionJNI
     * close`). Kết nối dựng ngay sau đó thất bại ngay ở gói đầu tiên vì session
     * USB vừa bị xáo trộn — không phải "chưa kịp sẵn sàng" nên retry gửi lại
     * không cứu được.
     *
     * Khoá theo `device.deviceName` (đường dẫn /dev/bus/usb/...), KHÔNG theo
     * [stableUsbId]: id đó đổi ngay khi được cấp quyền (đọc được serial), nên khoá
     * theo id thì lúc nhận kết quả sẽ xoá nhầm khoá, máy kẹt "đang xin quyền" mãi.
     * Ngoài ra các máy KHÁC NHAU cũng phải xin LẦN LƯỢT (xem [permissionQueue]).
     */
    private fun requestUsbPermissionOnce(device: UsbDevice) {
        if (!pendingPermissionRequests.add(device.deviceName)) return
        permissionQueue.addLast(device)
        pumpPermissionQueue()
    }

    // Hàng đợi xin quyền USB — chỉ chạy trên main thread (broadcast receiver,
    // method channel, EventChannel.onListen đều ở main thread).
    //
    // Android chỉ hiện ĐƯỢC MỘT dialog xin quyền USB tại một thời điểm: gọi
    // `requestPermission()` cho máy B khi dialog của máy A còn đang mở thì hệ
    // thống chỉ đưa activity dialog cũ lên trước, lời xin của B bị NUỐT IM LẶNG —
    // không hiện dialog, cũng không bao giờ bắn broadcast kết quả. Hậu quả cũ: sau
    // khi bật lại máy (quyền USB tạm bị xoá), auto-scan xin quyền cho mọi máy in
    // cùng lúc -> chỉ 1 dialog hiện; các máy còn lại kẹt mãi trong
    // [pendingPermissionRequests] nên kể cả bấm in (`connectUsb`) cũng không xin
    // lại được, phải rút/cắm lại dây mới hết. Vì vậy xin lần lượt: chờ kết quả
    // máy trước (đồng ý/từ chối/rút dây) rồi mới xin máy sau.
    private val permissionQueue = ArrayDeque<UsbDevice>()
    private var permissionInFlight: String? = null  // deviceName

    // deviceName của máy đang xin quyền hộ `connectUsb` -> deviceId Dart đang chờ.
    // Chỉ dùng khi chưa biết chắc máy nào là [deviceId] (xem `connectUsb`).
    private val permissionWaiters = mutableMapOf<String, String>()

    private fun pumpPermissionQueue() {
        if (permissionInFlight != null) return
        while (permissionQueue.isNotEmpty()) {
            val device = permissionQueue.removeFirst()
            val path = device.deviceName
            // Đã rút dây trong lúc xếp hàng.
            if (usbManager.deviceList.values.none { it.deviceName == path }) {
                pendingPermissionRequests.remove(path)
                continue
            }
            // Quyền đã có sẵn (VD người dùng đã tick "Luôn mở Easy Pos..." ở dialog
            // trước, hoặc hệ thống tự cấp qua intent-filter USB_DEVICE_ATTACHED).
            if (usbManager.hasPermission(device)) {
                onUsbPermissionResult(device, granted = true)
                continue
            }
            // Máy vừa cắm / vừa bật lại nguồn: chờ hệ thống tự cấp quyền cho app mặc
            // định (xem [USB_SYSTEM_GRANT_WAIT_MS]) rồi mới hiện dialog.
            val waitMs = systemGrantWaitMs(path)
            if (waitMs > 0) {
                permissionQueue.addFirst(device)
                if (!systemGrantWaitScheduled) {
                    systemGrantWaitScheduled = true
                    Handler(Looper.getMainLooper()).postDelayed({
                        systemGrantWaitScheduled = false
                        if (!isDetached) pumpPermissionQueue()
                    }, waitMs)
                }
                return
            }

            permissionInFlight = path
            permissionBatchIndex++
            val total = permissionBatchIndex + permissionQueue.size
            // Các máy in cùng model hiện dialog Y HỆT nhau ("...truy cập vào Printer-80?"),
            // bấm OK xong dialog máy sau hiện ngay trông như dialog không tắt -> đánh số.
            if (total > 1) toast("Cấp quyền máy in USB $permissionBatchIndex/$total")
            requestSystemUsbPermission(device)
            return
        }
        // Hết lượt xin quyền.
        permissionBatchIndex = 0
        val callbacks = permissionBatchCallbacks.toList()
        permissionBatchCallbacks.clear()
        callbacks.forEach { it() }
    }

    // deviceName -> thời điểm (uptimeMillis) nhận broadcast ATTACHED gần nhất.
    private val usbAttachedAt = mutableMapOf<String, Long>()
    private var systemGrantWaitScheduled = false

    /** Số ms còn phải chờ hệ thống tự cấp quyền cho máy vừa cắm tại [path], 0 = khỏi chờ. */
    private fun systemGrantWaitMs(path: String): Long {
        val attachedAt = usbAttachedAt[path] ?: return 0
        val remaining = attachedAt + USB_SYSTEM_GRANT_WAIT_MS - android.os.SystemClock.uptimeMillis()
        if (remaining <= 0) usbAttachedAt.remove(path)
        return remaining.coerceAtLeast(0)
    }

    // Số thứ tự máy đang xin quyền trong lượt hiện tại (để đánh số "2/3").
    private var permissionBatchIndex = 0

    // Chờ hàng đợi xin quyền chạy hết (xem `requestUsbPermissions`).
    private val permissionBatchCallbacks = mutableListOf<() -> Unit>()

    private fun requestSystemUsbPermission(device: UsbDevice) {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        else PendingIntent.FLAG_UPDATE_CURRENT
        // requestCode riêng cho từng máy để PendingIntent không dùng chung giữa các máy.
        val permIntent = PendingIntent.getBroadcast(
            mContext!!, device.deviceName.hashCode(),
            Intent(ACTION_USB_PERMISSION).apply { setPackage(mContext!!.packageName) },
            flags
        )
        usbManager.requestPermission(device, permIntent)
    }

    /**
     * Có tự bật popup xin quyền cho máy in USB ĐÃ CẮM SẴN lúc mở app không (mặc định có).
     *
     * Sau khi tắt/bật nguồn, Android xoá quyền USB tạm -> mở app là popup hệ thống bật
     * lên liên tiếp mà người dùng không hiểu vì sao. App host tắt cờ này để tự hiện
     * hướng dẫn (VD banner) rồi mới gọi `requestUsbPermissions` khi người dùng đồng ý.
     * Cắm máy in MỚI (broadcast ATTACHED) và `connectUsb` lúc in vẫn tự xin quyền như cũ,
     * vì lúc đó người dùng đang chủ động thao tác với máy in.
     */
    @Volatile internal var autoRequestUsbPermission = true

    private fun attachedUsbPrintersWithoutPermission(): List<UsbDevice> =
        runCatching {
            usbManager.deviceList.values.filter { isUsbPrinter(it) && !usbManager.hasPermission(it) }
        }.getOrDefault(emptyList())

    /** Máy in USB đang cắm nhưng chưa có quyền: `[{device_id, name}]`. */
    internal fun getUsbPrintersNeedingPermission(): List<Map<String, String>> =
        attachedUsbPrintersWithoutPermission().map { device ->
            mapOf(
                "device_id" to stableUsbId(device),
                "name" to (runCatching { device.productName }.getOrNull()
                    ?.takeIf { it.isNotBlank() } ?: device.deviceName)
            )
        }

    /**
     * Xin quyền LẦN LƯỢT cho mọi máy in USB đang cắm mà chưa có quyền. Trả về số máy
     * được cấp quyền sau khi người dùng trả lời hết các popup.
     */
    internal fun requestUsbPermissions(result: Result) {
        val devices = attachedUsbPrintersWithoutPermission()
        if (devices.isEmpty()) {
            result.success(0)
            return
        }
        val paths = devices.map { it.deviceName }.toSet()
        permissionBatchCallbacks.add {
            val granted = usbManager.deviceList.values.count {
                it.deviceName in paths && usbManager.hasPermission(it)
            }
            runCatching { result.success(granted) }
        }
        devices.forEach { requestUsbPermissionOnce(it) }
        // Mọi máy đều đã nằm sẵn trong hàng đợi / đang xin dở -> callback chạy khi lượt đó xong.
        pumpPermissionQueue()
    }

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_USB_PERMISSION) return
            val device: UsbDevice? = getUsbDeviceFromIntent(intent)
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            // Broadcast kết quả tới MỌI instance plugin (xem [isUsbOwner]) — chỉ xử lý
            // máy mà CHÍNH instance này đã xin, nếu không 2 instance cùng connect 1 máy.
            if (device != null && !pendingPermissionRequests.contains(device.deviceName)) return
            if (device == null && permissionInFlight == null) return
            // Dialog hiện tại đã đóng -> xin quyền cho máy kế tiếp trong hàng đợi.
            permissionInFlight = null
            Handler(Looper.getMainLooper()).post { if (!isDetached) pumpPermissionQueue() }
            if (device == null) {
                toast("Người dùng từ chối quyền USB")
                return
            }
            toast(if (granted) "Đã cấp quyền USB cho thiết bị" else "Người dùng từ chối quyền USB")
            onUsbPermissionResult(device, granted)
        }
    }

    private fun onUsbPermissionResult(device: UsbDevice, granted: Boolean) {
        pendingPermissionRequests.remove(device.deviceName)
        val waiter = permissionWaiters.remove(device.deviceName)
        // Gọi SAU khi có quyền -> id đã gồm serial thật của máy.
        val deviceId = stableUsbId(device)
        if (granted) {
            if (connections[deviceId]?.isConnect != true) tryConnectWithDelay(device, 0)
        } else {
            pendingConnects.remove(deviceId)?.complete(false)
        }
        // Máy vừa xử lý không phải máy `connectUsb` cần (cùng model, khác serial) và
        // không còn máy nào khác đang xin quyền hộ -> báo thất bại để Dart khỏi chờ mãi.
        if (waiter != null && (!granted || deviceId != waiter)) failUsbWaiterIfNoCandidate(waiter)
    }

    private fun failUsbWaiterIfNoCandidate(waiterId: String) {
        if (permissionWaiters.containsValue(waiterId)) return
        if (connections[waiterId]?.isConnect == true) return
        pendingConnects.remove(waiterId)?.complete(false)
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

    /**
     * [justPlugged] = true khi gọi từ broadcast ATTACHED (máy vừa cắm / vừa bật lại
     * nguồn), false khi quét máy đã cắm sẵn lúc mở app.
     *
     * Với máy vừa cắm, Android bắn broadcast ATTACHED TRƯỚC rồi mới cấp quyền cho app
     * được tick "Luôn mở ... khi kết nối" (UsbProfileGroupSettingsManager.deviceAttached:
     * sendBroadcast -> resolveActivity -> grantDevicePermission). Xin quyền ngay lúc nhận
     * broadcast là chen vào trước bước cấp quyền đó -> dialog hiện lại dù đã tick.
     * Vì vậy ghi lại thời điểm cắm để [pumpPermissionQueue] chờ hệ thống cấp quyền trước.
     */
    fun handleUsbDeviceAttached(device: UsbDevice, justPlugged: Boolean = false) {
        if (justPlugged) usbAttachedAt[device.deviceName] = android.os.SystemClock.uptimeMillis()
        if (!isUsbOwner) return
        val deviceId = stableUsbId(device)
        usbDevicePaths[deviceId] = device.deviceName  // update path for this plug-in event
        toast("USB được gắn: $deviceId")
        if (usbManager.hasPermission(device)) {
            tryConnectWithDelay(device, 0)
        } else {
            requestUsbPermissionOnce(device)
        }
    }

    fun handleUsbDeviceDetached(device: UsbDevice?) {
        if (device == null) return
        val path = device.deviceName
        // Lúc DETACHED không đọc được serial nữa -> lấy từ cache theo đường dẫn.
        val deviceId = stableUsbId(device)
        runCatching { connections[deviceId]?.close() }
        connections.remove(deviceId)
        connectionTypes.remove(deviceId)
        usbDevicePaths.remove(deviceId)
        usbSerialByPath.remove(path)
        usbAttachedAt.remove(path)
        // Nếu rút dây đúng lúc đang chờ dialog xin quyền / đang giữa các lần thử
        // connect, `permissionReceiver`/`tryConnectWithDelay` có thể không bao
        // giờ chạy tới bước dọn cờ tương ứng — dọn luôn ở đây để lần ATTACHED kế
        // tiếp (cắm lại) không bị `requestUsbPermissionOnce` chặn nhầm là "đang
        // xin quyền rồi" (xem comment tại hàm đó).
        pendingPermissionRequests.remove(path)
        permissionQueue.removeAll { it.deviceName == path }
        permissionWaiters.remove(path)?.let { failUsbWaiterIfNoCandidate(it) }
        if (permissionInFlight == path) {
            // Dialog của máy vừa rút thường tự đóng và vẫn bắn broadcast "từ chối";
            // nhả hàng đợi luôn ở đây phòng khi broadcast đó không tới.
            permissionInFlight = null
            pumpPermissionQueue()
        }
        pendingConnects.remove(deviceId)?.complete(false)
        emitUsbEvent(deviceId, false)
        toast("USB bị ngắt kết nối [$deviceId]")
    }

    private fun tryConnectWithDelay(device: UsbDevice, attempt: Int) {
        val deviceId = stableUsbId(device)
        usbDevicePaths[deviceId] = device.deviceName  // keep path current on each attempt
        if (attempt > 3) {
            toast("Kết nối USB thất bại sau nhiều lần thử")
            pendingConnects[deviceId]?.complete(false)
            pendingConnects.remove(deviceId)
            return
        }

        // Đăng ký `pendingConnects` NGAY tại attempt 0, TRƯỚC `postDelayed` (không phải
        // bên trong closure ở dưới, vốn chỉ chạy sau 1200ms nữa).
        //
        // Trước đây `pendingConnects` chỉ được set trong closure, để hở một cửa sổ
        // ~1200ms giữa lúc auto-scan lúc khởi động app (`scanAndConnectExistingUsbDevices`
        // -> `handleUsbDeviceAttached` -> đây) BẮT ĐẦU gọi hàm này và lúc nó thực sự
        // đăng ký pending. Nếu người dùng bấm in trong đúng cửa sổ đó, luồng in gọi
        // `connectUsb()` (Dart) thấy `pendingConnects[deviceId]` chưa tồn tại -> tự tạo
        // PendingConnect RIÊNG và tự gọi `tryConnectWithDelay` LẦN 2, độc lập với lần 1.
        // Cả hai closure sau đó đều `close()` connection của nhau khi tới lượt chạy ->
        // đúng hiện tượng "sendSync trả -1 tại byte 0" xảy ra lẫn với các dòng
        // "UsbDeviceConnectionJNI close" — vì đơn in đầu tiên đang gửi dở dang trên
        // connection mà lần connect còn lại vừa đóng.
        //
        // `putIfAbsent` với `NoOpResult`: các lần gọi tự động (auto-scan, re-attach) không
        // có `Result` thật cần trả lời; nếu đã có pending khác (VD từ `connectUsb` do
        // người dùng bấm in) thì giữ nguyên cái đó — không ghi đè.
        if (attempt == 0) {
            pendingConnects.putIfAbsent(
                deviceId,
                PendingConnect(NoOpResult, ConnectionType.USB, deviceId)
            )
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
                posDevice.connect(rawId(deviceId), makeConnectListener(deviceId) { posDevice })
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
            takeUsbOwnership()
            scanAndConnectExistingUsbDevices()
        }

        override fun onCancel(arguments: Any?) {
            usbEventSink = null
        }
    }

    private fun scanAndConnectExistingUsbDevices() {
        if (!isUsbOwner) return
        try {
            val deviceList = usbManager.deviceList
            for (device in deviceList.values) {
                if (!isUsbPrinter(device)) continue
                // Chưa có quyền + app host tự hướng dẫn (xem [autoRequestUsbPermission]).
                if (!autoRequestUsbPermission && !usbManager.hasPermission(device)) continue
                handleUsbDeviceAttached(device)
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
        Log.d(
            "USB_CONNECT",
            "emit $deviceId connected=$connected owner=$isUsbOwner sink=${usbEventSink != null}"
        )
        // Tên model máy in tự báo qua USB (VD "Printer-80") để app đặt tên mặc định dễ
        // nhận biết. Lúc rút dây thiết bị không còn trong deviceList -> không có tên.
        val name = runCatching {
            usbManager.deviceList.values.firstOrNull { stableUsbId(it) == deviceId }
                ?.productName?.trim()
        }.getOrNull()
        Handler(Looper.getMainLooper()).post {
            usbEventSink?.success(
                mapOf("device_id" to deviceId, "connected" to connected, "name" to name)
            )
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
            // Chỉ khổ 3 tem cần HOME (xem LabelPerRow.useHome). Bật cho khổ 1-2 tem sẽ
            // đẩy thừa một hàng -> in một hàng lại bỏ trắng một hàng.
            val useHome = call.argument<Boolean>("use_home") ?: false

            val targetWidthDots = sizeWidth * 8
            val targetHeightDots = sizeHeight * 8

            images.forEach { imageData ->
                val bitmap =
                    BitmapFactory.decodeByteArray(imageData, 0, imageData.size) ?: return@forEach

                // Scale bitmap to exactly targetWidthDots and targetHeightDots
                val scaledBitmap = Bitmap.createScaledBitmap(bitmap, targetWidthDots, targetHeightDots, true)

                // Bù dải trắng leftPadding của widget Dart (8px logic -> ~1.16mm sau khi
                // scale). -8 dots = -1mm đưa tem đầu về sát mép trái mà không cắt mất.
                val shiftX = -8f
                val shifted = Bitmap.createBitmap(targetWidthDots, targetHeightDots, scaledBitmap.config ?: Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(shifted)
                canvas.drawColor(android.graphics.Color.WHITE)
                canvas.drawBitmap(scaledBitmap, shiftX, 0f, null)

                if (scaledBitmap != bitmap) {
                    scaledBitmap.recycle()
                }
                bitmap.recycle()

                // Tuần tự hóa việc gửi TRÊN CÙNG máy này (khóa theo connection), khớp
                // với cơ chế khóa của luồng ESC. Các máy khác dùng khóa khác nên vẫn
                // in song song, không đợi nhau.
                synchronized(PrinterThermal.lockFor(conn)) {
                    printer.sizeMm(sizeWidth.toDouble(), sizeHeight.toDouble())
                        .gapMm(gapWidth, gapHeight)
                        .reference(0, 0)
                        .direction(0)
                    if (useHome) {
                        // Dò khe decal để canh lại đầu tem, xóa sai số đẩy giấy tích lũy.
                        printer.home()
                    }
                    printer.cls()
                        .bitmap(
                            0,
                            0,
                            TSPLConst.BMP_MODE_OVERWRITE,
                            targetWidthDots,
                            shifted,
                            AlgorithmType.Threshold
                        )
                        .print(1)

                    // Chặn tới khi tem NÀY thực sự ra khỏi hàng đợi gửi của SDK, VẪN
                    // trong khối khóa. Hai lý do, đều đã quan sát được trên tem in ra:
                    //
                    // 1. `bitmap()` chỉ XẾP lệnh vào LinkedBlockingQueue rồi return;
                    //    luồng consumer mới là chỗ đọc pixel của `shifted`. Recycle ngay
                    //    sau khối khóa (code cũ) giải phóng bitmap trong khi consumer còn
                    //    đang encode -> đọc trúng vùng nhớ đã thu hồi, ra nhiễu ngẫu
                    //    nhiên (VD dòng giá "30 đ" biến thành ký tự rác).
                    // 2. Consumer gặp lỗi ghi socket sẽ CLEAR sạch queue. Nếu đã nhồi cả
                    //    lô, một tem hỏng cuốn theo `PRINT 1` của các tem còn lại -> máy
                    //    không nhả giấy và tem kế in chồng lên tem trước.
                    //
                    // Giữ hàng đợi luôn chỉ có một tem khiến cả hai không xảy ra được.
                    PrinterThermal.awaitLabelSent(conn)
                }

                shifted.recycle()
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    internal fun printLabelUrovo(call: MethodCall, result: Result) {
        kotlin.concurrent.thread {
            try {
                val type = call.argument<String>("type")
                if (type != "TSPL") {
                    Handler(Looper.getMainLooper()).post { result.success(false) }
                    return@thread
                }

                val images: List<ByteArray>? = call.argument<List<ByteArray>>("images")
                if (images.isNullOrEmpty()) {
                    Handler(Looper.getMainLooper()).post { result.success(false) }
                    return@thread
                }

                val size = call.argument<Map<String, Any>>("size")
                val (sizeWidth, sizeHeight) = extractSizeImage(size)
                
                // 8 dots per mm
                val targetWidthDots = sizeWidth * 8
                val targetHeightDots = sizeHeight * 8

                val urovoPrinter = UrovoPrinterManager()
                if (!urovoPrinter.isSupported()) {
                    Handler(Looper.getMainLooper()).post { 
                        result.error("UROVO_ERROR", "Urovo PrinterManager not supported", null) 
                    }
                    return@thread
                }

                urovoPrinter.openPrinter()
                
                // Tối ưu tốc độ in
                urovoPrinter.setSpeedLevel(9)
                urovoPrinter.setGrayLevel(0)
                
                images.forEach { imageData ->
                    val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size) ?: return@forEach
                    
                    val scaledBitmap = Bitmap.createScaledBitmap(bitmap, targetWidthDots, targetHeightDots, true)
                    
                    urovoPrinter.setupPage(targetWidthDots, targetHeightDots)
                    urovoPrinter.drawBitmap(scaledBitmap, 0, 0)
                    urovoPrinter.printPage(0)

                    if (scaledBitmap != bitmap) {
                        scaledBitmap.recycle()
                    }
                    bitmap.recycle()
                }

                urovoPrinter.closePrinter()
                Handler(Looper.getMainLooper()).post { result.success(true) }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post { result.error("PRINT_ERROR", e.message, null) }
            }
        }
    }

    internal fun printImageESCUrovo(call: MethodCall, result: Result) {
        kotlin.concurrent.thread {
            try {
                val image: ByteArray? = call.argument<ByteArray>("image")
                if (image == null) {
                    Handler(Looper.getMainLooper()).post { result.success(false) }
                    return@thread
                }

                val urovoPrinter = UrovoPrinterManager()
                if (!urovoPrinter.isSupported()) {
                    Handler(Looper.getMainLooper()).post { 
                        result.error("UROVO_ERROR", "Urovo PrinterManager not supported", null) 
                    }
                    return@thread
                }

                urovoPrinter.openPrinter()
                
                // Tối ưu tốc độ: Speed level cao nhất (9), độ đậm nhạt thấp nhất (0) để in nhanh nhất
                urovoPrinter.setSpeedLevel(9)
                urovoPrinter.setGrayLevel(0)

                val bitmap = android.graphics.BitmapFactory.decodeByteArray(image, 0, image.size)
                if (bitmap != null) {
                    // Sử dụng chiều dài thực tế của ảnh thay vì -1
                    urovoPrinter.setupPage(bitmap.width, -1)
                    urovoPrinter.drawBitmap(bitmap, 0, 0)
                    urovoPrinter.printPage(0)
                    urovoPrinter.paperFeed(120) // Đẩy giấy lên thêm 1.5cm để cắt bill
                    bitmap.recycle()
                }

                urovoPrinter.closePrinter()
                Handler(Looper.getMainLooper()).post { result.success(true) }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post { result.error("PRINT_ERROR", e.message, null) }
            }
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

            PrinterThermal.awaitFlush(conn)
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

            PrinterThermal.awaitFlush(conn)
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

            PrinterThermal.awaitFlush(conn)
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

    internal fun printTextESCUrovo(call: MethodCall, result: Result) {
        kotlin.concurrent.thread {
            try {
                val text = call.argument<String>("text") ?: ""
                val urovoPrinter = UrovoPrinterManager()
                if (!urovoPrinter.isSupported()) {
                    Handler(Looper.getMainLooper()).post { result.error("UROVO_ERROR", "Not supported", null) }
                    return@thread
                }

                urovoPrinter.openPrinter()
                urovoPrinter.setupPage(384, -1)
                urovoPrinter.prnDrawText(text, 0, 0, "sans-serif", 24, false, false, 0)
                urovoPrinter.printPage(0)
                urovoPrinter.paperFeed(100)
                urovoPrinter.closePrinter()
                
                Handler(Looper.getMainLooper()).post { result.success(true) }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post { result.error("PRINT_ERROR", e.message, null) }
            }
        }
    }

    internal fun printBarcodeESCUrovo(call: MethodCall, result: Result) {
        kotlin.concurrent.thread {
            try {
                val code = call.argument<String>("code") ?: ""
                val urovoPrinter = UrovoPrinterManager()
                if (!urovoPrinter.isSupported()) {
                    Handler(Looper.getMainLooper()).post { result.error("UROVO_ERROR", "Not supported", null) }
                    return@thread
                }

                urovoPrinter.openPrinter()
                urovoPrinter.setupPage(384, -1)
                // Barcode type 8 corresponds to CODE128 in Urovo SDK
                urovoPrinter.drawBarcode(code, 40, 0, 8, 2, 60, 0)
                urovoPrinter.printPage(0)
                urovoPrinter.paperFeed(100)
                urovoPrinter.closePrinter()
                
                Handler(Looper.getMainLooper()).post { result.success(true) }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post { result.error("PRINT_ERROR", e.message, null) }
            }
        }
    }

    internal fun printQrCodeESCUrovo(call: MethodCall, result: Result) {
        kotlin.concurrent.thread {
            try {
                val code = call.argument<String>("code") ?: ""
                val urovoPrinter = UrovoPrinterManager()
                if (!urovoPrinter.isSupported()) {
                    Handler(Looper.getMainLooper()).post { result.error("UROVO_ERROR", "Not supported", null) }
                    return@thread
                }

                urovoPrinter.openPrinter()
                urovoPrinter.setupPage(384, -1)
                // For Urovo QR code is usually barcode type 58
                urovoPrinter.drawBarcode(code, 40, 0, 58, 6, 60, 0)
                urovoPrinter.printPage(0)
                urovoPrinter.paperFeed(100)
                urovoPrinter.closePrinter()
                
                Handler(Looper.getMainLooper()).post { result.success(true) }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post { result.error("PRINT_ERROR", e.message, null) }
            }
        }
    }

    internal fun toast(str: String) = Toast.makeText(mContext, str, Toast.LENGTH_SHORT).show()

    companion object {
        /** Instance được tự kết nối USB, xem [isUsbOwner]. */
        @Volatile private var usbOwner: PrinterLabelPlugin? = null
        internal const val REQUEST_PERMISSIONS_CODE = 1002
        private const val ACTION_USB_PERMISSION = "com.printer.printer_label.USB_PERMISSION"
        private const val CONNECT_TIMEOUT_MS = 3_000L

        /// Thời gian chờ hệ thống tự cấp quyền USB cho app mặc định sau khi cắm máy in
        /// (xem [handleUsbDeviceAttached]). Hết thời gian mà vẫn chưa có quyền (người
        /// dùng chưa tick "Luôn mở...") thì mới hiện dialog xin quyền.
        private const val USB_SYSTEM_GRANT_WAIT_MS = 1_500L

        /// Lớp chờ ngoài cho một lượt connect LAN: dài hơn LanSocketConnection.CONNECT_TIMEOUT_MS
        /// (6s) để không cắt ngang lúc socket đang bắt tay.
        internal const val LAN_CONNECT_TIMEOUT_MS = 8_000L

        /** A no-op Result used for fire-and-forget connects (e.g. USB auto-attach). */
        private val NoOpResult = object : Result {
            override fun success(result: Any?) {}
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
            override fun notImplemented() {}
        }
    }
}