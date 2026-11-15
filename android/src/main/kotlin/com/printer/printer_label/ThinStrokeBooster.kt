package com.printer.printer_label

/**
 * Làm RÕ NÉT MẢNH cho máy in tích hợp (đầu in nhiệt cầm tay 58mm) — Kotlin
 * thuần để unit test được ([ThinStrokeBoosterTest]).
 *
 * Chữ thường / chữ nhỏ ở 384 chấm có nét dọc chỉ dày 1 chấm; đầu in cầm tay in
 * nét 1 chấm ra mảnh và nhạt (chữ đậm vẫn rõ). Các lệnh chỉnh độ đậm ESC/POS
 * (`ESC 7`, `GS ( K`, `DC2 #`) đã thử trên máy thật đều không có tác dụng qua
 * máy in Bluetooth ảo, nên phải xử lý ngay trên ảnh.
 *
 * KHÔNG làm dày đều cả ảnh (chữ nhỏ dính nét, bít lỗ "e", "a"): chỉ nét ngang
 * dày ĐÚNG 1 chấm mới được thêm 1 chấm bên phải, và chỉ khi sau đó vẫn còn
 * khoảng trắng — nét đã dày từ 2 chấm (chữ đậm, khối đen, mã QR) giữ nguyên.
 * Vạch dọc CAO (mã vạch, đường kẻ dọc) cũng giữ nguyên để không lệch tỉ lệ vạch.
 */
internal object ThinStrokeBooster {

    /** Nét dọc cao hơn ngần này dòng coi là vạch mã vạch / đường kẻ, không đụng. */
    const val MAX_STEM_ROWS = 48

    /**
     * [bits]: ảnh 1-bit đóng gói theo dòng ([widthBytes] byte mỗi dòng, bit cao
     * là điểm bên trái, 1 = đen). Trả về mảng MỚI; [bits] không bị sửa.
     */
    fun boost(bits: ByteArray, widthBytes: Int, width: Int, height: Int): ByteArray {
        val out = bits.copyOf()
        fun on(x: Int, y: Int): Boolean =
            (bits[y * widthBytes + (x shr 3)].toInt() and (0x80 ushr (x and 7))) != 0

        for (y in 0 until height) {
            var x = 0
            // Cần x+1 (điểm thêm) và x+2 (khoảng trắng còn lại) nằm trong ảnh.
            while (x < width - 2) {
                if (on(x, y) &&
                    (x == 0 || !on(x - 1, y)) &&
                    !on(x + 1, y) &&
                    !on(x + 2, y) &&
                    !isTallStem(x, y, height, ::on)
                ) {
                    val i = y * widthBytes + ((x + 1) shr 3)
                    out[i] = (out[i].toInt() or (0x80 ushr ((x + 1) and 7))).toByte()
                    x += 3
                } else {
                    x++
                }
            }
        }
        return out
    }

    /** Cột [x] có đoạn đen liền qua dòng [y] cao hơn [MAX_STEM_ROWS] không. */
    private inline fun isTallStem(x: Int, y: Int, height: Int, on: (Int, Int) -> Boolean): Boolean {
        var run = 1
        var up = y - 1
        while (up >= 0 && on(x, up)) {
            if (++run > MAX_STEM_ROWS) return true
            up--
        }
        var down = y + 1
        while (down < height && on(x, down)) {
            if (++run > MAX_STEM_ROWS) return true
            down++
        }
        return false
    }
}
