package com.printer.printer_label

import com.printer.printer_label.BuiltInPrinterRules.Bonded
import com.printer.printer_label.BuiltInPrinterRules.Tier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BuiltInPrinterRulesTest {
    private val unknown = BuiltInPrinterRules.DEVICE_TYPE_UNKNOWN
    private val classic = 1

    @Test
    fun macGiaTheoDaySo() {
        for (mac in listOf(
            "00:11:22:33:44:55", // Sunmi / iMin
            "66:11:22:33:44:55", // B68 / ZCS
            "11:22:33:44:55:66",
            "00:01:02:03:04:05",
            "12:34:56:78:9A:BC",
            "88:88:88:88:88:88",
        )) assertTrue(mac, BuiltInPrinterRules.isSyntheticMac(mac))
        for (mac in listOf(
            "86:67:7A:25:90:AF", // máy in ngoài thật
            "58:64:C4:D9:50:55",
            "DC:0D:30:12:34:99",
            "00:00:00:00:00:00",
            "khong-phai-mac",
            null,
        )) assertFalse("$mac", BuiltInPrinterRules.isSyntheticMac(mac))
    }

    @Test
    fun mucThietBi() {
        fun tier(vararg f: String, rom: String = "", pk: List<String> = emptyList()) =
            BuiltInPrinterRules.tierOf(f.toList(), rom, pk)
        assertEquals(Tier.VERIFIED, tier("SUNMI", "V2s"))
        assertEquals(Tier.VERIFIED, tier("BLESSX", "T4SMODELX"))
        // Máy B68 trắng nhãn: chỉ mã ROM lộ dòng máy.
        assertEquals(Tier.VERIFIED, tier("ACME", "X1", rom = "B68_V1.1.1_B230721"))
        assertEquals(Tier.VERIFIED, tier("ACME", "X1", pk = listOf("com.zcs.printer")))
        assertEquals(Tier.LIKELY, tier("ACME", "Q2", pk = listOf("com.iposprinter.iposprinterservice")))
        assertEquals(Tier.LIKELY, tier("ACME", "Android POS"))
        assertEquals(Tier.LIKELY, tier("ACME", "SmartPOS-5"))
        // Điện thoại thường — kể cả tên có chuỗi "pos" bên trong từ khác.
        assertEquals(Tier.UNKNOWN, tier("samsung", "SM-A546E"))
        assertEquals(Tier.UNKNOWN, tier("OPPO", "CPH2591"))
        assertEquals(Tier.UNKNOWN, tier("acme", "Poseidon"))
    }

    /** Đúng tình huống máy BLESSX T4SMODELX: máy in ảo + một máy in ngoài đã ghép đôi. */
    @Test
    fun chonMayInAoKhongChonMayInNgoai() {
        val inner = Bonded("66:11:22:33:44:55", "BluetoothPrint", unknown, printerLike = true)
        val external = Bonded("86:67:7A:25:90:AF", "mini-printer_90AF", 3, printerLike = true)
        val headset = Bonded("58:64:C4:D9:50:55", "AirPods", classic)
        for (tier in Tier.values()) {
            assertEquals(tier.name, inner, BuiltInPrinterRules.pick(listOf(external, headset, inner), tier))
        }
    }

    @Test
    fun mayLaChiNhanMayInAoChac() {
        // Điện thoại thường ghép đôi máy in ngoài: không coi là máy in tích hợp.
        val cheap = Bonded("DC:0D:30:12:34:99", "BlueTooth Printer", classic, printerLike = true)
        val named = Bonded("DC:0D:30:12:34:99", "InnerPrinter", classic, printerLike = true)
        assertNull(BuiltInPrinterRules.pick(listOf(cheap), Tier.UNKNOWN))
        assertNull(BuiltInPrinterRules.pick(listOf(named), Tier.UNKNOWN))
        // Máy POS lạ có máy in ảo (MAC giả + chưa từng dò qua sóng): nhận.
        val virtual = Bonded("00:11:22:33:44:55", "PrinterX", unknown)
        assertEquals(virtual, BuiltInPrinterRules.pick(listOf(cheap, virtual), Tier.UNKNOWN))
        // Máy có dấu hiệu POS: tên nội bộ là đủ.
        assertEquals(named, BuiltInPrinterRules.pick(listOf(named), Tier.LIKELY))
        assertNull(BuiltInPrinterRules.pick(listOf(cheap), Tier.LIKELY))
    }

    @Test
    fun dongMayDaBietGiuCachCu() {
        // Sunmi: InnerPrinter thắng máy in ngoài; không có máy in ảo thì vẫn lấy
        // máy in đang ghép đôi (cách cũ), thiết bị không phải máy in thì bỏ.
        val inner = Bonded("00:11:22:33:44:55", "InnerPrinter", unknown, printerLike = true)
        val external = Bonded("DC:0D:30:12:34:99", "XP-58", classic, printerLike = true)
        val headset = Bonded("58:64:C4:D9:50:55", "AirPods", classic)
        assertEquals(inner, BuiltInPrinterRules.pick(listOf(external, inner), Tier.VERIFIED))
        assertEquals(external, BuiltInPrinterRules.pick(listOf(headset, external), Tier.VERIFIED))
        assertNull(BuiltInPrinterRules.pick(listOf(headset), Tier.VERIFIED))
    }

    @Test
    fun tenMayInTichHop() {
        for (n in listOf("InnerPrinter", "BluetoothPrinter", "BluetoothPrint", "IposPrinter", "SUNMI V2"))
            assertTrue(n, BuiltInPrinterRules.isBuiltInName(n))
        for (n in listOf("mini-printer_90AF", "XP-58", "", null))
            assertFalse("$n", BuiltInPrinterRules.isBuiltInName(n))
    }
}
