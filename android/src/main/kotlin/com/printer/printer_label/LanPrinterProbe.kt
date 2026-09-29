package com.printer.printer_label

import java.io.File

object LanPrinterProbe {

    fun getMacFromArp(ip: String): String? {
        // 1. Thử đọc /proc/net/arp (Android 9 trở xuống hoặc máy POS chuyên dụng)
        try {
            val file = File("/proc/net/arp")
            if (file.exists()) {
                val lines = file.readLines()
                for (line in lines) {
                    val parts = line.split("\\s+".toRegex())
                    if (parts.size >= 4 && parts[0] == ip) {
                        val mac = parts[3].trim()
                        if (mac != "00:00:00:00:00:00" && mac.length == 17) {
                            return mac
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        // 2. Thử lệnh `ip neigh` (hoạt động trên Android 10+ không cần root)
        try {
            val process = Runtime.getRuntime().exec(arrayOf("ip", "neigh"))
            val reader = process.inputStream.bufferedReader()
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                val currentLine = line ?: continue
                if (currentLine.contains(ip)) {
                    val parts = currentLine.split("\\s+".toRegex())
                    val lladdrIdx = parts.indexOf("lladdr")
                    if (lladdrIdx != -1 && lladdrIdx + 1 < parts.size) {
                        val mac = parts[lladdrIdx + 1].trim()
                        if (mac.length == 17 && mac != "00:00:00:00:00:00") {
                            return mac
                        }
                    }
                }
            }
            process.waitFor()
        } catch (_: Exception) {}

        return null
    }

    /// Bảng OUI dưới đây được đối chiếu trực tiếp với database IEEE/Wireshark
    /// (wireshark.org/download/automated/data/manuf, tra cứu 2026-09-03) — CHỈ
    /// giữ mã đã xác nhận đúng thật. Bảng cũ trước đây tự chế/nhớ nhầm gần 90% mã
    /// (ví dụ nhóm "HPRT"/"Xprinter" cũ thực ra trỏ sang Xiaomi, Espressif,
    /// Nokia...), gây nhận diện sai hàng loạt thiết bị không phải máy in. Xprinter
    /// và TSC không có trong danh sách vì KHÔNG đăng ký OUI riêng dưới tên hãng
    /// (dùng module Wi-Fi/Ethernet của bên thứ ba) — để trống thay vì suy đoán;
    /// muốn thêm phải đo MAC thật từ máy mẫu, không tra ngược từ trí nhớ.
    fun getVendorFromMac(mac: String?): String? {
        if (mac == null) return null
        val clean = mac.replace(":", "").replace("-", "").uppercase()
        if (clean.length < 6) return null
        val prefix6 = clean.substring(0, 6)

        return when {
            // Epson (Seiko Epson Corporation)
            prefix6.startsWith("000048") ||
            prefix6.startsWith("0026AB") ||
            prefix6.startsWith("381A52") ||
            prefix6.startsWith("389D92") ||
            prefix6.startsWith("44D244") ||
            prefix6.startsWith("50579C") ||
            prefix6.startsWith("5805D9") ||
            prefix6.startsWith("64C6D2") ||
            prefix6.startsWith("64EB8C") ||
            prefix6.startsWith("6855D4") ||
            prefix6.startsWith("9CAED3") ||
            prefix6.startsWith("A4D73C") ||
            prefix6.startsWith("A4EE57") ||
            prefix6.startsWith("AC1826") ||
            prefix6.startsWith("B0E892") ||
            prefix6.startsWith("BCC8CC") ||
            prefix6.startsWith("D4808B") ||
            prefix6.startsWith("DC83BF") ||
            prefix6.startsWith("DCCD2F") ||
            prefix6.startsWith("E0BB9E") ||
            prefix6.startsWith("F82551") ||
            prefix6.startsWith("F8D027") -> "Epson"

            // HPRT (Xiamen Hanin Electronic Technology)
            prefix6.startsWith("6CC147") -> "HPRT"

            // Rongta (Xiamen Rongta Technology) — mã duy nhất hãng này có trong
            // registry; là khối /28 nên 6 hex đầu không phân biệt tuyệt đối 100%
            prefix6.startsWith("480BB2") -> "Rongta"

            // Zebra Technologies
            prefix6.startsWith("000512") ||
            prefix6.startsWith("00074D") ||
            prefix6.startsWith("001570") ||
            prefix6.startsWith("002368") ||
            prefix6.startsWith("00A0F8") ||
            prefix6.startsWith("4083DE") ||
            prefix6.startsWith("488EB7") ||
            prefix6.startsWith("609532") ||
            prefix6.startsWith("7493A4") ||
            prefix6.startsWith("78B8D6") ||
            prefix6.startsWith("84248D") ||
            prefix6.startsWith("88BCAC") ||
            prefix6.startsWith("9075DE") ||
            prefix6.startsWith("94FB29") ||
            prefix6.startsWith("C47DCC") ||
            prefix6.startsWith("C4BB4C") ||
            prefix6.startsWith("C81CFE") ||
            prefix6.startsWith("FC597A") -> "Zebra"

            // Bixolon
            prefix6.startsWith("001594") -> "Bixolon"

            // Star Micronics
            prefix6.startsWith("001162") -> "Star"

            // Citizen (Citizen Watch Co. — công ty mẹ, dùng chung khối OUI)
            prefix6.startsWith("000CAC") -> "Citizen"

            // Brother Industries
            prefix6.startsWith("001BA9") ||
            prefix6.startsWith("008077") ||
            prefix6.startsWith("30055C") ||
            prefix6.startsWith("3C2AF4") ||
            prefix6.startsWith("94DDF8") ||
            prefix6.startsWith("B07C8E") ||
            prefix6.startsWith("B42200") -> "Brother"

            // SNBC (Shandong New Beiyang Information Technology)
            prefix6.startsWith("001341") -> "SNBC"

            // Godex International
            prefix6.startsWith("001D9A") -> "Godex"

            // Sunmi (Shanghai Sunmi Technology)
            prefix6.startsWith("1C1A1B") ||
            prefix6.startsWith("68508C") ||
            prefix6.startsWith("74F7F6") ||
            prefix6.startsWith("B81BCB") -> "Sunmi"

            // PDIT — đo từ MAC máy mẫu thật (00:1A:EF:CB:2C:B0, 2026-09-29). Registry
            // IEEE ghi 00:1A:EF là "Loopcomm Technology, Inc." — hãng làm MODULE MẠNG,
            // không phải PDIT. Máy in hãng khác dùng module Loopcomm cũng sẽ hiện "PDIT".
            prefix6.startsWith("001AEF") -> "PDIT"

            else -> null
        }
    }

    /// Probes a printer IP by reading ARP and neighbor tables.
    /// Does NOT open any socket connection to the printer to avoid triggering
    /// paper feed or print during a network scan.
    fun probe(ip: String, port: Int = 9100, timeoutMs: Int = 800): Map<String, Any?> {
        val mac = getMacFromArp(ip)
        val vendor = getVendorFromMac(mac)

        return mapOf(
            "ip" to ip,
            "port" to port,
            "mac" to mac,
            "rawName" to null,
            "vendor" to vendor
        )
    }
}
