package com.printer.printer_label

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * Tự khởi động lại máy Agent (máy nhận lệnh in hộ) khi:
 * - máy vừa bật nguồn / khởi động lại ([AgentBootReceiver]);
 * - app bị hệ thống tắt (thiếu RAM, bị vuốt tắt) — [PrintKeepAliveService] là
 *   START_STICKY nên được hệ thống bật lại, rồi mở lại app.
 *
 * Chỉ khi đang bật chạy nền ([PrintKeepAliveService.start]) và chưa bị người dùng
 * tắt. Mở lại app là đủ: phần Dart (trạm in) tự khôi phục lúc vào app.
 *
 * Android 10+ chặn app tự mở màn hình từ nền, trừ khi có quyền "Hiển thị trên ứng
 * dụng khác" ([canLaunchFromBackground] / [requestPermission]).
 */
internal object AgentAutoStart {
    private const val TAG = "AgentAutoStart"
    private const val PREFS = "printer_label_keep_alive"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(context: Context, title: String, text: String, channelName: String, stopLabel: String?) {
        prefs(context).edit()
            .putBoolean("enabled", true)
            .putString("title", title)
            .putString("text", text)
            .putString("channel_name", channelName)
            .putString("stop_label", stopLabel)
            .apply()
    }

    fun disable(context: Context) {
        prefs(context).edit().putBoolean("enabled", false).apply()
    }

    fun isEnabled(context: Context) = prefs(context).getBoolean("enabled", false)

    /** Nội dung thông báo đã lưu (dùng khi hệ thống tự bật lại dịch vụ). */
    fun savedTexts(context: Context): Array<String?> {
        val p = prefs(context)
        return arrayOf(
            p.getString("title", null),
            p.getString("text", null),
            p.getString("channel_name", null),
            p.getString("stop_label", null),
        )
    }

    fun canLaunchFromBackground(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || Settings.canDrawOverlays(context)

    /** Mở màn cấp quyền "Hiển thị trên ứng dụng khác" cho app. */
    fun requestPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Mở lại app (màn hình chính) — phần Dart khôi phục chế độ Agent. */
    fun launchApp(context: Context): Boolean {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return false
        return try {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            context.startActivity(launch)
            Log.i(TAG, "Đã mở lại app (máy Agent)")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Không mở lại được app: ${e.message}")
            false
        }
    }

    /** Bật lại dịch vụ chạy nền với nội dung đã lưu rồi mở lại app. */
    fun restart(context: Context, reason: String) {
        if (!isEnabled(context)) return
        Log.i(TAG, "Khởi động lại máy Agent ($reason)")
        val t = savedTexts(context)
        runCatching {
            PrintKeepAliveService.start(
                context,
                title = t[0] ?: "Agent",
                text = t[1] ?: "",
                channelName = t[2] ?: (t[0] ?: "Agent"),
                stopLabel = t[3],
            )
        }.onFailure { Log.w(TAG, "Không bật lại được dịch vụ chạy nền: ${it.message}") }
        launchApp(context)
    }
}

/** Máy vừa bật nguồn / app vừa cập nhật: khởi động lại máy Agent nếu đang bật. */
class AgentBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            -> AgentAutoStart.restart(context, intent.action ?: "boot")
        }
    }
}
