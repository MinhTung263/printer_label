package com.printer.printer_label

import android.content.Context
import android.os.Build
import android.provider.Settings

/**
 * Tên máy người dùng đặt trong Cài đặt (VD "Quầy bar", "Redmi Note 13 Pro").
 * - Android 7.1+: Settings.Global.DEVICE_NAME.
 * - Máy cũ (Android 6, VD Sunmi T1-G) / ROM không ghi DEVICE_NAME: tên Bluetooth
 *   (cũng là tên máy hiện trong Cài đặt), một số ROM lưu "device_name" riêng.
 * Không đọc được thì `null` (app tự dùng hãng + model).
 */
object DeviceNameHelper {
    fun read(ctx: Context): String? {
        val resolver = ctx.contentResolver
        val candidates = mutableListOf<String?>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            candidates += safe { Settings.Global.getString(resolver, Settings.Global.DEVICE_NAME) }
        }
        candidates += safe { Settings.Global.getString(resolver, "device_name") }
        candidates += safe { Settings.System.getString(resolver, "device_name") }
        // Khoá không công khai — app target S+ có thể bị chặn đọc (SecurityException).
        candidates += safe { Settings.Secure.getString(resolver, "bluetooth_name") }
        return candidates.firstOrNull { !it.isNullOrBlank() }?.trim()
    }

    /**
     * Mã phần cứng ổn định của máy — giống nhau giữa các bản build / app trên cùng
     * máy (để một máy chỉ là MỘT Agent):
     * - Android 7.1 trở xuống (VD Sunmi T1-G Android 6): số serial phần cứng.
     * - Android 8+: ANDROID_ID (chung cho các app cùng khoá ký trên máy).
     * `null` khi không đọc được.
     */
    @Suppress("DEPRECATION")
    fun deviceId(ctx: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            val serial = safe { Build.SERIAL }
            if (!serial.isNullOrBlank() && !serial.equals(Build.UNKNOWN, ignoreCase = true)) {
                return "serial:$serial"
            }
        }
        val androidId = safe {
            Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID)
        }
        // Mã lỗi của một số máy Android 2.2 đời đầu — coi như không có.
        if (androidId.isNullOrBlank() || androidId == "9774d56d682e549c") return null
        return "android:$androidId"
    }

    private inline fun safe(block: () -> String?): String? =
        try {
            block()
        } catch (_: Throwable) {
            null
        }
}
