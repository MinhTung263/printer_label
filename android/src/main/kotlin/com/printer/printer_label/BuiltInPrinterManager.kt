package com.printer.printer_label

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

/**
 * Nhận diện máy in tích hợp của máy POS Android — luật ở [BuiltInPrinterRules]
 * (thuần, có test), file này chỉ đọc dữ liệu từ Android.
 *
 * - Dòng máy ĐÃ BIẾT (hãng / model / mã ROM / gói dịch vụ in): nhận ngay.
 * - Máy CHƯA BIẾT: nhận khi thấy máy in Bluetooth ẢO trong danh sách đã ghép
 *   đôi (MAC giả theo dãy số, chưa từng dò qua sóng, tên máy in nội bộ) — cần
 *   quyền Bluetooth và Bluetooth đang bật mới đọc được danh sách.
 */

/** Đã thấy (hoặc đã kết nối được) máy in ảo trên máy này — nhớ trong phiên chạy. */
@Volatile
private var virtualPrinterConfirmed = false

@Volatile
private var cachedPackages: List<String>? = null

/** Đánh dấu máy này chắc chắn có máy in tích hợp (vừa kết nối được). */
internal fun markBuiltInPrinterConfirmed() {
    virtualPrinterConfirmed = true
}

private fun installedPrinterPackages(context: Context?): List<String> {
    cachedPackages?.let { return it }
    val pm = context?.packageManager ?: return emptyList()
    val found = BuiltInPrinterRules.HINT_PACKAGES
        .filter { pkg -> runCatching { pm.getPackageInfo(pkg, 0) }.isSuccess }
    cachedPackages = found
    return found
}

/** Mức nhận diện của thiết bị (hãng, model, mã ROM, gói dịch vụ in). */
internal fun builtInTier(context: Context? = null): BuiltInPrinterRules.Tier =
    BuiltInPrinterRules.tierOf(
        manufacturer = Build.MANUFACTURER ?: "",
        model = Build.MODEL ?: "",
        others = listOf(Build.BRAND ?: "", Build.PRODUCT ?: "", Build.DEVICE ?: ""),
        display = Build.DISPLAY ?: "",
        // Chưa có context: dùng danh sách gói đã đọc lần trước (nếu có).
        packages = if (context != null) installedPrinterPackages(context) else (cachedPackages ?: emptyList()),
    )

/**
 * Máy này CÓ máy in tích hợp in được: dòng máy đã biết, hoặc đã thấy máy in ảo.
 * (Không cần context — dùng ở các chốt trong plugin.)
 */
fun isBuiltInPrinter(): Boolean =
    builtInTier() == BuiltInPrinterRules.Tier.VERIFIED || virtualPrinterConfirmed

/**
 * Máy này CÓ THỂ có máy in tích hợp — rộng hơn [isBuiltInPrinter]: gồm cả máy có
 * dấu hiệu là máy POS nhưng chưa xác minh. Dùng để quyết định có nên xin quyền
 * Bluetooth / thử tự kết nối không.
 */
internal fun mayHaveBuiltInPrinter(context: Context?): Boolean =
    builtInTier(context) != BuiltInPrinterRules.Tier.UNKNOWN ||
        virtualPrinterConfirmed ||
        findBuiltInBondedDevice(context) != null

/**
 * Kênh `hasBuiltInPrinter`: "có thể có máy in tích hợp" ([mayHaveBuiltInPrinter]).
 * App dùng để xin quyền Bluetooth rồi hỏi lại [getBuiltInPrinterPaperSize] (chắc
 * chắn) — máy POS lạ vẫn được nhận sau khi có quyền.
 */
fun hasBuiltInPrinter(context: Context?): Boolean = mayHaveBuiltInPrinter(context)

/** Thiết bị Bluetooth đã ghép đôi dưới dạng dữ liệu thô cho [BuiltInPrinterRules]. */
internal fun BluetoothDevice.toBonded(printerLike: Boolean): BuiltInPrinterRules.Bonded =
    BuiltInPrinterRules.Bonded(
        mac = address ?: "",
        name = try { name } catch (_: SecurityException) { null },
        type = try { type } catch (_: SecurityException) { -1 },
        imaging = try {
            bluetoothClass?.majorDeviceClass == BluetoothClass.Device.Major.IMAGING
        } catch (_: SecurityException) { false },
        printerLike = printerLike,
    )

/** Tên Bluetooth giống máy in nói chung (bản gọn của `isPrinter`, không cần plugin). */
private fun looksLikePrinterName(name: String?): Boolean {
    val n = name?.lowercase() ?: return false
    return n.contains("print") || n.contains("pos") || n.contains("thermal")
}

/**
 * Máy in ảo trong danh sách Bluetooth đã ghép đôi (theo mức thiết bị); `null`
 * khi không có / chưa có quyền Bluetooth / Bluetooth đang tắt (danh sách rỗng).
 */
internal fun findBuiltInBondedDevice(
    context: Context?,
    adapter: BluetoothAdapter? = null,
): BuiltInPrinterRules.Bonded? {
    val ctx = context ?: return null
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
        androidx.core.content.ContextCompat.checkSelfPermission(
            ctx,
            android.Manifest.permission.BLUETOOTH_CONNECT,
        ) != PackageManager.PERMISSION_GRANTED
    ) {
        return null
    }
    return try {
        val bt = adapter
            ?: (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            ?: return null
        val bonded = bt.bondedDevices?.map { d ->
            d.toBonded(printerLike = looksLikePrinterName(try { d.name } catch (_: SecurityException) { null }))
        } ?: return null
        val picked = BuiltInPrinterRules.pick(bonded, builtInTier(ctx))
        // Máy lạ mà có máy in ảo "chắc" → từ giờ coi là máy có máy in tích hợp.
        if (picked != null && BuiltInPrinterRules.isStrong(picked)) virtualPrinterConfirmed = true
        picked
    } catch (_: Exception) {
        null
    }
}

/**
 * Khổ giấy máy in tích hợp (58 / 80mm); 0 khi máy KHÔNG (chắc chắn) có máy in
 * tích hợp — dòng máy đã biết, hoặc đã thấy máy in ảo trong Bluetooth.
 */
fun getBuiltInPrinterPaperSize(context: Context?): Int {
    // Đọc gói dịch vụ in (cần context) + dò máy in ảo trước khi kết luận.
    val tier = builtInTier(context)
    if (tier != BuiltInPrinterRules.Tier.VERIFIED &&
        !virtualPrinterConfirmed &&
        findBuiltInBondedDevice(context)?.let { BuiltInPrinterRules.isStrong(it) } != true
    ) {
        return 0
    }

    // 1. Thuộc tính hệ thống của Sunmi: "0" = 80mm, "1" = 58mm.
    val sunmiPaperProp = getSystemProperty("ro.sunmi.printer.paper")
    if (sunmiPaperProp == "0") return 80
    if (sunmiPaperProp == "1") return 58

    val sunmiHardwareProp = getSystemProperty("ro.sunmi.hardware.printer")
    if (sunmiHardwareProp.contains("80")) return 80
    if (sunmiHardwareProp.contains("58")) return 58

    // 2. Nhóm model máy để bàn đã biết (khổ 80mm).
    val model = Build.MODEL.lowercase()
    val isDesktopModel = model.contains("t1") ||
                         model.contains("t2") ||
                         model.contains("s2") ||
                         model.contains("d2") ||
                         model.contains("d3") ||
                         model.contains("d4") ||
                         model.contains("swan") ||
                         model.contains("mix")
    if (isDesktopModel) return 80

    // 3. Máy chưa biết model: máy để bàn màn lớn (cạnh ngắn >= 720dp, ~10 inch
    //    trở lên) thường in 80mm; máy cầm tay / tablet nhỏ in 58mm.
    val smallestDp = context?.resources?.configuration?.smallestScreenWidthDp ?: 0
    if (tier != BuiltInPrinterRules.Tier.VERIFIED && smallestDp >= 720) return 80

    // Mặc định máy POS cầm tay (V2, V2s, V3, M2, A920, Urovo, B68...) là 58mm.
    return 58
}

private fun getSystemProperty(key: String): String {
    return try {
        val c = Class.forName("android.os.SystemProperties")
        val get = c.getMethod("get", String::class.java)
        get.invoke(c, key) as String
    } catch (e: Exception) {
        ""
    }
}
