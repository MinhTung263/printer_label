package com.printer.printer_label

import android.util.Log
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import java.util.concurrent.ConcurrentHashMap

/**
 * Chốt chặn cuối trước khi gửi lệnh tem TSPL: máy in HOÁ ĐƠN (ESC/POS) nhận TSPL sẽ
 * in nguyên văn lệnh (`SIZE`, `GAP`, `BITMAP`...) thành ký tự rác, phần ảnh nhị phân
 * thành rác và đẩy giấy liên tục — chạy gần hết cuộn giấy.
 *
 * Tầng Dart đã chọn đường in theo cấu hình (máy hoá đơn in tem dạng ảnh), nhưng cấu
 * hình có thể sai (VD gán chức năng tem cho máy hoá đơn) hoặc có màn in mới quên kiểm
 * tra. Ở đây hỏi CHÍNH máy in (PrinterCapabilities.probe — chỉ tin câu trả lời đúng
 * khung) và chặn khi chắc chắn là máy ESC/POS.
 *
 * - Máy in tích hợp: luôn là ESC/POS -> chặn.
 * - LAN / USB: hỏi một lần rồi nhớ theo thiết bị. Chặn khi XÁC NHẬN ESC/POS mà KHÔNG
 *   xác nhận TSPL. Không rõ (máy không trả lời) -> vẫn in như cũ, không chặn nhầm.
 * - Bluetooth: không hỏi (nhiều máy BT không trả lời, mỗi lần in phí trọn thời gian chờ).
 */
object PrinterLanguageGuard {
    private const val TAG = "PRINTER_PROBE"

    /** deviceKey -> true nếu là máy CHỈ hiểu ESC/POS (không in được tem TSPL). */
    private val receiptOnly = ConcurrentHashMap<String, Boolean>()

    fun isReceiptOnly(plugin: PrinterLabelPlugin, conn: IDeviceConnection, deviceKey: String): Boolean {
        if (plugin.bluetoothManager.isConnectionToBuiltInPrinter(conn)) return true
        val canAsk = conn is LanSocketConnection || conn.getConnectType() == POSConnect.DEVICE_TYPE_USB
        if (!canAsk) return false
        receiptOnly[deviceKey]?.let { return it }
        val languages = PrinterCapabilities.probe(conn, deviceKey)["languages"] as? Map<*, *>
        val escConfirmed = languages?.get("escpos") == "confirmed"
        val tsplConfirmed = languages?.get("tspl") == "confirmed"
        val result = escConfirmed && !tsplConfirmed
        // Nhớ cả "không rõ" để máy không trả lời khỏi bị hỏi lại (tốn ~2s) mỗi lần in.
        receiptOnly[deviceKey] = result
        if (result) Log.w(TAG, "Chặn lệnh tem TSPL tới máy hoá đơn $deviceKey")
        return result
    }

    /** Máy in đổi (VD cùng IP nhưng thay máy khác) -> hỏi lại. */
    fun forget(deviceKey: String) {
        receiptOnly.remove(deviceKey)
    }
}
