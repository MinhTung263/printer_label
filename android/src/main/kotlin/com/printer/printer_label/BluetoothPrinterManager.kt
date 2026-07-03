package com.printer.printer_label

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
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

    internal fun isPrinter(device: BluetoothDevice): Boolean {
        try {
            val name = device.name ?: ""
            val lowerName = name.lowercase()
            if (lowerName.isEmpty()) return false

            // Danh sách từ khóa dài tự động khớp nếu xuất hiện ở bất kỳ đâu trong tên (giống iOS)
            val longKeywords = listOf(
                "print", "pos", "thermal", "spp", "label", "barcode", "receipt", "ticket",
                "epson", "star", "citizen", "bixolon", "sewoo", "brother", "tsc", "sprt",
                "hprt", "goojprt", "kiotviet", "sapo", "sunmi", "paperang", "peripage", "niimbot", "zijiang"
            )
            val matchesLong = longKeywords.any { lowerName.contains(it) }

            // Danh sách tiền tố ngắn (khớp ở đầu tên hoặc đi kèm khoảng trắng/gạch ngang/gạch dưới - giống iOS)
            val shortPrefixes = listOf(
                "mpt", "rpp", "rt", "pt", "xp", "gp", "zj", "qs", "nt", "mtp", "cc", "dl", "jc"
            )
            val matchesShort = shortPrefixes.any { prefix ->
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
                    BluetoothDevice.ACTION_FOUND -> {
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
                        device?.let {
                            if (!filterPrinterOnly || isPrinter(it)) {
                                val map = mapOf("name" to (it.name ?: "Unknown"), "mac" to it.address)
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
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
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

    internal fun connectBt(macAddress: String, result: Result) {
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

            plugin.pendingConnects[deviceId] = PrinterLabelPlugin.PendingConnect(result, ConnectionType.BT, deviceId)
            runCatching { plugin.connections[deviceId]?.close() }

            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_BLUETOOTH) ?: run {
                plugin.pendingConnects.remove(deviceId)
                result.error("CREATE_DEVICE_FAIL", "Cannot create device", null)
                return
            }
            plugin.connections[deviceId] = device
            plugin.connectionTypes[deviceId] = ConnectionType.BT
            device.connect(plugin.rawId(deviceId), plugin.makeConnectListener(deviceId))
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
        if (!isBuiltInPrinter()) {
            result.success(false)
            return
        }

        requestConnectPermissions { granted ->
            if (granted) {
                // 1. Kiểm tra xem đã có kết nối nào đang hoạt động chưa
                val activeConn = plugin.connections.values.firstOrNull { it.isConnect }
                if (activeConn != null) {
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
            var printerMac: String? = null
            val pairedDevices: Set<BluetoothDevice>? = adapter.bondedDevices
            pairedDevices?.forEach { device ->
                val name = device.name ?: ""
                if (name.contains("SUNMI", ignoreCase = true) || 
                    name.contains("iMin", ignoreCase = true) || 
                    name.contains("Pax", ignoreCase = true) || 
                    name.contains("Urovo", ignoreCase = true) || 
                    name.contains("InnerPrinter", ignoreCase = true) ||
                    name.contains("Inner Printer", ignoreCase = true) ||
                    name.contains("Builtin Printer", ignoreCase = true) ||
                    name.contains("Built-in Printer", ignoreCase = true)) {
                    printerMac = device.address
                }
            }

            val mac = printerMac ?: run {
                result.success(false)
                return
            }

            // Kết nối bằng hàm connectBt hiện có
            connectBt(mac, result)
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
    }

    internal fun autoConnectBuiltInSync(): Boolean {
        if (!isBuiltInPrinter()) {
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
        var printerMac: String? = null
        val pairedDevices: Set<BluetoothDevice>? = try {
            adapter.bondedDevices
        } catch (_: SecurityException) {
            null
        }
        pairedDevices?.forEach { device ->
            val name = try { device.name ?: "" } catch (_: SecurityException) { "" }
            if (name.contains("SUNMI", ignoreCase = true) || 
                name.contains("iMin", ignoreCase = true) || 
                name.contains("Pax", ignoreCase = true) || 
                name.contains("Urovo", ignoreCase = true) || 
                name.contains("InnerPrinter", ignoreCase = true) ||
                name.contains("Inner Printer", ignoreCase = true) ||
                name.contains("Builtin Printer", ignoreCase = true) ||
                name.contains("Built-in Printer", ignoreCase = true)) {
                printerMac = device.address
            }
        }

        val mac = printerMac ?: return false
        
        // Kết nối đồng bộ bằng CountDownLatch
        return connectBtSync(mac)
    }

    internal fun connectBtSync(macAddress: String): Boolean {
        val deviceId = "BT:$macAddress"
        try {
            if (macAddress.isEmpty()) return false

            val adapter = getBluetoothAdapter() ?: return false
            if (!adapter.isEnabled) return false

            // Stop scanning if any
            runCatching { adapter.cancelDiscovery() }

            runCatching { plugin.connections[deviceId]?.close() }

            val device = POSConnect.createDevice(POSConnect.DEVICE_TYPE_BLUETOOTH) ?: return false
            plugin.connections[deviceId] = device
            plugin.connectionTypes[deviceId] = ConnectionType.BT

            val latch = java.util.concurrent.CountDownLatch(1)
            val listener = net.posprinter.IConnectListener { code, _, _ ->
                latch.countDown()
            }
            device.connect(plugin.rawId(deviceId), listener)
            
            // Chờ tối đa 3.5 giây cho việc kết nối hoàn tất
            latch.await(3500, java.util.concurrent.TimeUnit.MILLISECONDS)
            return device.isConnect
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    internal fun isConnectionToBuiltInPrinter(conn: IDeviceConnection): Boolean {
        // Tìm deviceId của connection này trong map
        val deviceId = plugin.connections.entries.find { it.value == conn }?.key ?: return false
        
        // Nếu không phải kết nối Bluetooth thì chắc chắn không phải máy in tích hợp ảo
        if (plugin.connectionTypes[deviceId] != ConnectionType.BT) return false
        
        // Kiểm tra tên Bluetooth device xem có phải máy in ảo tích hợp không
        try {
            val btAdapter = (plugin.mContext?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            val mac = deviceId.substringAfter("BT:")
            val btDevice = btAdapter?.getRemoteDevice(mac)
            val name = btDevice?.name ?: ""
            return name.contains("SUNMI", ignoreCase = true) || 
                   name.contains("iMin", ignoreCase = true) || 
                   name.contains("Pax", ignoreCase = true) || 
                   name.contains("Urovo", ignoreCase = true) || 
                   name.contains("InnerPrinter", ignoreCase = true) ||
                   name.contains("Inner Printer", ignoreCase = true) ||
                   name.contains("Builtin Printer", ignoreCase = true) ||
                   name.contains("Built-in Printer", ignoreCase = true)
        } catch (e: Exception) {
            return false
        }
    }
}
