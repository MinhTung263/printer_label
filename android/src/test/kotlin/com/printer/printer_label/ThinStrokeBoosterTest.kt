package com.printer.printer_label

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class ThinStrokeBoosterTest {
    private val w = 32
    private val wb = 4

    /** Dựng ảnh từ các dòng chữ: '#' = đen. */
    private fun img(vararg rows: String): ByteArray {
        val bits = ByteArray(wb * rows.size)
        rows.forEachIndexed { y, r ->
            r.forEachIndexed { x, c ->
                if (c == '#') bits[y * wb + (x shr 3)] = (bits[y * wb + (x shr 3)].toInt() or (0x80 ushr (x and 7))).toByte()
            }
        }
        return bits
    }

    private fun row(bits: ByteArray, y: Int, len: Int): String = (0 until len).joinToString("") { x ->
        if ((bits[y * wb + (x shr 3)].toInt() and (0x80 ushr (x and 7))) != 0) "#" else "."
    }

    private fun boost(vararg rows: String) = ThinStrokeBooster.boost(img(*rows), wb, w, rows.size)

    @Test
    fun oneDotStroke_getsExtraDot() {
        assertEquals(".##...", row(boost(".#....", ".#...."), 0, 6))
    }

    @Test
    fun strokeOfTwoDotsOrMore_unchanged() {
        val src = img(".##..###..", ".##..###..")
        assertArrayEquals(src, ThinStrokeBooster.boost(src, wb, w, 2))
    }

    @Test
    fun doesNotFillOneDotWhiteGap() {
        // Hai nét cách nhau 1 chấm trắng (lỗ chữ "e", "a"): nét trái giữ nguyên.
        assertEquals(".#.##.", row(boost(".#.#.."), 0, 6))
    }

    @Test
    fun tallVerticalBar_untouched() {
        val rows = Array(ThinStrokeBooster.MAX_STEM_ROWS + 5) { "..#....." }
        val src = img(*rows)
        assertArrayEquals(src, ThinStrokeBooster.boost(src, wb, w, rows.size))
    }

    @Test
    fun doesNotModifySourceImage() {
        val src = img(".#....")
        val copy = src.copyOf()
        ThinStrokeBooster.boost(src, wb, w, 1)
        assertArrayEquals(copy, src)
    }
}
