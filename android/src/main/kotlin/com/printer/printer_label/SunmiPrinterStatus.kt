package com.printer.printer_label

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import android.os.Parcel
import android.util.Log
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Trạng thái máy in TÍCH HỢP Sunmi, hỏi qua dịch vụ InnerPrinterService
 * (`woyou.aidlservice.jiuiv5`).
 *
 * Máy in tích hợp được in qua Bluetooth ảo "InnerPrinter" — đường này không trả
 * lời lệnh hỏi trạng thái ESC/POS, nên trước đây hết giấy / mở nắp vẫn gửi bill:
 * máy giữ dữ liệu, thay giấy xong mới in -> nhân viên đã in lại thì ra 2 phiếu.
 * Hỏi trạng thái trước khi in để báo ngay (giống máy LAN/USB).
 *
 * Gọi thẳng binder bằng mã giao dịch thay vì sinh lớp từ file AIDL: mã giao dịch
 * AIDL tính theo THỨ TỰ khai báo, và file `IWoyouService.aidl` trong plugin
 * không đúng thứ tự bản gốc (vị trí 7 của dịch vụ thật là `getPrinterVersion`
 * trả chuỗi -> đọc nhầm ra độ dài chuỗi = 5 = "quá nóng"). Mã dưới đây đã đối
 * chiếu với dịch vụ thật (SunmiPrinterService 4.13.13 trên T1-G): bảng
 * `onTransact` gọi hàm trả 505/507/3/7/8… ở mã 33.
 *
 * Mã của `updatePrinterState()`: 1 bình thường, 2 đang khởi động, 3 lỗi giao
 * tiếp, 4 hết giấy, 5 quá nóng, 6 mở nắp, 7 lỗi dao cắt, 8 dao cắt đã phục hồi,
 * 9 không thấy vạch đen, 505 không có máy in, 507 lỗi cập nhật firmware.
 * Không hỏi được (máy không phải Sunmi, dịch vụ không có / bản cũ) -> null:
 * vẫn in như cũ, không chặn.
 */
object SunmiPrinterStatus {
    const val OUT_OF_PAPER = 4
    const val OVERHEATED = 5
    const val COVER_OPEN = 6

    private const val TAG = "SunmiPrinterStatus"
    private const val SERVICE_PACKAGE = "woyou.aidlservice.jiuiv5"
    private const val SERVICE_ACTION = "woyou.aidlservice.jiuiv5.IWoyouService"
    private const val DESCRIPTOR = "woyou.aidlservice.jiuiv5.IWoyouService"

    /** `IBinder.FIRST_CALL_TRANSACTION + 32` — hàm thứ 33 `int updatePrinterState()`. */
    private const val TRANSACTION_UPDATE_PRINTER_STATE = IBinder.FIRST_CALL_TRANSACTION + 32

    /** Mã hợp lệ của `updatePrinterState()`; giá trị khác = dịch vụ lạ -> bỏ qua. */
    private val KNOWN_STATES = setOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 505, 507)

    /** Chờ kết nối dịch vụ lần đầu tối đa ngần này — không làm chậm lệnh in. */
    private const val BIND_TIMEOUT_MS = 600L

    @Volatile private var appContext: Context? = null
    @Volatile private var binder: IBinder? = null
    @Volatile private var bindLatch: CountDownLatch? = null
    @Volatile private var bound = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            binder = service
            bindLatch?.countDown()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            binder = null
            bound = false
        }
    }

    /** Gọi một lần khi plugin gắn vào engine. */
    fun init(context: Context?) {
        appContext = context?.applicationContext
    }

    private fun isSunmi(): Boolean =
        Build.MANUFACTURER.contains("sunmi", ignoreCase = true) ||
            Build.BRAND.contains("sunmi", ignoreCase = true)

    /** Mã trạng thái hiện tại, hoặc null nếu không hỏi được. Gọi từ luồng NỀN. */
    fun query(): Int? {
        if (!isSunmi()) return null
        val b = binder ?: bind() ?: return null
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        return try {
            data.writeInterfaceToken(DESCRIPTOR)
            if (!b.transact(TRANSACTION_UPDATE_PRINTER_STATE, data, reply, 0)) return null
            reply.readException()
            reply.readInt().takeIf { it in KNOWN_STATES }
        } catch (e: Exception) {
            Log.w(TAG, "Không hỏi được trạng thái máy in tích hợp: ${e.message}")
            binder = null
            null
        } finally {
            reply.recycle()
            data.recycle()
        }
    }

    @Synchronized
    private fun bind(): IBinder? {
        binder?.let { return it }
        val ctx = appContext ?: return null
        val latch = CountDownLatch(1)
        bindLatch = latch
        if (!bound) {
            bound = try {
                ctx.bindService(
                    Intent(SERVICE_ACTION).setPackage(SERVICE_PACKAGE),
                    connection,
                    Context.BIND_AUTO_CREATE
                )
            } catch (e: Exception) {
                Log.w(TAG, "Không kết nối được dịch vụ máy in Sunmi: ${e.message}")
                false
            }
            if (!bound) return null
        }
        latch.await(BIND_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        return binder
    }
}
