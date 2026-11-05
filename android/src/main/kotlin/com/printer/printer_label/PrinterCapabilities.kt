package com.printer.printer_label

import android.os.SystemClock
import android.util.Log
import net.posprinter.IDeviceConnection

object PrinterCapabilities {
    /** `adb logcat -s PRINTER_PROBE` */
    private const val TAG = "PRINTER_PROBE"

    private val ESC_QUERY = byteArrayOf(0x10, 0x04, 0x04)   // DLE EOT 4
    private val TSPL_QUERY = byteArrayOf(0x1B, 0x21, 0x3F)  // <ESC> ! ?

    /** Chờ câu trả lời của MỘT câu hỏi trạng thái. */
    private const val REPLY_TIMEOUT_MS = 600

    /**
     * Xả byte cũ phải dùng timeout THẬT.
     *
     * Bản trước dùng `readSync(1)`, tức `soTimeout = 1ms`, nên gần như không bao
     * giờ hớt được byte đang trên đường về: câu trả lời của lần hỏi thứ nhất bị
     * lần hỏi thứ hai đọc nhầm thành câu trả lời của chính nó, khiến "hỏi hai lần
     * cho chắc" không thêm được chút bằng chứng nào.
     */
    private const val DRAIN_TIMEOUT_MS = 60

    /**
     * `readSync` trả về nguyên một lần đọc socket (tới 1024 byte), không phải đúng
     * một byte. Máy nào gửi kèm byte rác là `size == 1` trượt và bị xếp nhầm thành
     * `unknown`. Nhận tối đa vài byte, nhưng MỌI byte đều phải đúng khung tin.
     */
    private const val MAX_REPLY_BYTES = 4

    fun unknown(deviceId: String, reason: String) = mapOf<String, Any?>(
        "deviceId" to deviceId, "reason" to reason,
        "languages" to mapOf("escpos" to "unknown", "tspl" to "unknown"),
        "features" to listOf("nativeText", "raster", "barcode", "qrCode").associateWith { "not_tested" },
        "receiveBufferBytes" to null
    )

    // `DLE EOT n` trả byte trạng thái có khung cố định: bit0=0, bit1=1, bit4=1, bit7=0.
    private fun escByte(b: Byte) = (b.toInt() and 0x93) == 0x12

    // `<ESC>!?` trả đúng MỘT mã trong bảng trạng thái TSPL. Bản trước nhận mọi byte
    // < 0x80 — tức 128/256 giá trị, lọt cả ký tự ASCII lẫn mẩu byte thừa — nên
    // "tspl: confirmed" không chứng minh được gì, mà 0x80 (other error) lại bị loại.
    private val TSPL_STATUS = intArrayOf(
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
        0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
        0x10, 0x20, 0x80,
    )
    private fun tsplByte(b: Byte) = (b.toInt() and 0xFF) in TSPL_STATUS

    // Strict framing rejects echoed requests, arbitrary strings and delayed
    // multi-byte data. Never turn a timeout/exception into a positive result.
    fun validEsc(data: ByteArray) = framed(data, ::escByte)
    fun validTspl(data: ByteArray) = framed(data, ::tsplByte)

    private fun framed(data: ByteArray, ok: (Byte) -> Boolean) =
        data.isNotEmpty() && data.size <= MAX_REPLY_BYTES && data.all(ok)

    /** Byte thô, để biết máy thật sự trả về gì khi kết luận sai. */
    private fun hex(data: ByteArray?) =
        if (data == null || data.isEmpty()) "-"
        else data.joinToString("") { "%02X".format(it.toInt() and 0xFF) }

    /**
     * Dừng ngay khi bộ đệm đã rỗng — `repeat` là inline nên `return` thoát hẳn hàm.
     * Trả về số byte cũ đã bỏ đi: khác 0 nghĩa là có rác xen giữa các câu hỏi.
     */
    private fun drain(conn: IDeviceConnection): Int {
        var dropped = 0
        repeat(4) {
            val stale = conn.readSync(DRAIN_TIMEOUT_MS) ?: return dropped
            dropped += stale.size
        }
        return dropped
    }

    fun probe(conn: IDeviceConnection, deviceId: String): Map<String, Any?> {
        synchronized(PrinterThermal.lockFor(conn)) {
            val startedMs = SystemClock.elapsedRealtime()
            fun ask(label: String, bytes: ByteArray, valid: (ByteArray) -> Boolean): Boolean {
                // Discard stale unsolicited statuses before each distinct query.
                val dropped = drain(conn)
                if (conn.sendSync(bytes) != bytes.size) {
                    Log.i(TAG, "ask=$label drained=$dropped send=FAILED")
                    return false
                }
                val askedMs = SystemClock.elapsedRealtime()
                val data = conn.readSync(REPLY_TIMEOUT_MS)
                val ok = data != null && valid(data)
                Log.i(
                    TAG,
                    "ask=$label drained=$dropped replyMs=${SystemClock.elapsedRealtime() - askedMs} " +
                        "replyBytes=${data?.size ?: 0} reply=${hex(data)} valid=$ok"
                )
                return ok
            }
            return try {
                // Hỏi TSPL TRƯỚC. Firmware TSPL đọc lệnh theo dòng, nên ba byte lạ
                // `DLE EOT 4` của câu hỏi ESC nằm lại trong bộ đệm lệnh và làm câu
                // `<ESC>!?` ngay sau đó bị phân tích sai — máy tem thật vì thế trả
                // `unknown`, rồi chỉ còn mỗi ESC được xác nhận. Máy in đơn không
                // thiệt gì khi đảo thứ tự: `ESC ! 0x3F` chỉ đổi chế độ chữ, mà mọi
                // phiếu đều mở đầu bằng `ESC @` nên bị đặt lại ngay.
                val tspl = ask("TSPL#1", TSPL_QUERY, ::validTspl) &&
                    ask("TSPL#2", TSPL_QUERY, ::validTspl)
                val esc = ask("ESC#1", ESC_QUERY, ::validEsc) &&
                    ask("ESC#2", ESC_QUERY, ::validEsc)
                val reason = if (esc || tspl) "status_reply" else "no_response"
                Log.i(
                    TAG,
                    "result device=$deviceId escpos=${if (esc) "confirmed" else "unknown"} " +
                        "tspl=${if (tspl) "confirmed" else "unknown"} reason=$reason " +
                        "totalMs=${SystemClock.elapsedRealtime() - startedMs}"
                )
                unknown(deviceId, reason) +
                    ("languages" to mapOf("escpos" to if (esc) "confirmed" else "unknown",
                                          "tspl" to if (tspl) "confirmed" else "unknown"))
            } catch (e: Exception) {
                Log.w(
                    TAG,
                    "result device=$deviceId reason=query_failed " +
                        "totalMs=${SystemClock.elapsedRealtime() - startedMs}",
                    e
                )
                unknown(deviceId, "query_failed")
            }
        }
    }
}
