package com.printer.printer_label

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Random

class RasterBinarizerTest {
    /** Cách CŨ (toàn ảnh một mảng) — chuẩn để so: kết quả mới phải giống hệt từng byte. */
    private fun reference(width: Int, height: Int, pixels: IntArray): Pair<ByteArray, BooleanArray> {
        val widthBytes = (width + 7) / 8
        val bits = ByteArray(widthBytes * height)
        val blank = BooleanArray(height)
        for (y in 0 until height) {
            val rowPixel = y * width
            val rowByte = y * widthBytes
            var any = 0
            for (xByte in 0 until widthBytes) {
                var byteVal = 0
                val x0 = xByte * 8
                val xEnd = Math.min(x0 + 8, width)
                var x = x0
                while (x < xEnd) {
                    val pixel = pixels[rowPixel + x]
                    if (((pixel ushr 24) and 0xff) > 50) {
                        val gray1000 = 299 * ((pixel shr 16) and 0xff) +
                            587 * ((pixel shr 8) and 0xff) +
                            114 * (pixel and 0xff)
                        if (gray1000 < 200_000) byteVal = byteVal or (0x80 ushr (x - x0))
                    }
                    x++
                }
                bits[rowByte + xByte] = byteVal.toByte()
                any = any or byteVal
            }
            blank[y] = any == 0
        }
        return bits to blank
    }

    private fun check(width: Int, height: Int, seed: Long) {
        val rnd = Random(seed)
        // Trộn: điểm đen, trắng, xám sát ngưỡng, trong suốt (alpha thấp) và cả dải dòng trắng dài.
        val pixels = IntArray(width * height) {
            val y = it / width
            if (y % 200 in 50..140) {
                0xFFFFFFFF.toInt()
            } else {
                when (rnd.nextInt(5)) {
                    0 -> 0xFF000000.toInt()
                    1 -> 0xFFFFFFFF.toInt()
                    2 -> (0xFF shl 24) or (199 shl 16) or (199 shl 8) or 199
                    3 -> (rnd.nextInt(60) shl 24) or rnd.nextInt(0x1000000) // alpha ≤ 59, quanh ngưỡng 50
                    else -> rnd.nextInt()
                }
            }
        }
        val (expectedBits, expectedBlank) = reference(width, height, pixels)

        var calls = 0
        var maxRowsAtOnce = 0
        val r = RasterBinarizer.binarize(width, height) { start, n, buf ->
            calls++
            maxRowsAtOnce = Math.max(maxRowsAtOnce, n)
            assertTrue("bộ đệm phải đủ chỗ", buf.size >= n * width)
            System.arraycopy(pixels, start * width, buf, 0, n * width)
        }
        assertArrayEquals("bits $width x $height", expectedBits, r.bits)
        assertEquals("blank $width x $height", expectedBlank.toList(), r.blankRow.toList())
        assertTrue("không đọc quá một dải mỗi lần", maxRowsAtOnce <= RasterBinarizer.STRIP_ROWS)
        assertEquals((height + RasterBinarizer.STRIP_ROWS - 1) / RasterBinarizer.STRIP_ROWS, calls)
    }

    @Test fun khoGiay80mm_cao_khong_chia_het_cho_dai() = check(576, 1000, 1)
    @Test fun khoGiay58mm() = check(384, 641, 2)
    @Test fun rongKhongChiaHetCho8() = check(37, 130, 3)
    @Test fun matDoThap_mot_dai() = check(100, 10, 4)
    @Test fun dungBoiSoCuaDai() = check(64, 128, 5)
    @Test fun anhRatCao() = check(576, 5000, 6)

    @Test
    fun anhRong_khongLoi() {
        val r = RasterBinarizer.binarize(0, 0) { _, _, _ -> throw AssertionError("không được đọc") }
        assertEquals(0, r.bits.size)
        assertEquals(0, r.blankRow.size)
    }

    @Test
    fun anhTrang_moiDongLaTrang_vaChiDocTheoDai() {
        var calls = 0
        val r = RasterBinarizer.binarize(16, 200) { _, n, buf ->
            calls++
            java.util.Arrays.fill(buf, 0, n * 16, 0xFFFFFFFF.toInt())
        }
        assertTrue(r.blankRow.all { it })
        assertTrue(r.bits.all { it == 0.toByte() })
        assertEquals(4, calls) // 200 dòng / 64 = 4 dải
    }
}
