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

    internal val btScanStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            scanEventSink = events
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

    internal fun getBluetoothDevices(result: Result) {
        try {
            val adapter = getBluetoothAdapter()
            if (adapter == null || !adapter.isEnabled) {
                result.error("BT_OFF", "Bluetooth is not enabled", null); return
            }
            val list = adapter.bondedDevices
                .filter { isPrinter(it) }
                .map {
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
        val adapter = getBluetoothAdapter() ?: return
        if (!adapter.isEnabled) {
            scanEventSink?.error("BT_OFF", "Bluetooth is not enabled", null)
            return
        }

        val isDiscovering = try {
            adapter.isDiscovering
        } catch (_: SecurityException) {
            false
        }

        if (isDiscovering) {
            try {
                adapter.cancelDiscovery()
            } catch (_: SecurityException) {}

            // Trì hoãn 500ms để đảm bảo Bluetooth stack hoàn tất việc hủy quét cũ trước khi bắt đầu quét mới
            Handler(Looper.getMainLooper()).postDelayed({
                if (!plugin.isDetached && scanEventSink != null) {
                    actualStartBluetoothScan(adapter)
                }
            }, 500L)
        } else {
            actualStartBluetoothScan(adapter)
        }
    }

    private fun actualStartBluetoothScan(adapter: BluetoothAdapter) {
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
                            if (isPrinter(it)) {
                                val map = mapOf("name" to (it.name ?: "Unknown"), "mac" to it.address)
                                Handler(Looper.getMainLooper()).post {
                                    scanEventSink?.success(map)
                                }
                            }
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
        plugin.mContext?.registerReceiver(receiver, filter)
        btScanReceiver = receiver
        try {
            adapter.startDiscovery()
        } catch (_: SecurityException) {
            scanEventSink?.error("BT_PERMISSION", "Missing BLUETOOTH_SCAN permission", null)
        }
    }

    internal fun stopBluetoothScan() {
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

        // Kiểm tra quyền Bluetooth, nếu chưa được cấp thì hiển thị dialog giải thích trước khi mở Cài đặt
        if (!hasRequiredBluetoothPermissions()) {
            showPermissionDialog {
                openAppSettings()
            }
            result.success(false)
            return
        }

        // 1. Kiểm tra xem đã có kết nối nào đang hoạt động chưa
        val activeConn = plugin.connections.values.firstOrNull { it.isConnect }
        if (activeConn != null) {
            result.success(true)
            return
        }

        val adapter = getBluetoothAdapter() ?: run {
            result.success(false)
            return
        }

        // 2. Tự động bật Bluetooth nếu đang tắt
        if (!adapter.isEnabled) {
            try {
                // Thử bật ngầm trước (hoạt động trên các bản ROM máy POS cũ hoặc đặc quyền)
                val success = adapter.enable()
                if (!success) {
                    // Nếu bật ngầm bị từ chối/thất bại, hiển thị hộp thoại hệ thống xin bật Bluetooth
                    val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    plugin.mContext?.startActivity(intent)
                }
                
                // Khởi chạy vòng lặp Polling để đợi người dùng nhấn "Cho phép" và Bluetooth bật lên thành công
                var attempts = 0
                val handler = Handler(Looper.getMainLooper())
                val runnable = object : Runnable {
                    override fun run() {
                        if (adapter.isEnabled) {
                            findAndConnectBuiltInPrinter(adapter, result)
                        } else if (attempts < 25) { // Tăng lên tối đa 5 giây để người dùng có thời gian click xác nhận
                            attempts++
                            handler.postDelayed(this, 200)
                        } else {
                            result.success(false)
                        }
                    }
                }
                handler.postDelayed(runnable, 200)
                return
            } catch (e: SecurityException) {
                // Nếu bị lỗi bảo mật/quyền khi gọi adapter.enable(), thử hiện hộp thoại xin bật Bluetooth chính thức
                try {
                    val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    plugin.mContext?.startActivity(intent)
                    
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
                    return
                } catch (ex: Exception) {
                    openAppSettings()
                    result.success(false)
                    return
                }
            } catch (e: Exception) {
                result.success(false)
                return
            }
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
                    name.contains("InnerPrinter", ignoreCase = true) || 
                    name.contains("Inner", ignoreCase = true) || 
                    name.contains("Printer", ignoreCase = true)) {
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

    internal fun hasRequiredBluetoothPermissions(): Boolean {
        val context = plugin.mContext ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connectGranted = androidx.core.content.ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_CONNECT
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            val scanGranted = androidx.core.content.ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_SCAN
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            return connectGranted && scanGranted
        }
        return true
    }

    internal fun openAppSettings() {
        val context = plugin.mContext ?: return
        try {
            val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = android.net.Uri.fromParts("package", context.packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            // ignore
        }
    }

    private fun showPermissionDialog(onConfirm: () -> Unit) {
        val currentActivity = plugin.activity ?: return
        currentActivity.runOnUiThread {
            try {
                val builder = android.app.AlertDialog.Builder(currentActivity)
                
                builder.setTitle("Yêu cầu quyền kết nối máy in")
                builder.setMessage("Để sử dụng máy in tích hợp, vui lòng cấp quyền truy cập thiết bị Bluetooth cho ứng dụng tại màn hình Cài đặt tiếp theo.")
                
                builder.setPositiveButton("Đến Cài đặt") { dialog, _ ->
                    dialog.dismiss()
                    onConfirm()
                }
                builder.setNegativeButton("Đóng") { dialog, _ ->
                    dialog.dismiss()
                }
                
                val dialog = builder.create()
                dialog.show()
                
                // Thay đổi màu sắc chữ của các nút bấm sang tông màu xanh Indigo và Slate Grey hiện đại
                dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE)?.setTextColor(android.graphics.Color.parseColor("#4F46E5"))
                dialog.getButton(android.app.AlertDialog.BUTTON_NEGATIVE)?.setTextColor(android.graphics.Color.parseColor("#64748B"))
            } catch (e: Exception) {
                // Nếu bị lỗi luồng/window, chạy trực tiếp action confirm để tránh văng app
                onConfirm()
            }
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
                   name.contains("InnerPrinter", ignoreCase = true) ||
                   name.contains("Printer", ignoreCase = true)
        } catch (e: Exception) {
            return false
        }
    }
}
