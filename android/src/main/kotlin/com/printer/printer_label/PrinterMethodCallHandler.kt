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
                        result.success(plugin.connections[deviceId]?.isConnect ?: false)
                    } else {
                        // Trả về toàn bộ danh sách kết nối đang hoạt động dưới dạng map { deviceId: true/false }
                        val map = plugin.connections.mapValues { (_, conn) -> conn.isConnect }
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
 
                "open_permission_settings" -> {
                    plugin.bluetoothManager.openAppSettings()
                    result.success(true)
                }
    
                "has_built_in_printer" -> {
                    result.success(hasBuiltInPrinter(plugin.mContext))
                }
    
                "get_built_in_printer_paper_size" -> {
                    result.success(getBuiltInPrinterPaperSize(plugin.mContext))
                }
    
                "get_bluetooth_devices" -> {
                    plugin.bluetoothManager.getBluetoothDevices(result)
                }
    
                "print_label" -> {
                    plugin.toast("[print_label] nhận lệnh in")
                    val conn = plugin.resolveConn(call, result) ?: return
                    plugin.printLabel(call, conn, result)
                }
    
                "print_text" -> {
                    val conn = plugin.resolveConn(call, result) ?: return
                    plugin.printText(call, conn, result)
                }
    
                "print_text_esc" -> {
                    val conn = plugin.resolveConn(call, result) ?: return
                    plugin.printThermal.printTextESC(call, conn, result)
                }
    
                "print_barcode" -> {
                    val conn = plugin.resolveConn(call, result) ?: return
                    plugin.printBarcode(call, conn, result)
                }
    
                "print_qrcode" -> {
                    val conn = plugin.resolveConn(call, result) ?: return
                    plugin.printQRCode(call, conn, result)
                }
    
                "print_image_esc" -> {
                    val conn = plugin.resolveConn(call, result) ?: return
                    val isTargetBuiltIn = plugin.bluetoothManager.isConnectionToBuiltInPrinter(conn)
                    plugin.printThermal.printImageESC(call, conn, result, isTargetBuiltIn)
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
                    val conn = plugin.resolveConn(call, result) ?: return
                    plugin.printThermal.printBarcodeESC(call, conn, result)
                }
    
                "print_qrcode_esc" -> {
                    val conn = plugin.resolveConn(call, result) ?: return
                    plugin.printThermal.printQRCodeESC(call, conn, result)
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

    companion object {
        private val NoOpResult = object : Result {
            override fun success(result: Any?) {}
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
            override fun notImplemented() {}
        }
    }
}
