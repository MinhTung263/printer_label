package com.printer.printer_label

import android.os.SystemClock
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
 * - LAN / USB: hỏi máy in, nhớ kết quả theo thiết bị. Chặn khi XÁC NHẬN ESC/POS mà
 *   KHÔNG xác nhận TSPL.
 * - Máy không trả lời: thường do máy ĐANG BẬN (vừa nhận job / socket trước vừa đóng —
 *   print server Wi-Fi của Epson mất vài trăm ms mới nhận kết nối mới). Chờ rồi hỏi
 *   lại một lần; vẫn không rõ thì xét hãng theo MAC (máy LAN) và chỉ nhớ "không rõ"
 *   trong [UNKNOWN_TTL_MS]. Trước đây "không rõ" được nhớ VĨNH VIỄN là "không chặn":
 *   một lần hỏi trúng lúc máy bận là mọi lệnh tem sau đó tới máy hoá đơn đều in rác.
 * - Bluetooth: không hỏi (nhiều máy BT không trả lời, mỗi lần in phí trọn thời gian chờ).
 */
object PrinterLanguageGuard {
    private const val TAG = "PRINTER_PROBE"

    /** Chờ máy in rảnh trước khi hỏi lại khi lần đầu không có trả lời. */
    private const val RETRY_DELAY_MS = 400L

    /** "Không rõ" chỉ nhớ ngần này rồi hỏi lại — không phí ~1,3s mỗi lần in tem. */
    private const val UNKNOWN_TTL_MS = 60_000L

    /** Hãng chỉ làm máy in hoá đơn ESC/POS, không có máy in tem TSPL. */
    private val RECEIPT_ONLY_VENDORS = setOf("Epson")

    private class Verdict(val receiptOnly: Boolean, val confirmed: Boolean, val atMs: Long)

    private val verdicts = ConcurrentHashMap<String, Verdict>()

    fun isReceiptOnly(plugin: PrinterLabelPlugin, conn: IDeviceConnection, deviceKey: String): Boolean {
        if (plugin.bluetoothManager.isConnectionToBuiltInPrinter(conn)) return true
        val isLan = conn is LanSocketConnection
        val canAsk = isLan || conn.getConnectType() == POSConnect.DEVICE_TYPE_USB
        if (!canAsk) return false

        val now = SystemClock.elapsedRealtime()
        verdicts[deviceKey]?.let { cached ->
            if (cached.confirmed || now - cached.atMs < UNKNOWN_TTL_MS) return cached.receiptOnly
        }

        var languages = askLanguages(conn, deviceKey)
        if (languages.esc == null) {
            // Không trả lời: máy có thể đang bận -> chờ rồi hỏi lại một lần.
            Thread.sleep(RETRY_DELAY_MS)
            languages = askLanguages(conn, deviceKey)
        }

        val esc = languages.esc
        val verdict = when {
            esc != null -> Verdict(receiptOnly = esc && !languages.tspl, confirmed = true, atMs = now)
            // Vẫn không trả lời: máy LAN của hãng chỉ làm máy hoá đơn -> chặn.
            isLan && vendorOf(deviceKey) in RECEIPT_ONLY_VENDORS ->
                Verdict(receiptOnly = true, confirmed = true, atMs = now)
            else -> Verdict(receiptOnly = false, confirmed = false, atMs = now)
        }
        verdicts[deviceKey] = verdict
        if (verdict.receiptOnly) Log.w(TAG, "Chặn lệnh tem TSPL tới máy hoá đơn $deviceKey")
        return verdict.receiptOnly
    }

    /** Máy in đổi (VD cùng IP nhưng thay máy khác) -> hỏi lại. */
    fun forget(deviceKey: String) {
        verdicts.remove(deviceKey)
    }

    /**
     * Kết quả hỏi ngôn ngữ lệnh: [esc] = null khi máy không trả lời câu nào (không rõ);
     * ngược lại [esc]/[tspl] = máy có xác nhận ngôn ngữ đó hay không.
     */
    private class Languages(val esc: Boolean?, val tspl: Boolean)

    private fun askLanguages(conn: IDeviceConnection, deviceKey: String): Languages {
        val languages = PrinterCapabilities.probe(conn, deviceKey)["languages"] as? Map<*, *>
        val esc = languages?.get("escpos") == "confirmed"
        val tspl = languages?.get("tspl") == "confirmed"
        return if (esc || tspl) Languages(esc, tspl) else Languages(null, false)
    }

    /** Hãng máy in LAN tra theo MAC trong bảng ARP (`LAN:<ip>[:port]`); null nếu không rõ. */
    private fun vendorOf(deviceKey: String): String? = try {
        val ip = deviceKey.removePrefix("LAN:").substringBefore(':')
        LanPrinterProbe.getVendorFromMac(LanPrinterProbe.getMacFromArp(ip))
    } catch (e: Exception) {
        null
    }
}
