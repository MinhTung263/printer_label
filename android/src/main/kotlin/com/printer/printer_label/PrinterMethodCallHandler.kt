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
                        result.success(plugin.isConnectionActive(deviceId))
                    } else {
                        // Trả về toàn bộ danh sách kết nối đang hoạt động dưới dạng map { deviceId: true/false }
                        val map = plugin.connections.keys.associateWith { plugin.isConnectionActive(it) }
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
                    runPrintJob(call, result) { conn, targetResult ->
                        plugin.printLabel(call, conn, targetResult)
                    }
                }
    
                "print_text" -> {
                    runPrintJob(call, result) { conn, targetResult ->
                        plugin.printText(call, conn, targetResult)
                    }
                }
    
                "print_text_esc" -> {
                    runPrintJob(call, result) { conn, targetResult ->
                        plugin.printThermal.printTextESC(call, conn, targetResult)
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
    
                "print_image_esc" -> {
                    runPrintJob(call, result) { conn, targetResult ->
                        val isTargetBuiltIn = plugin.bluetoothManager.isConnectionToBuiltInPrinter(conn)
                        plugin.printThermal.printImageESC(call, conn, targetResult, isTargetBuiltIn)
                    }
                }
    
                "check_printer_status" -> {
                    val conn = plugin.getConn(call)
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
    
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("METHOD_CALL_ERROR", e.message, null)
        }
    }

    private fun runPrintJob(call: MethodCall, result: Result, job: (IDeviceConnection, Result) -> Unit) {
        kotlin.concurrent.thread {
            val conns = plugin.resolveConnectionsForPrint(call)
            if (conns.isEmpty()) {
                Handler(Looper.getMainLooper()).post {
                    result.error("NO_CONNECTION", "No connected printer found", null)
                }
                return@thread
            }

            val total = conns.size
            val successCount = java.util.concurrent.atomic.AtomicInteger(0)
            val finishCount = java.util.concurrent.atomic.AtomicInteger(0)
            val isResultDelivered = java.util.concurrent.atomic.AtomicBoolean(false)
            val lastError = java.util.concurrent.atomic.AtomicReference<Pair<String, String?>>(Pair("PRINT_ERROR", "Printing failed"))

            conns.forEach { conn ->
                kotlin.concurrent.thread {
                    val jobResult = object : Result {
                        override fun success(res: Any?) {
                            successCount.incrementAndGet()
                            finishCount.incrementAndGet()
                            
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
