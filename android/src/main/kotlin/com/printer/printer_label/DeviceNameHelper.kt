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

    private inline fun safe(block: () -> String?): String? =
        try {
            block()
        } catch (_: Throwable) {
            null
        }
}
