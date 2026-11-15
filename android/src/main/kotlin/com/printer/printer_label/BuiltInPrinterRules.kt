package com.printer.printer_label

/**
 * LUẬT nhận diện máy in tích hợp — Kotlin thuần (không dùng API Android) để
 * unit test được ([BuiltInPrinterRulesTest]).
 *
 * Máy in tích hợp của máy POS Android mà plugin in được là một máy in
 * Bluetooth "ảo" do hệ thống tạo sẵn trong danh sách đã ghép đôi (Sunmi
 * "InnerPrinter", iMin "BluetoothPrinter", dòng B68 / ZCS "BluetoothPrint"...)
 * — hoặc SDK riêng (Urovo). Nhận diện theo HAI lớp, không chỉ theo tên hãng:
 *
 * 1. **Thiết bị** ([tierOf]): hãng / model / mã ROM / gói dịch vụ in →
 *    [Tier.VERIFIED] (dòng máy đã biết in được), [Tier.LIKELY] (có dấu hiệu là
 *    máy POS nhưng chưa xác minh), [Tier.UNKNOWN].
 * 2. **Máy in ảo trong danh sách Bluetooth đã ghép đôi** ([pick]): chấm điểm
 *    từng thiết bị theo dấu hiệu KHÔNG phụ thuộc hãng — MAC giả theo dãy số
 *    ([isSyntheticMac]), loại thiết bị "không rõ" (chưa từng dò qua sóng),
 *    tên máy in nội bộ. Máy chưa biết hãng vẫn nhận được nếu có máy in ảo.
 */
internal object BuiltInPrinterRules {

    enum class Tier { VERIFIED, LIKELY, UNKNOWN }

    /** Một thiết bị Bluetooth đã ghép đôi (dữ liệu thô để chấm điểm). */
    data class Bonded(
        val mac: String,
        val name: String?,
        /** `BluetoothDevice.getType()`; 0 = DEVICE_TYPE_UNKNOWN. */
        val type: Int,
        /** Lớp thiết bị IMAGING (máy in / máy quét). */
        val imaging: Boolean = false,
        /** Tên giống máy in Bluetooth nói chung (`isPrinter`). */
        val printerLike: Boolean = false,
    )

    const val DEVICE_TYPE_UNKNOWN = 0

    // ---- Lớp 1: thiết bị -------------------------------------------------

    /**
     * Hãng / dòng máy ĐÃ BIẾT in được — đúng danh sách cũ của plugin (chỉ xét
     * hãng sản xuất và model, KHÔNG xét thương hiệu / tên sản phẩm để không
     * nhận nhầm máy cũ) + dòng B68 bán dưới hãng khác (BLESSX T4SMODELX, đã
     * kiểm tra: ROM B68_V1.1.1, dịch vụ in ZCS).
     */
    private val VERIFIED_MANUFACTURERS = listOf(
        "sunmi", "imin", "pax", "urovo", "smartpeak", "kozen", "blessx",
    )

    /** Từ khoá model của dòng máy đã biết (kể cả máy cũ: sunmi, imin, pax, urovo). */
    private val VERIFIED_MODELS = listOf(
        "sunmi", "imin", "pax", "urovo", "b68", "p068", "t4smodel",
    )

    /** Tiền tố mã ROM (`Build.DISPLAY`) của dòng máy đã biết. */
    private val VERIFIED_ROM_PREFIXES = listOf("b68_", "p068_")

    /**
     * Gói dịch vụ in của máy POS. Chỉ là DẤU HIỆU ([Tier.LIKELY]) — KHÔNG đủ để
     * nhận là có máy in tích hợp (nhiều máy POS có gói này nhưng in bằng SDK
     * riêng, không có máy in Bluetooth): phải thấy máy in ảo mới nhận. Giữ
     * nguyên cách xử lý máy cũ.
     */
    val HINT_PACKAGES = listOf(
        "com.sunmi.printerservice",            // Sunmi
        "woyou.aidl.service",                  // Sunmi / iMin AIDL
        "woyou.aidlservice.jiuiv5",            // Sunmi (dịch vụ in gốc) + máy nhái
        "net.imin.printer",                    // iMin
        "com.imin.printer",                    // iMin (bản mới)
        "com.pax.sz.printerservice",           // Pax
        "com.landicorp.android.pinpadservice", // Landi
        "com.urovo.printerservice",            // Urovo
        "android.printservice.urovoprint",     // Urovo
        "com.zcs.printer",                     // ZCS (dòng B68 / BLESSX)
        "com.szzcs.smartpos",                  // ZCS SmartPOS
        "com.iposprinter.iposprinterservice",  // iPos (Q1 / Q2 / Z91...)
        "recieptservice.com.recieptservice",   // Senraise (H10...)
    )

    private val POS_WORD = Regex("(^|[^a-z])(m|smart|android)?pos([^a-z]|$)")

    /**
     * Mức nhận diện của THIẾT BỊ. [manufacturer] / [model]: dùng cho danh sách
     * ĐÃ BIẾT; [others] (thương hiệu, tên sản phẩm, tên thiết bị) chỉ dùng cho
     * dấu hiệu "máy POS"; [display]: mã ROM; [packages]: gói dịch vụ in có trên
     * máy.
     */
    fun tierOf(
        manufacturer: String,
        model: String,
        others: List<String>,
        display: String,
        packages: Collection<String>,
    ): Tier {
        val man = manufacturer.lowercase()
        val mod = model.lowercase()
        val rom = display.lowercase()
        if (VERIFIED_MANUFACTURERS.any { man.contains(it) } ||
            VERIFIED_MODELS.any { mod.contains(it) } ||
            VERIFIED_ROM_PREFIXES.any { rom.startsWith(it) }
        ) {
            return Tier.VERIFIED
        }
        val hints = listOf(man, mod) + others.map { it.lowercase() }
        if (packages.any { it in HINT_PACKAGES } ||
            hints.any { POS_WORD.containsMatchIn(it) } ||
            POS_WORD.containsMatchIn(rom)
        ) {
            return Tier.LIKELY
        }
        return Tier.UNKNOWN
    }

    // ---- Lớp 2: máy in ảo trong Bluetooth đã ghép đôi --------------------

    /** Tên máy in NỘI BỘ (ảo) do hệ thống máy POS đặt. */
    private val INNER_NAMES = listOf(
        "InnerPrinter", "Inner Printer",       // Sunmi + máy nhái
        "BluetoothPrint",                      // B68 / ZCS; gồm cả "BluetoothPrinter" (iMin)
        "IposPrinter",                         // iPos
        "Virtual BT Printer", "VirtualPrinter",
        "Builtin Printer", "Built-in Printer",
    )

    /**
     * Tên có chữ hãng / dòng máy POS (máy in nội bộ đặt theo tên hãng), và tên
     * chung "Bluetooth Printer" (giữ như trước — nhiều máy in NGOÀI giá rẻ cũng
     * mang tên này nên điểm thấp hơn tên nội bộ).
     */
    private val VENDOR_NAMES = listOf(
        "SUNMI", "iMin", "Pax", "Urovo", "B68", "P068", "SmartPos", "Bluetooth Printer",
    )

    fun isInnerPrinterName(name: String?): Boolean =
        !name.isNullOrEmpty() && INNER_NAMES.any { name.contains(it, ignoreCase = true) }

    /** Tên Bluetooth khớp máy in tích hợp (tên nội bộ hoặc tên hãng POS). */
    fun isBuiltInName(name: String?): Boolean =
        isInnerPrinterName(name) ||
            (!name.isNullOrEmpty() && VENDOR_NAMES.any { name.contains(it, ignoreCase = true) })

    /**
     * MAC "giả" theo dãy số — máy in ảo không có phần cứng Bluetooth thật nên
     * hãng đặt địa chỉ dễ nhớ: `00:11:22:33:44:55`, `66:11:22:33:44:55`,
     * `11:22:33:44:55:66`, `00:01:02:03:04:05`, `88:88:88:88:88:88`... MAC thật
     * (do IEEE cấp) gần như không thể trùng dạng này.
     */
    fun isSyntheticMac(mac: String?): Boolean {
        val parts = mac?.split(':', '-') ?: return false
        if (parts.size != 6) return false
        val b = parts.map { it.toIntOrNull(16) ?: return false }
        if (b.all { it == b[0] }) return b[0] != 0
        return isProgression(b.subList(1, 6)) || isProgression(b.subList(0, 5))
    }

    /** Cấp số cộng công sai khác 0 (11,22,33,44,55 / 01,02,03,04,05...). */
    private fun isProgression(v: List<Int>): Boolean {
        val step = v[1] - v[0]
        return step != 0 && (1 until v.size).all { v[it] - v[it - 1] == step }
    }

    /** Điểm "giống máy in tích hợp" của một thiết bị đã ghép đôi. */
    fun score(d: Bonded): Int {
        var s = 0
        if (isSyntheticMac(d.mac)) s += 60
        if (d.type == DEVICE_TYPE_UNKNOWN) s += 25
        if (isInnerPrinterName(d.name)) s += 40
        else if (isBuiltInName(d.name)) s += 30
        if (d.imaging) s += 5
        if (d.printerLike) s += 3
        return s
    }

    /**
     * Thiết bị đủ chắc là máy in ảo dù KHÔNG biết hãng máy: MAC giả VÀ (chưa
     * từng dò qua sóng HOẶC mang tên máy in nội bộ).
     */
    fun isStrong(d: Bonded): Boolean =
        isSyntheticMac(d.mac) && (d.type == DEVICE_TYPE_UNKNOWN || isInnerPrinterName(d.name))

    /** Ứng viên chấp nhận được theo mức thiết bị. */
    private fun accepts(d: Bonded, tier: Tier): Boolean = when (tier) {
        // Dòng máy đã biết: giữ cách cũ (máy in bất kỳ) làm lớp cuối, nhưng chọn
        // theo ĐIỂM — không lấy nhầm máy in ngoài khi có máy in ảo.
        Tier.VERIFIED -> score(d) > 0
        Tier.LIKELY -> isSyntheticMac(d.mac) || isInnerPrinterName(d.name) ||
            (d.type == DEVICE_TYPE_UNKNOWN && (d.printerLike || d.imaging))
        Tier.UNKNOWN -> isStrong(d)
    }

    /**
     * Chọn máy in tích hợp trong các thiết bị đã ghép đôi: điểm cao nhất trong
     * các ứng viên chấp nhận được với [tier]; `null` khi không có.
     */
    fun pick(devices: Collection<Bonded>, tier: Tier): Bonded? =
        devices.filter { accepts(it, tier) }.maxByOrNull { score(it) }
}
