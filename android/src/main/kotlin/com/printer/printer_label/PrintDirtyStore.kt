package com.printer.printer_label

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * Sổ ghi nhớ "máy in này có thể đang dở một lệnh ảnh", LƯU BỀN xuống bộ nhớ máy.
 *
 * Vì sao cần: ảnh bill đi bằng lệnh raster `GS v 0` khai báo trước số byte. Lần in trước đứt
 * giữa chừng (rút dây, rớt Wi-Fi, tắt máy in, app bị kill / crash / ANR) thì máy in vẫn chờ
 * nốt phần ảnh còn thiếu và NUỐT bill kế tiếp làm dữ liệu ảnh -> ra ký tự rác, giấy chạy dài.
 * Cách gỡ: lần kết nối / in kế tiếp tới máy đó, xả bằng [FLUSH_BYTES] (0x00 lấp phần ảnh còn
 * thiếu + `ESC @`) rồi mới gửi bill.
 *
 * Trước đây cờ này chỉ nằm trong bộ nhớ và chỉ bật ở đường lỗi ghi, nên app bị kill giữa chừng
 * (hoặc hot restart khi debug) là mất cờ, bill sau ra rác. Giờ theo kiểu "ghi trước":
 *  - [mark] TRƯỚC khi gửi byte đầu của một lệnh in (ghi đĩa ngay, đồng bộ);
 *  - [clear] chỉ khi cả lệnh đã gửi xong;
 *  - mọi gián đoạn giữa hai điểm đó (lỗi, kill, crash) đều để cờ lại.
 *
 * Khoá là `IDeviceConnection.getConnectInfo()` (IP:cổng, MAC Bluetooth, tên thiết bị USB).
 */
object PrintDirtyStore {
    private const val TAG = "PRINT_DIRTY"
    private const val PREFS = "printer_label_print_dirty"
    private const val KEY = "dirty_keys"

    /**
     * Số byte 0x00 xả. Một dải `GS v 0` tối đa 128 dòng; mỗi dòng tối đa 128 byte (1024 chấm,
     * đủ máy 112mm) -> 16384 byte lấp được MỌI phần ảnh còn thiếu của một dải. 0x00 thừa sau khi
     * lấp xong là lệnh rỗng, máy in bỏ qua.
     */
    const val FLUSH_ZEROS = 128 * 128

    /** `FLUSH_ZEROS` byte 0x00 rồi `ESC @` (đưa máy về trạng thái đầu). */
    val FLUSH_BYTES: ByteArray = ByteArray(FLUSH_ZEROS + 2).also {
        it[FLUSH_ZEROS] = 0x1B
        it[FLUSH_ZEROS + 1] = 0x40
    }

    /** Chờ máy nuốt xong phần xả trước khi gửi bill. */
    const val SETTLE_MS = 50L

    private val keys: MutableSet<String> = ConcurrentHashMap.newKeySet()

    @Volatile
    private var prefs: SharedPreferences? = null

    /** Gọi khi plugin gắn vào engine (idempotent). Nạp các khoá đã lưu từ lần chạy trước. */
    @JvmStatic
    fun init(context: Context?) {
        if (prefs != null || context == null) return
        synchronized(this) {
            if (prefs != null) return
            val p = runCatching {
                context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            }.getOrNull() ?: return
            runCatching { p.getStringSet(KEY, emptySet())?.let { keys.addAll(it) } }
            prefs = p
            if (keys.isNotEmpty()) Log.i(TAG, "Còn ${keys.size} máy in đánh dấu in dở từ lần chạy trước")
        }
    }

    @JvmStatic
    fun isDirty(key: String?): Boolean = !key.isNullOrBlank() && keys.contains(key)

    /** Đánh dấu và ghi đĩa NGAY (đồng bộ): app bị kill ngay sau đó vẫn còn cờ. */
    @JvmStatic
    fun mark(key: String?) {
        if (key.isNullOrBlank()) return
        if (keys.add(key)) persist(sync = true)
    }

    /** Bỏ đánh dấu. Mất lần ghi này chỉ gây thêm một lần xả thừa, vô hại -> ghi bất đồng bộ. */
    @JvmStatic
    fun clear(key: String?) {
        if (key.isNullOrBlank()) return
        if (keys.remove(key)) persist(sync = false)
    }

    private fun persist(sync: Boolean) {
        val editor = prefs?.edit() ?: return
        editor.putStringSet(KEY, HashSet(keys))
        runCatching { if (sync) editor.commit() else editor.apply() }
            .onFailure { Log.w(TAG, "Không ghi được sổ in dở: ${it.message}") }
    }

    /** Chỉ dùng cho test: xoá sạch trạng thái trong bộ nhớ. */
    @JvmStatic
    internal fun resetForTest() {
        keys.clear()
        prefs = null
    }
}
