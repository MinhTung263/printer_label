  package com.printer.printer_label

object NetworkConfigHelper {
    fun parseMac(macStr: String): ByteArray {
        val parts = macStr.split(":", "-")
        val bytes = ByteArray(6)
        if (parts.size == 6) {
            for (i in 0 until 6) {
                bytes[i] = (parts[i].toIntOrNull(16) ?: 0).toByte()
            }
        }
        return bytes
    }

    fun parseIp(ipStr: String): ByteArray {
        val parts = ipStr.split(".")
        val bytes = ByteArray(4)
        if (parts.size == 4) {
            for (i in 0 until 4) {
                bytes[i] = (parts[i].toIntOrNull() ?: 0).toByte()
            }
        }
        return bytes
    }
}
