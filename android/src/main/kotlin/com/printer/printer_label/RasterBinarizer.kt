package com.printer.printer_label

/**
 * Nhị phân hoá ảnh ARGB thành bitmap 1 bit (cháy / trắng) cho đầu in nhiệt, xử lý theo từng DẢI dòng.
 *
 * Trước đây đọc cả ảnh vào một `IntArray(width * height)`: hoá đơn dài (đơn 150 món ở khổ 80mm, ~25.000
 * dòng) tốn `576 × 25.000 × 4 ≈ 57MB` chỉ cho mảng này, ngoài bitmap giải mã cùng cỡ — máy POS RAM thấp
 * (Sunmi T1-G 2GB) dễ hết bộ nhớ. Nay chỉ giữ một dải [STRIP_ROWS] dòng (~150KB ở khổ 80mm) mỗi lần.
 * Kết quả GIỐNG HỆT cách cũ (cùng ngưỡng, cùng thứ tự bit) — xem `RasterBinarizerTest`.
 *
 * Quy tắc (không đổi): điểm cháy khi alpha > 50 và xám < 200, xám = 0.299R + 0.587G + 0.114B tính bằng số
 * nguyên (nhân 1000). Ngưỡng 200 — KHÔNG hạ về 128: đầu in nhiệt chỉ có cháy / trắng; chữ anti-alias gồm
 * lõi đậm + viền xám, ngưỡng 128 chỉ còn bộ xương mảnh -> in RẤT MỜ.
 */
internal object RasterBinarizer {
    /** Số dòng đọc mỗi lần. */
    const val STRIP_ROWS = 64

    class Result(
        /** `widthBytes * height` byte, mỗi dòng `widthBytes` byte, bit cao nhất = điểm bên trái. */
        val bits: ByteArray,
        /** `true` ở dòng không có điểm cháy nào. */
        val blankRow: BooleanArray,
    )

    /**
     * [readRows] điền [rowCount] dòng ARGB bắt đầu từ dòng [startRow] vào `buffer[0 until rowCount * width]`
     * (dòng sau nối liền dòng trước) — với `Bitmap` là `getPixels(buffer, 0, width, 0, startRow, width, rowCount)`.
     */
    fun binarize(
        width: Int,
        height: Int,
        readRows: (startRow: Int, rowCount: Int, buffer: IntArray) -> Unit,
    ): Result {
        val widthBytes = (width + 7) / 8
        val bits = ByteArray(widthBytes * height)
        val blankRow = BooleanArray(height)
        if (width <= 0 || height <= 0) return Result(bits, blankRow)

        val strip = IntArray(width * minOf(STRIP_ROWS, height))
        var startRow = 0
        while (startRow < height) {
            val n = minOf(STRIP_ROWS, height - startRow)
            readRows(startRow, n, strip)
            for (r in 0 until n) {
                val y = startRow + r
                val rowPixel = r * width
                val rowByte = y * widthBytes
                var any = 0
                for (xByte in 0 until widthBytes) {
                    var byteVal = 0
                    val x0 = xByte * 8
                    val xEnd = minOf(x0 + 8, width)
                    var x = x0
                    while (x < xEnd) {
                        val pixel = strip[rowPixel + x]
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
                blankRow[y] = any == 0
            }
            startRow += n
        }
        return Result(bits, blankRow)
    }
}
