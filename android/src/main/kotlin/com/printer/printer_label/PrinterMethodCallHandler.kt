package com.printer.printer_label

import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import net.posprinter.IDeviceConnection

class PrinterMethodCallHandler(private val plugin: PrinterLabelPlugin) : MethodCallHandler {

    @RequiresApi(Build.VERSION_CODES.HONEYCOMB_MR1)
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        try {
            when (call.method) {
                "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
    
                "bluetooth_enabled" -> {
                    result.success(plugin.bluetoothManager.getBluetoothAdapter()?.isEnabled == true)
                }
    
                "checkConnect" -> {
                    val deviceId = call.argument<String>("device_id")
                    if (deviceId != null) {
                        result.success(plugin.isPrinterAvailable(deviceId))
                    } else {
                        // Trả về toàn bộ danh sách kết nối đang hoạt động dưới dạng map { deviceId: true/false }
                        val map = plugin.statusKeys().associateWith { plugin.isPrinterAvailable(it) }
                        result.success(map)
                    }
                }
    
                "disconnect" -> {
                    val deviceId = call.argument<String>("device_id")
                    if (deviceId.isNullOrEmpty()) {
                        plugin.disconnectAll(result)
                    } else {
                        plugin.disconnectPrinter(deviceId, result)
                    }
                }
    
                "connect_lan" -> {
                    val ipAddress = call.argument<String>("ip_address")
                    if (ipAddress.isNullOrEmpty()) {
                        result.success(false)
                        return
                    }
                    plugin.connectNet(ipAddress, result)
                }
    
                "connect_bt" -> {
                    val macAddress = call.argument<String>("mac_address")
                    if (macAddress.isNullOrEmpty()) {
                        result.success(false)
                        return
                    }
                    plugin.bluetoothManager.connectBt(macAddress, result)
                }
    
                "auto_connect_built_in" -> {
                    plugin.isBuiltInPrinterDisabled = false
                    plugin.bluetoothManager.autoConnectBuiltIn(result)
                }
 

                "has_built_in_printer" -> {
                    result.success(hasBuiltInPrinter(plugin.mContext))
                }
    
                "get_built_in_printer_paper_size" -> {
                    result.success(getBuiltInPrinterPaperSize(plugin.mContext))
                }
    
                "get_bluetooth_devices" -> {
                    val filterPrinterOnly = call.argument<Boolean>("filter_printer_only") ?: true
                    plugin.bluetoothManager.getBluetoothDevices(result, filterPrinterOnly)
                }
    
                "print_label" -> {
                    if (UrovoPrinterManager.isUrovoDevice() && !plugin.isBuiltInPrinterDisabled) {
                        plugin.printLabelUrovo(call, result)
                    } else {
                        runPrintJob(call, result) { conn, targetResult ->
                            plugin.printLabel(call, conn, targetResult)
                        }
                    }
                }
    
                "print_text" -> {
                    runPrintJob(call, result) { conn, targetResult ->
                        plugin.printText(call, conn, targetResult)
                    }
                }
    
                "print_barcode" -> {
                    runPrintJob(call, result) { conn, targetResult ->
                        plugin.printBarcode(call, conn, targetResult)
                    }
                }
    
                "print_qrcode" -> {
                    runPrintJob(call, result) { conn, targetResult ->
                        plugin.printQRCode(call, conn, targetResult)
                    }
                }
    
                "print_text_esc" -> {
                    // Máy Urovo tích hợp chỉ in khi được chọn tường minh (device_id == "BUILT_IN").
                    if (isBuiltInTarget(call) && UrovoPrinterManager.isUrovoDevice() && !plugin.isBuiltInPrinterDisabled) {
                        plugin.printTextESCUrovo(call, result)
                    } else {
                        runPrintJob(call, result) { conn, targetResult ->
                            plugin.printThermal.printTextESC(call, conn, targetResult)
                        }
                    }
                }
                "print_barcode_esc" -> {
                    if (isBuiltInTarget(call) && UrovoPrinterManager.isUrovoDevice() && !plugin.isBuiltInPrinterDisabled) {
                        plugin.printBarcodeESCUrovo(call, result)
                    } else {
                        runPrintJob(call, result) { conn, targetResult ->
                            plugin.printThermal.printBarcodeESC(call, conn, targetResult)
                        }
                    }
                }
                "print_qrcode_esc" -> {
                    if (isBuiltInTarget(call) && UrovoPrinterManager.isUrovoDevice() && !plugin.isBuiltInPrinterDisabled) {
                        plugin.printQrCodeESCUrovo(call, result)
                    } else {
                        runPrintJob(call, result) { conn, targetResult ->
                            plugin.printThermal.printQRCodeESC(call, conn, targetResult)
                        }
                    }
                }

                "print_image_esc" -> {
                    if (isBuiltInTarget(call) && UrovoPrinterManager.isUrovoDevice() && !plugin.isBuiltInPrinterDisabled) {
                        plugin.printImageESCUrovo(call, result)
                    } else {
                        runPrintJob(call, result) { conn, targetResult ->
                            val isTargetBuiltIn = plugin.bluetoothManager.isConnectionToBuiltInPrinter(conn)
                            plugin.printThermal.printImageESC(call, conn, targetResult, isTargetBuiltIn)
                        }
                    }
                }

                "open_drawer" -> {
                    try {
                        if (CashBoxManager.isSupportedDevice()) {
                            val success = CashBoxManager.openCashBox(plugin.mContext)
                            if (success) {
                                result.success(true)
                                return
                            }
                        }
                    } catch (t: Throwable) {
                        // Đảm bảo không bao giờ văng app nếu gặp lỗi thiết bị không hỗ trợ
                    }
                    runPrintJob(call, result) { conn, targetResult ->
                        plugin.printThermal.openDrawer(call, conn, targetResult)
                    }
                }

                "identify_lan_printer" -> {
                    val ip = call.argument<String>("ip_address")
                    val port = call.argument<Int>("port") ?: 9100
                    val rawBytes = call.argument<Any>("bytes")
                    val bytes: ByteArray? = when (rawBytes) {
                        is ByteArray -> rawBytes
                        is List<*> -> (rawBytes as List<Int>).map { it.toByte() }.toByteArray()
                        else -> null
                    }
                    if (ip.isNullOrEmpty() || bytes == null) {
                        result.success(false)
                        return
                    }
                    Thread {
                        try {
                            val socket = java.net.Socket()
                            socket.connect(java.net.InetSocketAddress(ip, port), 2000)
                            socket.outputStream.write(bytes)
                            socket.outputStream.flush()
                            Thread.sleep(300)
                            socket.close()
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                result.success(false)
                            }
                        }
                    }.start()
                }

                "check_printer_status" -> {
                    // Hỏi trạng thái thật thì BẮT BUỘC phải có socket. Máy in LAN dùng chung
                    // đã nhả socket sau lần in trước nên phải mở lại, nếu không sẽ báo
                    // "offline" cho một máy in vẫn hoạt động bình thường.
                    var conn = plugin.getConn(call)
                    if (conn == null || !conn.isConnect) {
                        val deviceId = call.argument<String>("device_id")
                        val ip = deviceId?.let { plugin.rawId(it) }
                        // Chỉ mở lại khi đang bật chế độ nhả socket; nếu không, device sẵn có
                        // vẫn dùng được và tạo device mới sẽ làm gián đoạn kết nối đang tốt.
                        if (plugin.releaseLanSocketAfterPrint && ip != null &&
                            plugin.registeredLanPrinters.contains(ip)) {
                            conn = plugin.ensureLanConnectedSync(ip)
                        }
                    }
                    if (conn == null || !conn.isConnect) {
                        result.success("offline")
                        return
                    }
                    val type = call.argument<String>("type") ?: "TSPL"
                    if (type == "ESC") {
                        plugin.checkStatusESC(conn, result)
                    } else {
                        plugin.checkStatusTSPL(conn, result)
                    }
                }
    
                "print_barcode_esc" -> {
                    runPrintJob(call, result) { conn, targetResult ->
                        plugin.printThermal.printBarcodeESC(call, conn, targetResult)
                    }
                }
    
                "print_qrcode_esc" -> {
                    runPrintJob(call, result) { conn, targetResult ->
                        plugin.printThermal.printQRCodeESC(call, conn, targetResult)
                    }
                }
    
                "print_all" -> {
                    val connectionTypeStr = call.argument<String>("connection_type")
                    val filterType = connectionTypeStr?.let { str ->
                        ConnectionType.values().find { it.displayName() == str }
                    }
                    val targetConns = plugin.getFilteredConnections(filterType)
                    if (targetConns.isEmpty()) {
                        result.error("NO_ACTIVE", "No active connections", null); return
                    }
                    when (call.argument<String>("type")) {
                        "TSPL" -> targetConns.forEach { conn -> plugin.printLabel(call, conn, NoOpResult) }
                        "ESC" -> targetConns.forEach { conn ->
                            plugin.printThermal.printImageESC(
                                call,
                                conn,
                                NoOpResult,
                                plugin.bluetoothManager.isConnectionToBuiltInPrinter(conn)
                            )
                        }
    
                        else -> {
                            result.error("UNKNOWN_TYPE", "Unknown print type", null); return
                        }
                    }
                    result.success(true)
                }

                "get_lan_printer_info" -> {
                    val ip = call.argument<String>("ip") ?: ""
                    val port = call.argument<Int>("port") ?: 9100
                    if (ip.isEmpty()) {
                        result.success(null)
                    } else {
                        kotlin.concurrent.thread {
                            val info = LanPrinterProbe.probe(ip, port)
                            Handler(Looper.getMainLooper()).post {
                                result.success(info)
                            }
                        }
                    }
                }

                "scan_net_printers" -> {
                    val devices = mutableListOf<Map<String, Any>>()
                    net.posprinter.POSPrinter.searchNetDevice { udpDevice ->
                        if (udpDevice != null) {
                            val map = mapOf(
                                "mac" to udpDevice.macStr,
                                "ip" to udpDevice.ipStr,
                                "mask" to udpDevice.maskStr,
                                "gateway" to udpDevice.gatewayStr,
                                "dhcp" to udpDevice.isDhcp
                            )
                            devices.add(map)
                        }
                    }
                    // searchNetDevice works synchronously or asynchronously? 
                    // Wait, usually it might be asynchronous. We should probably wait a bit or it returns immediately.
                    // Assuming we wait 1.5 seconds.
                    Handler(Looper.getMainLooper()).postDelayed({
                        result.success(devices)
                    }, 1500)
                }

                "set_net_ip" -> {
                    val mac = call.argument<String>("mac") ?: ""
                    val ip = call.argument<String>("ip") ?: ""
                    val mask = call.argument<String>("mask") ?: "255.255.255.0"
                    val gateway = call.argument<String>("gateway") ?: ""
                    val dhcp = call.argument<Boolean>("dhcp") ?: false
                    val currentIp = call.argument<String>("current_ip") ?: ""

                    // Chạy trên background thread — cả UDP lẫn TCP đều có thể block
                    kotlin.concurrent.thread {
                        // --- Tuyến 1 (Ưu tiên): Xprinter UDP (hoạt động với Xprinter, POS printer) ---
                        // Gửi gói UDP tới cổng 9000, không gửi tới cổng TCP 9100 để tránh máy in bị in rác/in hóa đơn trắng
                        if (mac.isNotEmpty() && ip.isNotEmpty()) {
                            try {
                                net.posprinter.POSPrinter.udpNetConfig(
                                    NetworkConfigHelper.parseMac(mac),
                                    NetworkConfigHelper.parseIp(ip),
                                    NetworkConfigHelper.parseIp(mask),
                                    if (gateway.isNotEmpty()) NetworkConfigHelper.parseIp(gateway)
                                    else ByteArray(4),
                                    dhcp
                                )
                                Handler(Looper.getMainLooper()).post {
                                    result.success(true)
                                }
                                return@thread
                            } catch (_: Exception) {
                                // Nếu UDP lỗi, tiếp tục thử tuyến TCP bên dưới
                            }
                        }

                        // --- Tuyến 2: Chỉ khi không có MAC và có currentIp mới gửi qua TCP 9100 (Epson, Brother) ---
                        var escOk = false
                        if (currentIp.isNotEmpty() && ip.isNotEmpty()) {
                            escOk = NetworkConfigHelper.sendEscIpConfig(
                                currentIp = currentIp,
                                newIp = ip,
                                mask = mask,
                                gateway = gateway,
                                dhcp = dhcp,
                            )
                        }

                        // Trả kết quả về main thread
                        val success = escOk || mac.isNotEmpty()
                        Handler(Looper.getMainLooper()).post {
                            result.success(success)
                        }
                    }
                }
    
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("METHOD_CALL_ERROR", e.message, null)
        }
    }

    /** Lệnh in có chủ đích nhắm tới máy in tích hợp không (device_id == "BUILT_IN"). */
    private fun isBuiltInTarget(call: MethodCall): Boolean =
        call.argument<String>("device_id") == "BUILT_IN"

    private fun runPrintJob(call: MethodCall, result: Result, job: (IDeviceConnection, Result) -> Unit) {
        kotlin.concurrent.thread {
            val conns = plugin.resolveConnectionsForPrint(call)
            if (conns.isEmpty()) {
                Handler(Looper.getMainLooper()).post {
                    result.error("NO_CONNECTION", "No connected printer found", null)
                }
                return@thread
            }

            val validConns = conns
            val total = validConns.size
            val successCount = java.util.concurrent.atomic.AtomicInteger(0)
            val finishCount = java.util.concurrent.atomic.AtomicInteger(0)
            val isResultDelivered = java.util.concurrent.atomic.AtomicBoolean(false)
            val lastError = java.util.concurrent.atomic.AtomicReference<Pair<String, String?>>(Pair("PRINT_ERROR", "Printing failed"))

            validConns.forEach { conn ->
                kotlin.concurrent.thread {
                    // Nhả socket LAN khi job này kết thúc (thành công hay lỗi) để điện thoại
                    // khác kết nối được. Phải nhả trong callback chứ KHÔNG phải sau khi
                    // job() trả về: job() tự chạy luồng nền riêng nên trả về trước khi in
                    // xong — đóng lúc đó sẽ cắt socket giữa lúc đang truyền.
                    // Chỉ nhả đúng 1 lần dù callback có bị gọi nhiều lần.
                    val released = java.util.concurrent.atomic.AtomicBoolean(false)
                    fun releaseOnce() {
                        if (released.compareAndSet(false, true)) plugin.releaseLanSocket(conn)
                    }

                    val jobResult = object : Result {
                        override fun success(res: Any?) {
                            successCount.incrementAndGet()
                            finishCount.incrementAndGet()
                            releaseOnce()

                            // Nếu có ít nhất 1 thiết bị in thành công, phản hồi thành công ngay lập tức cho Flutter
                            if (isResultDelivered.compareAndSet(false, true)) {
                                Handler(Looper.getMainLooper()).post {
                                    result.success(true)
                                }
                            }
                        }

                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            lastError.set(Pair(errorCode, errorMessage))
                            val currentFinished = finishCount.incrementAndGet()
                            releaseOnce()

                            // Chỉ trả về lỗi nếu TẤT CẢ các thiết bị đều thất bại
                            if (currentFinished == total && successCount.get() == 0) {
                                if (isResultDelivered.compareAndSet(false, true)) {
                                    Handler(Looper.getMainLooper()).post {
                                        val err = lastError.get()
                                        result.error(err.first, err.second ?: "Printing failed", null)
                                    }
                                }
                            }
                        }

                        override fun notImplemented() {
                            val currentFinished = finishCount.incrementAndGet()
                            releaseOnce()
                            if (currentFinished == total && successCount.get() == 0) {
                                if (isResultDelivered.compareAndSet(false, true)) {
                                    Handler(Looper.getMainLooper()).post {
                                        val err = lastError.get()
                                        result.error(err.first, err.second ?: "Printing failed", null)
                                    }
                                }
                            }
                        }
                    }
                    try {
                        job(conn, jobResult)
                    } catch (e: Exception) {
                        jobResult.error("PRINT_ERROR", e.message, null)
                    }
                }
            }
        }
    }

    companion object {
        private val NoOpResult = object : Result {
            override fun success(result: Any?) {}
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
            override fun notImplemented() {}
        }
    }
}
