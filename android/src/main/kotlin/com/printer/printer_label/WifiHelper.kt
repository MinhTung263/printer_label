package com.printer.printer_label

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * Thông tin Wi-Fi để gợi ý người dùng chuyển sang đúng Wi-Fi của máy in.
 *
 * Đọc tên Wi-Fi (SSID) và danh sách Wi-Fi xung quanh cần app ĐÃ có quyền vị trí và
 * máy đang bật định vị (quy định của Android) — plugin không tự xin quyền; thiếu
 * quyền thì SSID trả `null`, danh sách rỗng.
 */
internal object WifiHelper {

    /** `{ssid, bssid}` của Wi-Fi đang kết nối; `null` khi không có Wi-Fi. */
    @SuppressLint("MissingPermission")
    fun current(context: Context): Map<String, Any?>? {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return null
        @Suppress("DEPRECATION")
        val info = wifi.connectionInfo ?: return null
        @Suppress("DEPRECATION")
        if (info.networkId == -1 && info.ipAddress == 0) return null
        return mapOf(
            "ssid" to cleanSsid(info.ssid),
            "bssid" to info.bssid?.lowercase()?.takeIf { it != "02:00:00:00:00:00" },
        )
    }

    /** Tên các Wi-Fi đang có sóng xung quanh (kết quả quét gần nhất), mạnh trước. */
    @SuppressLint("MissingPermission")
    fun nearby(context: Context): List<String> {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return emptyList()
        return try {
            @Suppress("DEPRECATION")
            wifi.startScan() // Bị giới hạn tần suất; kết quả cũ vẫn dùng được.
            wifi.scanResults
                .sortedByDescending { it.level }
                .mapNotNull {
                    @Suppress("DEPRECATION")
                    cleanSsid(it.SSID)
                }
                .distinct()
        } catch (e: SecurityException) {
            emptyList()
        }
    }

    /**
     * Wi-Fi xung quanh kèm BSSID (MAC bộ phát, KHÔNG đổi khi Wi-Fi đổi tên / mật
     * khẩu) — `[{ssid, bssid, level}]`, sóng mạnh trước. Một tên có thể có nhiều
     * BSSID (2 băng tần, mesh): trả đủ từng điểm phát.
     */
    fun nearbyNetworks(context: Context): List<Map<String, Any?>> {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return emptyList()
        return try {
            @Suppress("DEPRECATION")
            wifi.startScan()
            wifi.scanResults
                .sortedByDescending { it.level }
                .mapNotNull {
                    @Suppress("DEPRECATION")
                    val ssid = cleanSsid(it.SSID) ?: return@mapNotNull null
                    val bssid = it.BSSID?.lowercase()
                        ?.takeIf { b -> b != "02:00:00:00:00:00" }
                        ?: return@mapNotNull null
                    mapOf("ssid" to ssid, "bssid" to bssid, "level" to it.level)
                }
                .distinctBy { it["bssid"] }
        } catch (e: SecurityException) {
            emptyList()
        }
    }

    /** Mở bảng chọn Wi-Fi: dạng nổi trong app (Android 10+), không thì Cài đặt Wi-Fi. */
    fun openSettings(context: Context): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Intent(Settings.Panel.ACTION_WIFI)
        } else {
            Intent(Settings.ACTION_WIFI_SETTINGS)
        }
        if (context !is android.app.Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Bỏ dấu ngoặc kép; `<unknown ssid>` (thiếu quyền vị trí) → `null`. */
    private fun cleanSsid(raw: String?): String? {
        val s = raw?.trim()?.removePrefix("\"")?.removeSuffix("\"")?.trim()
        if (s.isNullOrEmpty() || s == "<unknown ssid>" || s == WifiManager.UNKNOWN_SSID) return null
        return s
    }
}

/**
 * Nối TẠM sang Wi-Fi của máy in để in (máy bán hàng đang ở Wi-Fi khác), xong thì
 * trả về như cũ ([leave]).
 *
 * - Android 10+: xin hệ điều hành nối riêng cho app (`WifiNetworkSpecifier`) — lần đầu
 *   hệ thống hỏi người dùng xác nhận; socket tới máy in tự gắn vào mạng này (xem
 *   `LanSocketConnection.bindToLocalNetwork`). [leave] trả mạng, máy về Wi-Fi cũ.
 * - Android 6–9: chuyển hẳn Wi-Fi bằng `WifiManager`, [leave] chuyển lại Wi-Fi trước đó.
 */
internal object PrinterWifiJoiner {
    private const val TAG = "PrinterWifiJoiner"
    private var callback: android.net.ConnectivityManager.NetworkCallback? = null
    private var previousNetworkId: Int? = null
    private val main = android.os.Handler(android.os.Looper.getMainLooper())

    fun join(
        context: Context,
        ssid: String,
        password: String,
        timeoutMs: Int,
        stay: Boolean,
        done: (Boolean, String?) -> Unit,
    ) {
        leave(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            joinWithSpecifier(context, ssid, password, timeoutMs, done)
        } else {
            joinLegacy(context, ssid, password, timeoutMs, stay, done)
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.Q)
    private fun joinWithSpecifier(
        context: Context,
        ssid: String,
        password: String,
        timeoutMs: Int,
        done: (Boolean, String?) -> Unit,
    ) {
        val cm = context.applicationContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        val spec = android.net.wifi.WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .apply { if (password.isNotEmpty()) setWpa2Passphrase(password) }
            .build()
        val request = android.net.NetworkRequest.Builder()
            .addTransportType(android.net.NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(spec)
            .build()
        var finished = false
        fun finish(ok: Boolean, error: String?) {
            main.post {
                if (finished) return@post
                finished = true
                done(ok, error)
            }
        }
        val cb = object : android.net.ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: android.net.Network) {
                Log.i(TAG, "Đã nối tạm Wi-Fi $ssid")
                // Mọi kết nối của app (kể cả quét / tìm lại máy in theo MAC bằng
                // Dart) đi qua Wi-Fi máy in trong lúc nối tạm; [leave] gỡ ra.
                runCatching { cm.bindProcessToNetwork(network) }
                finish(true, null)
            }

            override fun onUnavailable() {
                Log.w(TAG, "Không nối được Wi-Fi $ssid (từ chối / sai mật khẩu / không có sóng)")
                callback = null
                finish(false, "UNAVAILABLE")
            }
        }
        callback = cb
        try {
            cm.requestNetwork(request, cb, timeoutMs)
        } catch (e: Exception) {
            callback = null
            finish(false, e.message)
        }
    }

    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission")
    private fun joinLegacy(
        context: Context,
        ssid: String,
        password: String,
        timeoutMs: Int,
        stay: Boolean,
        done: (Boolean, String?) -> Unit,
    ) {
        val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        kotlin.concurrent.thread {
            try {
                val quoted = "\"$ssid\""
                if (wm.connectionInfo?.ssid == quoted) {
                    main.post { done(true, null) }
                    return@thread
                }
                // Luôn nhớ Wi-Fi cũ: in xong thì ở lại ([stay], không gọi leave),
                // còn không thấy máy in thì leave() đưa máy về Wi-Fi cũ.
                previousNetworkId = wm.connectionInfo?.networkId?.takeIf { it != -1 }
                val existing = wm.configuredNetworks?.firstOrNull { it.SSID == quoted }
                val id = existing?.networkId ?: wm.addNetwork(
                    android.net.wifi.WifiConfiguration().apply {
                        SSID = quoted
                        if (password.isEmpty()) {
                            allowedKeyManagement.set(android.net.wifi.WifiConfiguration.KeyMgmt.NONE)
                        } else {
                            preSharedKey = "\"$password\""
                        }
                    }
                )
                if (id == -1 || !wm.enableNetwork(id, true)) {
                    main.post { done(false, "ENABLE_FAILED") }
                    return@thread
                }
                wm.reconnect()
                val deadline = System.currentTimeMillis() + timeoutMs
                while (System.currentTimeMillis() < deadline) {
                    val info = wm.connectionInfo
                    if (info?.ssid == quoted && info.ipAddress != 0) {
                        Thread.sleep(500) // chờ định tuyến ổn định
                        main.post { done(true, null) }
                        return@thread
                    }
                    Thread.sleep(300)
                }
                main.post { done(false, "TIMEOUT") }
            } catch (e: Exception) {
                main.post { done(false, e.message) }
            }
        }
    }

    /** Trả mạng đã nối tạm, máy về Wi-Fi trước đó. */
    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission")
    fun leave(context: Context) {
        callback?.let { cb ->
            callback = null
            runCatching {
                val cm = context.applicationContext
                    .getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) cm.bindProcessToNetwork(null)
                cm.unregisterNetworkCallback(cb)
            }
        }
        val prev = previousNetworkId ?: return
        previousNetworkId = null
        runCatching {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wm.enableNetwork(prev, true)
            wm.reconnect()
            // enableNetwork(..., true) tắt các Wi-Fi đã lưu khác — bật lại để máy tự
            // chọn như bình thường.
            wm.configuredNetworks?.forEach { if (it.networkId != prev) wm.enableNetwork(it.networkId, false) }
        }
    }
}
