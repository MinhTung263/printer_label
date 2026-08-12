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

    fun getVendorFromMac(mac: String?): String? {
        if (mac == null) return null
        val clean = mac.replace(":", "").replace("-", "").uppercase()
        if (clean.length < 6) return null
        val prefix6 = clean.substring(0, 6)

        return when {
            // HPRT (Hanin)
            prefix6.startsWith("50EC50") ||
            prefix6.startsWith("3C9180") ||
            prefix6.startsWith("84F3EB") ||
            prefix6.startsWith("E04F43") ||
            prefix6.startsWith("C89346") ||
            prefix6.startsWith("AC67B2") ||
            prefix6.startsWith("4887B2") ||
            prefix6.startsWith("D8B04C") ||
            prefix6.startsWith("F835DD") -> "HPRT"

            // Xprinter & POS
            prefix6.startsWith("001BEE") ||
            prefix6.startsWith("000C43") ||
            prefix6.startsWith("08EA44") ||
            prefix6.startsWith("A09208") ||
            prefix6.startsWith("0008DC") ||
            prefix6.startsWith("001AB6") ||
            prefix6.startsWith("18FE34") ||
            prefix6.startsWith("B4E62D") ||
            prefix6.startsWith("ECFABC") ||
            prefix6.startsWith("240AC4") ||
            prefix6.startsWith("807D3A") ||
            prefix6.startsWith("68C63A") -> "Xprinter"

            // Epson
            prefix6.startsWith("0026AB") ||
            prefix6.startsWith("000048") ||
            prefix6.startsWith("0021B7") ||
            prefix6.startsWith("ACD1B8") ||
            prefix6.startsWith("64EB8C") -> "Epson"

            // TSC & Gaincha
            prefix6.startsWith("001B67") ||
            prefix6.startsWith("002655") -> "TSC"

            // Rongta
            prefix6.startsWith("00115B") ||
            prefix6.startsWith("2C2617") -> "Rongta"

            // Zebra
            prefix6.startsWith("00074D") ||
            prefix6.startsWith("001D92") ||
            prefix6.startsWith("00059A") ||
            prefix6.startsWith("AC3FA4") -> "Zebra"

            // Bixolon
            prefix6.startsWith("001599") -> "Bixolon"

            // Star Micronics
            prefix6.startsWith("001162") -> "Star"

            // Citizen
            prefix6.startsWith("0012F0") || prefix6.startsWith("001E8C") -> "Citizen"

            // Brother
            prefix6.startsWith("008077") -> "Brother"

            // SNBC & Beiyang
            prefix6.startsWith("001EAC") -> "SNBC"

            // Godex
            prefix6.startsWith("001882") -> "Godex"

            // Sunmi
            prefix6.startsWith("38A28C") ||
            prefix6.startsWith("D4619D") ||
            prefix6.startsWith("B0D59D") ||
            prefix6.startsWith("04E2B9") ||
            prefix6.startsWith("58B035") -> "Sunmi"

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
