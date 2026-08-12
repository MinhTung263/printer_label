  package com.printer.printer_label

import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

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

    /**
     * Gửi lệnh ESC/POS đặt IP qua TCP port 9100 tới [currentIp].
     * Hoạt động với Epson, Brother, và các máy in generic ESC/POS network.
     *
     * @return true nếu gửi thành công, false nếu lỗi kết nối / timeout
     */
    fun sendEscIpConfig(
        currentIp: String,
        newIp: String,
        mask: String,
        gateway: String,
        dhcp: Boolean,
        port: Int = 9100,
        timeoutMs: Int = 4000,
    ): Boolean {
        return try {
            val data = buildEscNetworkCommand(newIp, mask, gateway, dhcp)
            Socket().use { socket ->
                socket.connect(InetSocketAddress(currentIp, port), timeoutMs)
                socket.soTimeout = timeoutMs
                val out: OutputStream = socket.getOutputStream()
                out.write(data)
                out.flush()
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Xây dựng lệnh ESC/POS cấu hình mạng (WiFi IP setting command).
     *
     * Packet layout (Epson GS ( E, fn=2, sub-function IP config):
     * [1D 28 45] [pL pH] [02] [49] [dhcp] [ip0 ip1 ip2 ip3] [mask0..3] [gw0..3]
     */
    private fun buildEscNetworkCommand(
        ip: String,
        mask: String,
        gateway: String,
        dhcp: Boolean,
    ): ByteArray {
        val effectiveMask = if (mask.isEmpty()) "255.255.255.0" else mask
        val ipBytes = parseIp(ip)
        val maskBytes = parseIp(effectiveMask)
        val gwBytes = if (gateway.isNotEmpty()) parseIp(gateway) else ByteArray(4)

        // pL pH = data length after fn byte: 1 (fn) + 1 (subfn) + 1 (dhcp) + 4+4+4 = 15
        val dataLen = 15
        val pL = (dataLen and 0xFF).toByte()
        val pH = ((dataLen shr 8) and 0xFF).toByte()

        val dhcpByte: Byte = if (dhcp) 0x01 else 0x00

        return byteArrayOf(
            0x1D, 0x28, 0x45, pL, pH,  // GS ( E
            0x02,                        // fn = Network Interface Setting
            0x49,                        // sub-function = IP config ('I')
            dhcpByte,
            ipBytes[0], ipBytes[1], ipBytes[2], ipBytes[3],
            maskBytes[0], maskBytes[1], maskBytes[2], maskBytes[3],
            gwBytes[0], gwBytes[1], gwBytes[2], gwBytes[3],
        )
    }
}
