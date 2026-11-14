package com.printer.printer_label

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * Dịch vụ chạy nền (foreground service) giữ app in được khi tắt màn hình — dùng cho
 * "trạm in": máy nhận lệnh in từ máy khác (qua mạng) rồi in tới máy in LAN / USB.
 *
 * Khi chạy:
 * - Thông báo cố định (Android bắt buộc với foreground service), chạm để mở app, có nút
 *   dừng ([stopActionLabel]).
 * - Giữ CPU thức (PARTIAL_WAKE_LOCK) và Wi-Fi không ngủ (WifiLock) để lệnh in tới máy
 *   in LAN không bị trễ / rớt khi màn hình tắt.
 *
 * Kiểu dịch vụ `connectedDevice` (Android 14+): app giao tiếp với máy in qua mạng / USB.
 * Không dùng `dataSync` vì Android 15 giới hạn kiểu đó 6 giờ mỗi ngày.
 */
class PrintKeepAliveService : Service() {

    companion object {
        private const val TAG = "PrintKeepAlive"
        private const val CHANNEL_ID = "printer_label_keep_alive"
        private const val NOTIFICATION_ID = 73100
        private const val ACTION_START = "printer_label.keep_alive.START"
        private const val ACTION_STOP_BY_USER = "printer_label.keep_alive.STOP_BY_USER"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_CHANNEL_NAME = "channel_name"
        private const val EXTRA_STOP_LABEL = "stop_label"

        @Volatile
        var isRunning = false
            private set

        /** Gọi khi người dùng bấm nút dừng trên thông báo (để app tắt chế độ trạm). */
        @Volatile
        var onStoppedByUser: (() -> Unit)? = null

        /** Bật hoặc cập nhật nội dung thông báo nếu đang chạy. */
        fun start(
            context: Context,
            title: String,
            text: String,
            channelName: String,
            stopLabel: String?,
        ) {
            val intent = Intent(context, PrintKeepAliveService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
                putExtra(EXTRA_CHANNEL_NAME, channelName)
                putExtra(EXTRA_STOP_LABEL, stopLabel)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            // Tắt chủ động (tắt chế độ Agent): không tự khởi động lại nữa.
            AgentAutoStart.disable(context)
            context.stopService(Intent(context, PrintKeepAliveService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_BY_USER) {
            AgentAutoStart.disable(this)
            onStoppedByUser?.invoke()
            stopSelf()
            return START_NOT_STICKY
        }
        // intent == null: hệ thống tự bật lại dịch vụ sau khi tắt app (START_STICKY)
        // — dùng nội dung đã lưu và mở lại app để phần Dart (máy Agent) chạy lại.
        val restartedBySystem = intent == null
        val saved = AgentAutoStart.savedTexts(this)
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: saved[0] ?: "Printer"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: saved[1] ?: ""
        val channelName = intent?.getStringExtra(EXTRA_CHANNEL_NAME) ?: saved[2] ?: title
        val stopLabel = if (intent != null) intent.getStringExtra(EXTRA_STOP_LABEL) else saved[3]
        if (restartedBySystem && !AgentAutoStart.isEnabled(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!restartedBySystem) AgentAutoStart.save(this, title, text, channelName, stopLabel)

        val notification = buildNotification(title, text, channelName, stopLabel)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // VD Android 12+ không cho bật foreground service khi app đang ở nền.
            Log.e(TAG, "startForeground thất bại: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }
        acquireLocks()
        isRunning = true
        if (restartedBySystem) AgentAutoStart.launchApp(this)
        // Bị hệ thống tắt (thiếu RAM, vuốt tắt app) thì hệ thống bật lại dịch vụ và
        // dịch vụ mở lại app — máy Agent luôn chạy.
        return START_STICKY
    }

    override fun onDestroy() {
        releaseLocks()
        isRunning = false
        super.onDestroy()
    }

    private fun buildNotification(
        title: String,
        text: String,
        channelName: String,
        stopLabel: String?,
    ): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                // IMPORTANCE_LOW: hiện cố định nhưng không kêu / rung.
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_LOW)
                )
            }
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }

        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
            builder.setContentIntent(PendingIntent.getActivity(this, 0, launch, pendingFlags))
        }

        if (!stopLabel.isNullOrEmpty()) {
            val stopIntent = Intent(this, PrintKeepAliveService::class.java).apply {
                action = ACTION_STOP_BY_USER
            }
            val stopPending = PendingIntent.getService(this, 1, stopIntent, pendingFlags)
            @Suppress("DEPRECATION")
            builder.addAction(Notification.Action.Builder(0, stopLabel, stopPending).build())
        }

        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .build()
    }

    @SuppressLint("WakelockTimeout")
    private fun acquireLocks() {
        if (wakeLock?.isHeld != true) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "printer_label:keep_alive")
                .apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
        if (wifiLock?.isHeld != true) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            @Suppress("DEPRECATION")
            wifiLock = wifi?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "printer_label:keep_alive")
                ?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
    }

    private fun releaseLocks() {
        runCatching { if (wakeLock?.isHeld == true) wakeLock?.release() }
        runCatching { if (wifiLock?.isHeld == true) wifiLock?.release() }
        wakeLock = null
        wifiLock = null
    }
}
