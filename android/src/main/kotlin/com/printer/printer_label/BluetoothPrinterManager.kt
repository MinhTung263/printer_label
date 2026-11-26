package com.printer.printer_label

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel.Result
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect

class BluetoothPrinterManager(private val plugin: PrinterLabelPlugin) {
    internal var btScanReceiver: BroadcastReceiver? = null
    internal var scanEventSink: EventChannel.EventSink? = null
    internal var pendingBluetoothEnableCallback: ((Boolean) -> Unit)? = null

    // Biến điều khiển bộ lọc scan: true = chỉ hiển thị máy in, false = tất cả thiết bị BT
    private var filterPrinterOnly: Boolean = true
    // MAC đã gửi lên Flutter trong lượt quét hiện tại (một máy có thể tới cả qua
    // ACTION_FOUND lẫn ACTION_NAME_CHANGED). Chỉ đọc/ghi trên main thread.
    private val emittedScanMacs = mutableSetOf<String>()
    private val scanHandler = Handler(Looper.getMainLooper())

    internal val btScanStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            scanEventSink = events
            // Đọc tham số filterPrinterOnly từ Flutter (truyền qua receiveBroadcastStream arguments)
            @Suppress("UNCHECKED_CAST")
            val args = arguments as? Map<String, Any?>
            filterPrinterOnly = args?.get("filter_printer_only") as? Boolean ?: true
            startBluetoothScan()
        }

        override fun onCancel(arguments: Any?) {
            stopBluetoothScan()
            scanEventSink = null
        }
    }

    // Lấy các thiết bị ble đã từng ghép nối 
    // kết hớp với blueetoothScanStream (quét sóng usb thật sự) để hiển thị danh sách máy in cho người dùng chọn
    internal fun getBluetoothAdapter(): BluetoothAdapter? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            (plugin.mContext?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        else @Suppress("DEPRECATION") BluetoothAdapter.getDefaultAdapter()

    internal fun getBluetoothDevices(result: Result, filterPrinterOnly: Boolean = true) {
        if (!hasConnectPermission()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        try {
            val adapter = getBluetoothAdapter()
            if (adapter == null || !adapter.isEnabled) {
                result.success(emptyList<Map<String, Any>>())
                return
            }
            val list = adapter.bondedDevices
                .filter { !filterPrinterOnly || isPrinter(it) }
                .map {
                    mapOf(
                        "name" to (it.name ?: "Unknown"),
                        "mac" to it.address
                    )
                }
            result.success(list)
        } catch (e: SecurityException) {
            result.success(emptyList<Map<String, Any>>())
        } catch (e: Exception) {
            result.error("BT_ERROR", e.message, null)
        }
    }

    /**
     * Thiết bị có phải máy in không — dựa vào Class of Device (loại thiết bị máy tự
     * khai báo) trước, tên sau:
     *  0. Thiết bị CHỈ có BLE → loại: Android in qua SPP (Classic) bằng POSConnect,
     *     không có đường in BLE. Máy dual-mode (MJ5803...) phát thêm một địa chỉ BLE
     *     riêng (vd C0:15:83:.. bên cạnh 00:15:83:..) → không loại thì hiện 2 lần, chọn
     *     nhầm địa chỉ BLE sẽ không kết nối được.
     *  1. Lớp IMAGING (máy in/máy quét) → nhận.
     *  2. Tên khớp từ khoá máy in → nhận.
     *  3. Lớp chắc chắn không phải máy in (điện thoại, máy tính, tai nghe/loa/TV,
     *     đồng hồ, chuột/bàn phím, sức khoẻ, đồ chơi, mạng) → loại.
     *  4. Máy THUẦN Bluetooth Classic không khai lớp (UNCATEGORIZED/MISC) và có tên → nhận.
     *     Máy in giá rẻ (MJ5803...) hay khai lớp này. Chỉ áp dụng cho Classic/Dual:
     *     thiết bị chỉ có BLE tìm thấy qua discovery luôn mang lớp UNCATEGORIZED
     *     (vòng tay, đồng hồ...) nên với BLE chỉ dựa vào tên.
     *
     * [btClass]/[nameOverride]: lấy từ intent lúc quét (EXTRA_CLASS/EXTRA_NAME) vì
     * `device.bluetoothClass`/`device.name` có thể chưa kịp cập nhật.
     */
    internal fun isPrinter(
        device: BluetoothDevice,
        btClass: BluetoothClass? = null,
        nameOverride: String? = null,
    ): Boolean {
        try {
            val type = device.type
            if (type == BluetoothDevice.DEVICE_TYPE_LE) return false

            val major = (btClass ?: device.bluetoothClass)?.majorDeviceClass
            if (major == BluetoothClass.Device.Major.IMAGING) return true

            val name = nameOverride ?: device.name ?: ""
            if (name.isEmpty()) return false
            if (matchesPrinterName(name)) return true

            if (major in NON_PRINTER_MAJORS) return false

            // Chỉ máy THUẦN Classic: máy dual-mode (tai nghe, TV box... Bluetooth 5.x) dò qua sóng
            // BLE cũng mang lớp UNCATEGORIZED nên lọt vào danh sách (đã gặp: "ZE8000", "A9 Pro Box").
            // Máy in Classic thật (MJ5803...) khi dò Classic tự khai IMAGING/PRINTER -> nhận ở bước 1.
            return type == BluetoothDevice.DEVICE_TYPE_CLASSIC &&
                (major == BluetoothClass.Device.Major.UNCATEGORIZED ||
                    major == BluetoothClass.Device.Major.MISC)
        } catch (e: Exception) {
            return false
        }
    }

    // Tên có giống máy in không: danh sách từ khóa dài và tiền tố ngắn (giống iOS),
    // cũng như các từ khóa "InnerPrinter" và "Printer".
    private fun matchesPrinterName(name: String): Boolean {
        try {
            val lowerName = name.lowercase()
            if (lowerName.isEmpty()) return false

            // Từ khóa dài khớp ở bất kỳ đâu trong tên; model MINJCODE trần (MJ5803...) — xem
            // PRINTER_NAME_KEYWORDS / MJ_MODEL (tạo một lần, hàm này chạy cho mỗi thiết bị quét thấy).
            val matchesLong = PRINTER_NAME_KEYWORDS.any { lowerName.contains(it) } ||
                MJ_MODEL.containsMatchIn(lowerName)

            // Tiền tố ngắn: khớp ở đầu tên hoặc đi kèm khoảng trắng/gạch ngang/gạch dưới (giống iOS)
            val matchesShort = PRINTER_NAME_PREFIXES.any { prefix ->
                lowerName.startsWith(prefix) ||
                lowerName.contains("$prefix-") ||
                lowerName.contains("$prefix ") ||
                lowerName.contains("_$prefix")
            }

            return matchesLong || matchesShort ||
                   lowerName.contains("InnerPrinter", ignoreCase = true) ||
                   lowerName.contains("Printer", ignoreCase = true)
        } catch (e: Exception) {
            return false
        }
    }

    internal fun startBluetoothScan() {
        requestScanPermissions { granted ->
            if (granted) {
                // Tự động nhắc bật dịch vụ Vị trí (GPS) trên Android < 12 nếu chưa bật định vị
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && !isLocationServiceEnabled()) {
                    showLocationSettingsDialog()
                }

                val adapter = getBluetoothAdapter() ?: return@requestScanPermissions
                proceedBluetoothScan(adapter)
            } else {
                scanEventSink?.error("BT_PERMISSION", "Missing required Bluetooth scan/location permission", null)
            }
        }
    }

    private fun proceedBluetoothScan(adapter: BluetoothAdapter) {
        scanHandler.removeCallbacksAndMessages(null)
        if (!adapter.isEnabled) {
            // Thử bật ngầm trước (hoạt động trên các bản ROM máy POS cũ hoặc đặc quyền)
            var silentSuccess = false
            try {
                @Suppress("DEPRECATION")
                silentSuccess = adapter.enable()
            } catch (_: Exception) {}

            if (silentSuccess) {
                var attempts = 0
                val runnable = object : Runnable {
                    override fun run() {
                        if (adapter.isEnabled) {
                            try { adapter.cancelDiscovery() } catch (_: Exception) {}
                            scanHandler.postDelayed({
                                if (!plugin.isDetached && scanEventSink != null) {
                                    actualStartBluetoothScan(adapter)
                                }
                            }, 350L)
                        } else if (attempts < 25) {
                            attempts++
                            scanHandler.postDelayed(this, 200)
                        } else {
                            scanEventSink?.error("BT_OFF", "Bluetooth is not enabled", null)
                        }
                    }
                }
                scanHandler.postDelayed(runnable, 200)
            } else {
                // Bật ngầm thất bại -> hiển thị hộp thoại xin bật Bluetooth chính thức thông qua Activity
                requestBluetoothEnable { success ->
                    if (success) {
                        var attempts = 0
                        val runnable = object : Runnable {
                            override fun run() {
                                if (adapter.isEnabled) {
                                    try { adapter.cancelDiscovery() } catch (_: Exception) {}
                                    scanHandler.postDelayed({
                                        if (!plugin.isDetached && scanEventSink != null) {
                                            actualStartBluetoothScan(adapter)
                                        }
                                    }, 350L)
                                } else if (attempts < 25) {
                                    attempts++
                                    scanHandler.postDelayed(this, 200)
                                } else {
                                    scanEventSink?.error("BT_OFF", "Bluetooth is not enabled", null)
                                }
                            }
                        }
                        scanHandler.postDelayed(runnable, 200)
                    } else {
                        scanEventSink?.error("BT_OFF", "Bluetooth is not enabled", null)
                    }
                }
            }
            return
        }

        // Luôn huỷ quét cũ trước để giải phóng tài nguyên cho Bluetooth stack
        try {
            adapter.cancelDiscovery()
        } catch (_: SecurityException) {}

        // Trì hoãn 350ms để đảm bảo Bluetooth stack hoàn tất việc hủy quét cũ
        scanHandler.postDelayed({
            if (!plugin.isDetached && scanEventSink != null) {
                actualStartBluetoothScan(adapter)
            }
        }, 350L)
    }

    private fun actualStartBluetoothScan(adapter: BluetoothAdapter) {
        scanHandler.removeCallbacksAndMessages(null)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    // ACTION_FOUND thường tới khi CHƯA có tên; tên tới sau qua
                    // ACTION_NAME_CHANGED → xét lại ở đó, không thì máy tên lạ bị bỏ sót.
                    BluetoothDevice.ACTION_FOUND,
                    BluetoothDevice.ACTION_NAME_CHANGED -> {
                        val device: BluetoothDevice? =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                intent.getParcelableExtra(
                                    BluetoothDevice.EXTRA_DEVICE,
                                    BluetoothDevice::class.java
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                            }
                        val btClass: BluetoothClass? =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                intent.getParcelableExtra(
                                    BluetoothDevice.EXTRA_CLASS,
                                    BluetoothClass::class.java
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                intent.getParcelableExtra(BluetoothDevice.EXTRA_CLASS)
                            }
                        val extraName = intent.getStringExtra(BluetoothDevice.EXTRA_NAME)
                        device?.let {
                            val mac = it.address
                            if (mac in emittedScanMacs) return@let
                            val name = extraName ?: it.name
                            if (!filterPrinterOnly || isPrinter(it, btClass, name)) {
                                // Chưa có tên thì chờ ACTION_NAME_CHANGED (trừ khi đang
                                // hiện tất cả) để danh sách không có dòng "Unknown".
                                if (name.isNullOrEmpty() && filterPrinterOnly &&
                                    btClass?.majorDeviceClass != BluetoothClass.Device.Major.IMAGING
                                ) return@let
                                emittedScanMacs.add(mac)
                                val map = mapOf("name" to (name ?: "Unknown"), "mac" to mac)
                                scanHandler.post {
                                    scanEventSink?.success(map)
                                }
                            }
                        }
                    }

                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        scanHandler.post {
                            scanEventSink?.endOfStream()
                        }
                        stopBluetoothScan()
                    }
                }
            }
        }
        val filter = IntentFilter(BluetoothDevice.ACTION_FOUND).apply {
            addAction(BluetoothDevice.ACTION_NAME_CHANGED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        emittedScanMacs.clear()
        plugin.mContext?.registerReceiver(receiver, filter)
        btScanReceiver = receiver

        val success = try {
            adapter.startDiscovery()
        } catch (_: SecurityException) {
            scanEventSink?.error("BT_PERMISSION", "Missing BLUETOOTH_SCAN permission", null)
            false
        }

        if (!success) {
            // Thử lại sau 300ms nếu startDiscovery thất bại (do Bluetooth stack bận)
            scanHandler.postDelayed({
                if (!plugin.isDetached && scanEventSink != null) {
                    try {
                        adapter.startDiscovery()
                    } catch (_: SecurityException) {}
                }
            }, 300L)
        }
    }

    internal fun stopBluetoothScan() {
        scanHandler.removeCallbacksAndMessages(null)
        runCatching { getBluetoothAdapter()?.cancelDiscovery() }
        runCatching { btScanReceiver?.let { plugin.mContext?.unregisterReceiver(it) } }
        btScanReceiver = null
    }

    internal fun connectBt(macAddress: String, result: Result, markBuiltIn: Boolean = false) {
        val deviceId = "BT:$macAddress"
        try {
            if (macAddress.isEmpty()) {
                result.error("INVALID_MAC", "Mac address is empty", null); return
            }

            val adapter = getBluetoothAdapter()
            if (adapter == null || !adapter.isEnabled) {
                result.error("BT_OFF", "Bluetooth is not enabled", null); return
            }

            stopBluetoothScan()

            // Đánh dấu tường minh đây là máy in tích hợp (luồng auto-connect built-in).
            if (markBuiltIn) {
                plugin.builtInDeviceIds.add(deviceId)
            }

            // Connect trùng deviceId: gộp result vào lệnh đang chờ thay vì ghi đè, nếu
            // không result của lệnh trước bị mất -> Future treo tới timeout và timeout
            // handler đóng luôn kết nối vừa thành công.
            val existing = plugin.pendingConnects.putIfAbsent(
                deviceId,
                PrinterLabelPlugin.PendingConnect(result, ConnectionType.BT, deviceId)
            )
            if (existing != null) {
                synchronized(existing.results) { existing.results.add(result) }
                return
            }

            // Kết nối hiện có còn sống (VD lệnh in vừa nối xong): dùng luôn, không đóng —
            // đóng ở đây là cắt ngang lệnh in đang gửi trên kết nối đó.
            plugin.connections[deviceId]?.let { existing ->
                if (existing.isConnect) {
                    plugin.pendingConnects.remove(deviceId)?.complete(true)
                    return
                }
            }

            runCatching { plugin.connections[deviceId]?.close() }

            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_BLUETOOTH) ?: run {
                plugin.pendingConnects.remove(deviceId)
                result.error("CREATE_DEVICE_FAIL", "Cannot create device", null)
                return
            }
            plugin.connections[deviceId] = device
            plugin.connectionTypes[deviceId] = ConnectionType.BT
            device.connect(
                plugin.rawId(deviceId),
                // owner: sự kiện lỗi của kết nối CŨ (đã bị thay) không được xoá kết nối mới.
                plugin.makeConnectListener(deviceId) { device }
            )
            plugin.scheduleConnectTimeout(deviceId)
        } catch (e: Exception) {
            e.printStackTrace()
            plugin.connections.remove(deviceId)
            plugin.connectionTypes.remove(deviceId)
            plugin.pendingConnects.remove(deviceId)
            result.error("CONNECT_ERROR", e.message, null)
        }
    }

    internal fun autoConnectBuiltIn(result: Result) {
        // Gồm cả máy POS chưa xác minh ("có thể có"): thử tìm máy in ảo.
        if (!mayHaveBuiltInPrinter(plugin.mContext)) {
            result.success(false)
            return
        }

        requestConnectPermissions { granted ->
            if (granted) {
                // 1. Chỉ coi là đã kết nối khi có kết nối MÁY IN TÍCH HỢP đang hoạt động
                //    (không tính máy ngoài), để không bỏ qua bước đánh dấu built-in.
                val hasBuiltInConn = plugin.connections.entries.any {
                    isConnectionToBuiltInPrinter(it.value) && plugin.isConnectionActive(it.key)
                }
                if (hasBuiltInConn) {
                    result.success(true)
                    return@requestConnectPermissions
                }

                val adapter = getBluetoothAdapter() ?: run {
                    result.success(false)
                    return@requestConnectPermissions
                }

                proceedAutoConnectBuiltIn(adapter, result)
            } else {
                result.success(false)
            }
        }
    }

    private fun proceedAutoConnectBuiltIn(adapter: BluetoothAdapter, result: Result) {
        // 2. Tự động bật Bluetooth nếu đang tắt
        if (!adapter.isEnabled) {
            var silentSuccess = false
            try {
                // Thử bật ngầm trước (hoạt động trên các bản ROM máy POS cũ hoặc đặc quyền)
                silentSuccess = adapter.enable()
            } catch (e: SecurityException) {
                // Bị chặn bảo mật
            } catch (e: Exception) {
                // Lỗi khác
            }

            if (silentSuccess) {
                // Khởi chạy vòng lặp Polling để đợi Bluetooth bật lên thành công (vì bật ngầm mất chút thời gian)
                var attempts = 0
                val handler = Handler(Looper.getMainLooper())
                val runnable = object : Runnable {
                    override fun run() {
                        if (adapter.isEnabled) {
                            findAndConnectBuiltInPrinter(adapter, result)
                        } else if (attempts < 25) {
                            attempts++
                            handler.postDelayed(this, 200)
                        } else {
                            requestBluetoothEnable { success ->
                                if (success) {
                                    var attemptsInner = 0
                                    val handlerInner = Handler(Looper.getMainLooper())
                                    val runnableInner = object : Runnable {
                                        override fun run() {
                                            if (adapter.isEnabled) {
                                                findAndConnectBuiltInPrinter(adapter, result)
                                            } else if (attemptsInner < 25) {
                                                attemptsInner++
                                                handlerInner.postDelayed(this, 200)
                                            } else {
                                                result.success(false)
                                            }
                                        }
                                    }
                                    handlerInner.postDelayed(runnableInner, 200)
                                } else {
                                    result.success(false)
                                }
                            }
                        }
                    }
                }
                handler.postDelayed(runnable, 200)
            } else {
                // Bật ngầm thất bại/không được phép -> hiển thị hộp thoại xin bật Bluetooth chính thức thông qua Activity
                requestBluetoothEnable { success ->
                    if (success) {
                        var attempts = 0
                        val handler = Handler(Looper.getMainLooper())
                        val runnable = object : Runnable {
                            override fun run() {
                                if (adapter.isEnabled) {
                                    findAndConnectBuiltInPrinter(adapter, result)
                                } else if (attempts < 25) {
                                    attempts++
                                    handler.postDelayed(this, 200)
                                } else {
                                    result.success(false)
                                }
                            }
                        }
                        handler.postDelayed(runnable, 200)
                    } else {
                        result.success(false)
                    }
                }
            }
            return
        }

        findAndConnectBuiltInPrinter(adapter, result)
    }

    private fun findAndConnectBuiltInPrinter(adapter: BluetoothAdapter, result: Result) {
        try {
            val printerMac: String? = pickBuiltInMac(adapter.bondedDevices)

            val mac = printerMac ?: run {
                // Chưa thấy máy in ảo: Bluetooth vừa bật có thể chưa nạp xong danh sách ghép đôi -> đọc lại sau một
                // nhịp rồi MỚI kết luận (không chặn luồng giao diện).
                Handler(Looper.getMainLooper()).postDelayed({
                    val again = try { pickBuiltInMac(adapter.bondedDevices) } catch (_: Exception) { null }
                    if (again != null) {
                        connectBt(again, result, markBuiltIn = true)
                    } else {
                        concludeNoVirtualPrinter(adapter)
                        result.success(false)
                    }
                }, NO_VIRTUAL_PRINTER_RECHECK_MS)
                return
            }

            // Kết nối và ĐÁNH DẤU đây là máy in tích hợp.
            connectBt(mac, result, markBuiltIn = true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    internal fun hasConnectPermission(): Boolean {
        val context = plugin.mContext ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return androidx.core.content.ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_CONNECT
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    internal fun hasScanPermission(): Boolean {
        val context = plugin.mContext ?: return false
        val fineLocationGranted = androidx.core.content.ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val coarseLocationGranted = androidx.core.content.ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_COARSE_LOCATION
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val locationOk = fineLocationGranted || coarseLocationGranted

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connectGranted = androidx.core.content.ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_CONNECT
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            val scanGranted = androidx.core.content.ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_SCAN
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            return connectGranted && scanGranted && locationOk
        }
        return locationOk
    }

    internal fun openAppSettings() {
        val context = plugin.mContext ?: return
        try {
            // Thử mở thẳng màn hình Quản lý quyền (Permissions) của ứng dụng
            val intent = Intent("android.intent.action.MANAGE_APP_PERMISSIONS").apply {
                putExtra("android.intent.extra.PACKAGE_NAME", context.packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            try {
                // Nếu không hỗ trợ hoặc bị chặn trên một số dòng máy, fallback về màn hình Thông tin ứng dụng (App Info) mặc định
                val intentFallback = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.fromParts("package", context.packageName, null)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intentFallback)
            } catch (_: Exception) {}
        }
    }

    private fun getPrefs(): android.content.SharedPreferences? {
        return plugin.mContext?.getSharedPreferences("printer_label_prefs", Context.MODE_PRIVATE)
    }

    private fun hasAskedPermission(permission: String): Boolean {
        return getPrefs()?.getBoolean("asked_$permission", false) == true
    }

    private fun setAskedPermission(permission: String) {
        getPrefs()?.edit()?.putBoolean("asked_$permission", true)?.apply()
    }

    private fun showPermissionDialog(message: String, onConfirm: () -> Unit) {
        val currentActivity = plugin.activity ?: return
        currentActivity.runOnUiThread {
            try {
                val context = currentActivity
                val scale = context.resources.displayMetrics.density
                val dp = { value: Int -> (value * scale).toInt() }

                // 1. Tạo container LinearLayout
                val container = android.widget.LinearLayout(context).apply {
                    orientation = android.widget.LinearLayout.VERTICAL
                    setPadding(dp(24), dp(28), dp(24), dp(24))
                    background = android.graphics.drawable.GradientDrawable().apply {
                        setColor(android.graphics.Color.parseColor("#FFFFFF"))
                        cornerRadius = dp(20).toFloat()
                    }
                }

                // 2. Tạo hình tròn chứa Icon an ninh gradient
                val iconContainer = android.widget.FrameLayout(context).apply {
                    layoutParams = android.widget.LinearLayout.LayoutParams(dp(56), dp(56)).apply {
                        gravity = android.view.Gravity.CENTER_HORIZONTAL
                        bottomMargin = dp(16)
                    }
                    background = android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.OVAL
                        colors = intArrayOf(
                            android.graphics.Color.parseColor("#EEF2FF"),
                            android.graphics.Color.parseColor("#E0E7FF")
                        )
                    }
                }

                val iconView = android.widget.ImageView(context).apply {
                    layoutParams = android.widget.FrameLayout.LayoutParams(dp(28), dp(28)).apply {
                        gravity = android.view.Gravity.CENTER
                    }
                    setImageResource(android.R.drawable.ic_lock_lock)
                    setColorFilter(android.graphics.Color.parseColor("#4F46E5"))
                }
                iconContainer.addView(iconView)
                container.addView(iconContainer)

                // 3. Tiêu đề
                val titleView = android.widget.TextView(context).apply {
                    layoutParams = android.widget.LinearLayout.LayoutParams(
                        android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                        android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
                    ).apply {
                        bottomMargin = dp(12)
                    }
                    text = "Cần cấp quyền truy cập"
                    textAlignment = android.view.View.TEXT_ALIGNMENT_CENTER
                    textSize = 19f
                    setTextColor(android.graphics.Color.parseColor("#1E293B"))
                    typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.BOLD)
                }
                container.addView(titleView)

                // 4. Nội dung mô tả
                val messageView = android.widget.TextView(context).apply {
                    layoutParams = android.widget.LinearLayout.LayoutParams(
                        android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                        android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
                    ).apply {
                        bottomMargin = dp(24)
                    }
                    text = message
                    textAlignment = android.view.View.TEXT_ALIGNMENT_CENTER
                    textSize = 14.5f
                    setTextColor(android.graphics.Color.parseColor("#64748B"))
                    setLineSpacing(0f, 1.25f)
                }
                container.addView(messageView)

                // 5. Layout chứa các button
                val buttonLayout = android.widget.LinearLayout(context).apply {
                    orientation = android.widget.LinearLayout.HORIZONTAL
                    layoutParams = android.widget.LinearLayout.LayoutParams(
                        android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                        dp(46)
                    )
                }

                val btnCancel = android.widget.Button(context).apply {
                    layoutParams = android.widget.LinearLayout.LayoutParams(0, android.widget.LinearLayout.LayoutParams.MATCH_PARENT, 1f).apply {
                        rightMargin = dp(8)
                    }
                    text = "Đóng"
                    textSize = 14f
                    isAllCaps = false
                    setTextColor(android.graphics.Color.parseColor("#64748B"))
                    background = android.graphics.drawable.GradientDrawable().apply {
                        setColor(android.graphics.Color.parseColor("#F1F5F9"))
                        cornerRadius = dp(12).toFloat()
                    }
                }

                val btnConfirm = android.widget.Button(context).apply {
                    layoutParams = android.widget.LinearLayout.LayoutParams(0, android.widget.LinearLayout.LayoutParams.MATCH_PARENT, 1f).apply {
                        leftMargin = dp(8)
                    }
                    text = "Đến Cài đặt"
                    textSize = 14f
                    isAllCaps = false
                    setTextColor(android.graphics.Color.WHITE)
                    background = android.graphics.drawable.GradientDrawable().apply {
                        colors = intArrayOf(
                            android.graphics.Color.parseColor("#4F46E5"),
                            android.graphics.Color.parseColor("#4338CA")
                        )
                        orientation = android.graphics.drawable.GradientDrawable.Orientation.LEFT_RIGHT
                        cornerRadius = dp(12).toFloat()
                    }
                }

                buttonLayout.addView(btnCancel)
                buttonLayout.addView(btnConfirm)
                container.addView(buttonLayout)

                val dialog = android.app.Dialog(context)
                dialog.requestWindowFeature(android.view.Window.FEATURE_NO_TITLE)
                dialog.setContentView(container)
                dialog.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT))
                dialog.show()

                // Thiết lập kích thước dialog to và đẹp hơn (85% chiều rộng màn hình)
                val metrics = context.resources.displayMetrics
                val width = (metrics.widthPixels * 0.85).toInt()
                dialog.window?.setLayout(width, android.view.ViewGroup.LayoutParams.WRAP_CONTENT)

                btnCancel.setOnClickListener {
                    dialog.dismiss()
                }
                btnConfirm.setOnClickListener {
                    dialog.dismiss()
                    onConfirm()
                }
            } catch (e: Exception) {
                e.printStackTrace()
                onConfirm()
            }
        }
    }

    internal fun requestConnectPermissions(callback: (Boolean) -> Unit) {
        if (hasConnectPermission()) {
            callback(true)
            return
        }

        val activity = plugin.activity
        if (activity == null) {
            callback(false)
            return
        }

        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(android.Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            emptyArray()
        }

        if (permissions.isEmpty()) {
            callback(true)
            return
        }

        plugin.permissionCallback = { granted ->
            if (granted) {
                callback(true)
            } else {
                val msg = "Ứng dụng cần quyền thiết bị Bluetooth ở gần để kết nối máy in. Vui lòng bật quyền tại mục Quyền (Permissions) ở trang cài đặt tiếp theo."
                showPermissionDialog(msg) {
                    openAppSettings()
                }
                callback(false)
            }
        }

        androidx.core.app.ActivityCompat.requestPermissions(
            activity,
            permissions,
            PrinterLabelPlugin.REQUEST_PERMISSIONS_CODE
        )
    }

    internal fun requestScanPermissions(callback: (Boolean) -> Unit) {
        if (hasScanPermission()) {
            callback(true)
            return
        }

        val activity = plugin.activity
        if (activity == null) {
            callback(false)
            return
        }

        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                android.Manifest.permission.BLUETOOTH_CONNECT,
                android.Manifest.permission.BLUETOOTH_SCAN,
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_COARSE_LOCATION
            )
        } else {
            arrayOf(
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_COARSE_LOCATION
            )
        }

        plugin.permissionCallback = { granted ->
            if (granted) {
                callback(true)
            } else {
                val msg = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    "Ứng dụng cần quyền thiết bị Bluetooth ở gần và quyền Vị trí để tìm kiếm máy in. Vui lòng bật cả hai quyền tại mục Quyền (Permissions) ở trang cài đặt tiếp theo."
                } else {
                    "Ứng dụng cần quyền Vị trí để quét tìm máy in Bluetooth. Vui lòng bật quyền tại mục Quyền (Permissions) ở trang cài đặt tiếp theo."
                }
                showPermissionDialog(msg) {
                    openAppSettings()
                }
                callback(false)
            }
        }

        androidx.core.app.ActivityCompat.requestPermissions(
            activity,
            permissions,
            PrinterLabelPlugin.REQUEST_PERMISSIONS_CODE
        )
    }

    internal fun isLocationServiceEnabled(): Boolean {
        val context = plugin.mContext ?: return false
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? android.location.LocationManager
        return locationManager?.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) == true ||
               locationManager?.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER) == true
    }

    private fun showLocationSettingsDialog() {
        val currentActivity = plugin.activity ?: return
        currentActivity.runOnUiThread {
            try {
                val builder = android.app.AlertDialog.Builder(currentActivity)
                builder.setTitle("Yêu cầu bật Vị trí (GPS)")
                builder.setMessage("Để quét tìm các thiết bị Bluetooth xung quanh, vui lòng bật dịch vụ định vị (GPS).")
                builder.setPositiveButton("Bật GPS") { dialog, _ ->
                    dialog.dismiss()
                    val intent = Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                    currentActivity.startActivity(intent)
                }
                builder.setNegativeButton("Đóng") { dialog, _ ->
                    dialog.dismiss()
                }
                val dialog = builder.create()
                dialog.show()
                dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE)?.setTextColor(android.graphics.Color.parseColor("#4F46E5"))
                dialog.getButton(android.app.AlertDialog.BUTTON_NEGATIVE)?.setTextColor(android.graphics.Color.parseColor("#64748B"))
            } catch (_: Exception) {}
        }
    }



    internal fun requestBluetoothEnable(callback: (Boolean) -> Unit) {
        val activity = plugin.activity
        if (activity == null) {
            callback(false)
            return
        }

        pendingBluetoothEnableCallback = callback
        try {
            val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
            activity.startActivityForResult(intent, REQUEST_ENABLE_BT)
        } catch (e: Exception) {
            pendingBluetoothEnableCallback = null
            callback(false)
        }
    }

    internal fun handleBluetoothEnableResult(resultCode: Int) {
        val callback = pendingBluetoothEnableCallback ?: return
        pendingBluetoothEnableCallback = null

        callback(resultCode == Activity.RESULT_OK)
    }


    companion object {
        internal const val REQUEST_ENABLE_BT = 1001

        /** Từ khóa tên máy in, khớp ở bất kỳ đâu trong tên (giống iOS). */
        private val PRINTER_NAME_KEYWORDS = listOf(
            "print", "pos", "thermal", "spp", "label", "barcode", "receipt", "ticket",
            "epson", "star", "citizen", "bixolon", "sewoo", "brother", "tsc", "sprt",
            "hprt", "goojprt", "kiotviet", "sapo", "sunmi", "paperang", "peripage", "niimbot", "zijiang",
            "minjcode"
        )

        /** MINJCODE phát tên model trần (MJ5803, MJ-8001...); "mj" + số để không dính Xiaomi Mijia (MJYD...). */
        private val MJ_MODEL = Regex("^mj[-_ ]?\\d")

        /** Tiền tố tên máy in ngắn (giống iOS). */
        private val PRINTER_NAME_PREFIXES = listOf(
            "mpt", "rpp", "rt", "pt", "xp", "gp", "zj", "qs", "nt", "mtp", "cc", "dl", "jc"
        )

        /** Lớp thiết bị chắc chắn không phải máy in (xem [isPrinter]). */
        private val NON_PRINTER_MAJORS = setOf(
            BluetoothClass.Device.Major.PHONE,
            BluetoothClass.Device.Major.COMPUTER,
            BluetoothClass.Device.Major.AUDIO_VIDEO,
            BluetoothClass.Device.Major.WEARABLE,
            BluetoothClass.Device.Major.PERIPHERAL,
            BluetoothClass.Device.Major.HEALTH,
            BluetoothClass.Device.Major.TOY,
            BluetoothClass.Device.Major.NETWORKING,
        )

        /**
         * Tên Bluetooth [name] có khớp mẫu máy in tích hợp không — LỚP DỰ PHÒNG
         * (nguồn chính là builtInDeviceIds được đánh dấu lúc kết nối). Danh sách
         * tên ở [BuiltInPrinterRules].
         */
        internal fun isBuiltInPrinterName(name: String?): Boolean =
            BuiltInPrinterRules.isBuiltInName(name)
    }

    /**
     * Chọn máy in tích hợp trong các thiết bị đã ghép đôi theo ĐIỂM
     * ([BuiltInPrinterRules.pick]): máy in ảo (MAC giả, chưa từng dò qua sóng,
     * tên nội bộ) thắng máy in Bluetooth ngoài đã ghép đôi — không còn lấy "máy
     * in đầu tiên" theo thứ tự ngẫu nhiên.
     */
    private fun pickBuiltInMac(paired: Set<BluetoothDevice>?): String? {
        // Chỉ theo tên (không theo lớp như isPrinter): BuiltInPrinterRules đã chấm lớp
        // IMAGING riêng, nới thêm ở đây sẽ làm lệch điểm chọn máy in tích hợp.
        val bonded = paired?.map {
            it.toBonded(printerLike = matchesPrinterName(runCatching { it.name }.getOrNull() ?: ""))
        } ?: return null
        val tier = builtInTier(plugin.mContext)
        val picked = BuiltInPrinterRules.pick(bonded, tier, strictVirtual = requiresVirtualPrinter()) ?: return null
        // Máy chưa xác minh mà tìm được máy in ảo: từ giờ coi là có máy in tích
        // hợp (các chốt isBuiltInPrinter() trong plugin + khổ giấy).
        if (tier != BuiltInPrinterRules.Tier.VERIFIED || BuiltInPrinterRules.isStrong(picked)) {
            markBuiltInPrinterConfirmed()
        } else {
            clearNoVirtualPrinterFound()
        }
        return picked.mac
    }

    /** Chờ trước khi đọc lại danh sách ghép đôi để kết luận "không có máy in ảo". */
    private val NO_VIRTUAL_PRINTER_RECHECK_MS = 1_500L

    /**
     * Hai lần đọc danh sách ghép đôi đều KHÔNG thấy máy in ảo -> máy này không có máy in tích hợp (xem
     * [markNoVirtualPrinterFound]). Chỉ kết luận khi thật sự đọc được danh sách (Bluetooth bật, có quyền) và không
     * phải máy Urovo (in bằng SDK riêng, không qua Bluetooth ảo).
     */
    private fun concludeNoVirtualPrinter(adapter: BluetoothAdapter) {
        if (!adapter.isEnabled || !hasConnectPermission()) return
        if (UrovoPrinterManager.isUrovoDevice()) return
        Log.i("BUILTIN_PRINTER", "Không thấy máy in ảo trong danh sách ghép đôi: máy này không có máy in tích hợp")
        markNoVirtualPrinterFound()
    }

    internal fun autoConnectBuiltInSync(): Boolean {
        if (!mayHaveBuiltInPrinter(plugin.mContext)) {
            return false
        }

        val latchPermission = java.util.concurrent.CountDownLatch(1)
        var hasPermission = false
        Handler(Looper.getMainLooper()).post {
            requestConnectPermissions { granted ->
                hasPermission = granted
                latchPermission.countDown()
            }
        }
        latchPermission.await()
        if (!hasPermission) return false

        // 1. Kiểm tra xem đã có kết nối nào đến máy in tích hợp hoạt động chưa
        val hasBuiltInConn = plugin.connections.entries.any { 
            isConnectionToBuiltInPrinter(it.value) && plugin.isConnectionActive(it.key) 
        }
        if (hasBuiltInConn) {
            return true
        }

        val adapter = getBluetoothAdapter() ?: return false

        // 2. Tự động bật Bluetooth nếu đang tắt
        if (!adapter.isEnabled) {
            var silentSuccess = false
            try {
                silentSuccess = adapter.enable()
            } catch (_: Exception) {}

            if (silentSuccess) {
                // Đợi tối đa 2.5 giây cho Bluetooth bật hẳn (bật ngầm)
                var attempts = 0
                while (!adapter.isEnabled && attempts < 25) {
                    Thread.sleep(100)
                    attempts++
                }
            }

            // Nếu bật ngầm thất bại HOẶC bật ngầm báo thành công nhưng đợi mãi vẫn không bật được -> hiện popup chính thức
            if (!adapter.isEnabled) {
                val latch = java.util.concurrent.CountDownLatch(1)
                var userAccepted = false
                Handler(Looper.getMainLooper()).post {
                    requestBluetoothEnable { success ->
                        userAccepted = success
                        latch.countDown()
                    }
                }
                // Chờ tối đa 30 giây để người dùng trả lời popup
                latch.await(30_000, java.util.concurrent.TimeUnit.MILLISECONDS)
                if (!userAccepted) return false
                // Đợi thêm tối đa 2.5 giây cho adapter bật hẳn sau khi user chấp nhận
                var attempts = 0
                while (!adapter.isEnabled && attempts < 25) {
                    Thread.sleep(100)
                    attempts++
                }
            }

            if (!adapter.isEnabled) return false
        }

        // Tìm MAC address của máy in tích hợp
        val pairedDevices: Set<BluetoothDevice>? = try {
            adapter.bondedDevices
        } catch (_: SecurityException) {
            null
        }
        var printerMac: String? = pickBuiltInMac(pairedDevices)

        if (printerMac == null) {
            // Đọc lại sau một nhịp rồi mới kết luận (danh sách ghép đôi có thể chưa nạp xong). Đang ở luồng nền.
            Thread.sleep(NO_VIRTUAL_PRINTER_RECHECK_MS)
            printerMac = pickBuiltInMac(try { adapter.bondedDevices } catch (_: SecurityException) { null })
        }
        val mac = printerMac ?: run {
            concludeNoVirtualPrinter(adapter)
            return false
        }

        // Kết nối đồng bộ và ĐÁNH DẤU đây là máy in tích hợp.
        return connectBtSync(mac, markBuiltIn = true)
    }

    /** Chờ kết nối Bluetooth (kể cả chờ lệnh kết nối khác tới cùng máy) tối đa ngần này. */
    private val CONNECT_WAIT_MS = 8_000L

    internal fun connectBtSync(macAddress: String, markBuiltIn: Boolean = false): Boolean {
        val deviceId = "BT:$macAddress"
        try {
            if (macAddress.isEmpty()) return false

            val adapter = getBluetoothAdapter() ?: return false
            if (!adapter.isEnabled) return false

            // Stop scanning if any
            runCatching { adapter.cancelDiscovery() }

            // Đang có lệnh kết nối KHÔNG đồng bộ tới đúng máy này (khởi động app / trạm in
            // kiểm tra máy tích hợp): chờ nó xong rồi dùng luôn, KHÔNG đóng kết nối nó đang
            // mở — trước đây hai đường đóng kết nối của nhau nên cả hai cùng thất bại.
            val waitUntil = android.os.SystemClock.elapsedRealtime() + CONNECT_WAIT_MS
            while (plugin.pendingConnects.containsKey(deviceId) &&
                android.os.SystemClock.elapsedRealtime() < waitUntil
            ) {
                Thread.sleep(100)
            }
            plugin.connections[deviceId]?.let { existing ->
                if (existing.isConnect) {
                    if (markBuiltIn) {
                        plugin.builtInDeviceIds.add(deviceId)
                        markBuiltInPrinterConfirmed()
                    }
                    return true
                }
            }

            runCatching { plugin.connections[deviceId]?.close() }

            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_BLUETOOTH) ?: return false
            plugin.connections[deviceId] = device
            plugin.connectionTypes[deviceId] = ConnectionType.BT

            val latch = java.util.concurrent.CountDownLatch(1)
            val listener = net.posprinter.IConnectListener { code, _, _ ->
                // Kết nối hỏng / đứt về sau: bỏ khỏi danh sách để lần in sau nối lại, thay
                // vì dùng tiếp kết nối chết. Chỉ đụng tới CHÍNH kết nối này (đã bị thay thì
                // để yên kết nối mới).
                if (code == POSConnect.CONNECT_FAIL || code == POSConnect.CONNECT_INTERRUPT) {
                    if (plugin.connections[deviceId] === device) {
                        plugin.connections.remove(deviceId)
                        plugin.connectionTypes.remove(deviceId)
                    }
                    runCatching { device.close() }
                }
                latch.countDown()
            }
            device.connect(plugin.rawId(deviceId), listener)

            // Bluetooth ảo của máy in tích hợp có lúc mất vài giây mới nối xong (máy vừa
            // thức dậy, dịch vụ máy in vừa khởi động lại): 3,5s cũ hay hết hạn -> NO_CONNECTION.
            latch.await(CONNECT_WAIT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
            val connected = device.isConnect
            if (!connected && plugin.connections[deviceId] === device) {
                plugin.connections.remove(deviceId)
                plugin.connectionTypes.remove(deviceId)
                runCatching { device.close() }
            }
            if (connected && markBuiltIn) {
                plugin.builtInDeviceIds.add(deviceId)
                markBuiltInPrinterConfirmed()
            }
            return connected
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    internal fun isConnectionToBuiltInPrinter(conn: IDeviceConnection): Boolean {
        // Tìm deviceId của connection này trong map
        val deviceId = plugin.connections.entries.find { it.value == conn }?.key ?: return false

        // NGUỒN CHÍNH: connection đã được đánh dấu tường minh là built-in khi kết nối.
        // Chính xác cho mọi hãng, không phụ thuộc tên Bluetooth.
        if (plugin.builtInDeviceIds.contains(deviceId)) return true

        // DỰ PHÒNG theo tên BT: CHỈ áp dụng khi CHƯA có bất kỳ connection nào được đánh
        // dấu built-in tường minh. Nếu đã có (trường hợp bình thường — Sunmi/iMin/Pax
        // luôn được autoConnectBuiltIn() đánh dấu ngay khi mở app), TUYỆT ĐỐI không cho
        // một connection khác khớp thêm qua tên nữa.
        //
        // Lý do: BUILT_IN_NAME_KEYWORDS chứa các từ khóa rất chung ("BluetoothPrinter",
        // "Inner Printer", "Bluetooth Printer"...) — rất nhiều máy in nhiệt Bluetooth
        // ngoài giá rẻ dùng đúng tên mặc định này. Nếu không chặn, khi người dùng connect
        // thêm một máy ngoài như vậy, hàm này trả `true` cho CẢ built-in thật VÀ máy
        // ngoài "trùng tên". Ở PrinterLabelPlugin.resolveConnectionsForPrint,
        // `connections.entries.firstOrNull { isConnectionToBuiltInPrinter(...) }` lấy
        // theo thứ tự lặp của ConcurrentHashMap (KHÔNG đảm bảo built-in được ưu tiên) —
        // nếu vô tình chọn trúng entry máy ngoài, lệnh in "BUILT_IN" bị gửi sang máy
        // ngoài: built-in thật im lặng không in, còn máy ngoài nhận thêm lệnh này CỘNG
        // với lệnh gửi đúng địa chỉ của chính nó nên in ra 2 bản. Đã xảy ra thực tế với
        // máy Sunmi + một máy Bluetooth ngoài tên generic.
        if (plugin.builtInDeviceIds.isNotEmpty()) return false

        if (plugin.connectionTypes[deviceId] != ConnectionType.BT) return false
        try {
            val btAdapter = (plugin.mContext?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            val mac = deviceId.substringAfter("BT:")
            val btDevice = btAdapter?.getRemoteDevice(mac)
            return isBuiltInPrinterName(btDevice?.name)
        } catch (e: Exception) {
            return false
        }
    }
}
