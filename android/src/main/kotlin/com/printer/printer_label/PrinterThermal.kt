package com.printer.printer_label

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.POSConst
import net.posprinter.POSPrinter

class PrinterThermal {
    companion object {
        // Khóa gửi RIÊNG cho TỪNG máy in (theo đối tượng IDeviceConnection).
        // SDK POSConnect có hàng đợi + luồng gửi riêng cho mỗi connection, nên 2 máy
        // KHÁC nhau in được song song. Chỉ cần tuần tự hóa các lần gửi trên CÙNG một
        // máy (nhiều chunk/nhiều job vào chung 1 connection) để byte không chèn vào
        // nhau gây in ra ký tự rác. Nhờ vậy in cùng lúc 2 máy không phải đợi nhau.
        @JvmStatic
        val sendLocks = java.util.concurrent.ConcurrentHashMap<IDeviceConnection, Any>()

        @JvmStatic
        fun lockFor(conn: IDeviceConnection): Any =
            sendLocks.getOrPut(conn) { Any() }

        /**
         * Gửi hết [data] theo từng gói [chunkSize] và KIỂM TRA số byte thật sự gửi được.
         *
         * `sendSync` trả về số byte đã gửi, có thể NHỎ HƠN số byte đưa vào khi buffer
         * máy in/socket đầy (hay gặp với đơn dài, ảnh vài chục–trăm KB). Trước đây giá
         * trị trả về bị bỏ qua nên phần dữ liệu thiếu biến mất âm thầm: máy in vẫn đợi
         * cho đủ số byte mà lệnh `GS v 0` khai báo, treo luôn và ăn mất cả lệnh cắt lẫn
         * job in kế tiếp. Ở đây gửi tiếp đúng phần còn lại, và ném lỗi nếu không gửi
         * nổi để lớp trên báo thất bại thay vì báo thành công giả.
         */
        @JvmStatic
        fun sendAllSync(conn: IDeviceConnection, data: ByteArray, chunkSize: Int) {
            var offset = 0
            while (offset < data.size) {
                val count = Math.min(chunkSize, data.size - offset)
                val chunk = data.copyOfRange(offset, offset + count)
                val sent = conn.sendSync(chunk)
                if (sent <= 0) {
                    throw java.io.IOException(
                        "Gửi dữ liệu tới máy in thất bại tại byte $offset/${data.size} " +
                            "(sendSync trả về $sent). Máy in có thể đã mất kết nối hoặc đầy buffer."
                    )
                }
                // sendSync có thể gửi thiếu -> chỉ tiến đúng số byte đã gửi được.
                offset += sent
            }
        }
    }

    fun printImageESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result,
        isTargetBuiltIn: Boolean = false
    ) {
        val type = call.argument<String>("type")
        if (type != "ESC") {
            result.success(false)
            return
        }
        
        // Chạy toàn bộ quá trình in trên luồng nền để tránh khóa UI
        kotlin.concurrent.thread {
            try {
                val image: ByteArray? = call.argument<ByteArray>("image")
                if (image == null) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("PRINT_ERROR", "Image data is null", null)
                    }
                    return@thread
                }
                val bitmap = BitmapFactory.decodeByteArray(image, 0, image.size)
                if (bitmap == null) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("PRINT_ERROR", "Failed to decode bitmap image", null)
                    }
                    return@thread
                }
                val isBluetooth = curConnect.getConnectType() == POSConnect.DEVICE_TYPE_BLUETOOTH

                // LAN/USB: để SDK tự dựng + gửi lệnh ảnh, đúng như bản 2.0.9 vẫn chạy tốt.
                //
                // Bộ encoder raster thủ công bên dưới sinh ra ở commit 83ac36d để chữa lỗi
                // RIÊNG của Bluetooth (ảnh lệch, QR bị tách), nhưng lại áp cho MỌI kết nối.
                // Nó nhồi cả bill vào MỘT lệnh `GS v 0` duy nhất; đơn ngắn thì vừa, còn đơn
                // dài sinh ảnh cao hàng nghìn dòng, vượt giới hạn chiều cao mỗi lệnh raster
                // của máy in (Epson chỉ nhận vài trăm dòng/lệnh). Khi vượt, máy in hủy chế
                // độ raster và diễn giải byte ảnh còn lại thành VĂN BẢN -> giấy ra đầy ký tự
                // rác, không cắt, và treo luôn các job in sau.
                //
                // `printBitmap` của SDK tự chia dải nội bộ nên đơn dài bao nhiêu cũng in tốt.
                if (!isBluetooth && !isTargetBuiltIn) {
                    val printer = POSPrinter(curConnect)
                    val paperWidth: Int? = call.argument<Int>("size")
                    synchronized(lockFor(curConnect)) {
                        printer.initializePrinter()
                            .printBitmap(bitmap, POSConst.ALIGNMENT_CENTER, paperWidth ?: 576)
                            .feedLine()
                            .cutHalfAndFeed(1)
                    }
                    bitmap.recycle()
                    Handler(Looper.getMainLooper()).post {
                        result.success(true)
                    }
                    return@thread
                }

                // Dựng dữ liệu ảnh thô (GS v 0) sử dụng bộ nhị phân hóa chất lượng cao (threshold 200) để giữ nguyên chất lượng ảnh gốc của Flutter
                val rasterBytes = getEscPosRasterBytes(bitmap)
                bitmap.recycle()

                val stream = java.io.ByteArrayOutputStream()
                
                // 1. Initialize printer (ESC @)
                stream.write(byteArrayOf(0x1B, 0x40))
                
                // 2. Set alignment Center (ESC a 1)
                stream.write(byteArrayOf(0x1B, 0x61, 0x01))
                
                // 3. Write raster image data
                stream.write(rasterBytes)
                
                // 4. Feed 5 lines (LF)
                stream.write(byteArrayOf(0x0A, 0x0A, 0x0A, 0x0A, 0x0A))
                
                // 5. Cut paper (GS V 66 1)
                stream.write(byteArrayOf(0x1D, 0x56, 0x42, 0x01))
                
                val allBytes = stream.toByteArray()

                // Tuần tự hóa việc gửi TRÊN CÙNG máy này (khóa theo connection).
                // Các máy khác dùng khóa khác nên vẫn in song song, không đợi nhau.
                synchronized(lockFor(curConnect)) {
                    if (isBluetooth && !isTargetBuiltIn) {
                        // Cấu hình vừa tầm cân bằng cho máy in Bluetooth ngoài: Gói 120 bytes, delay 4ms, nghỉ 80ms mỗi 1500 bytes
                        val chunkSize = 120
                        var offset = 0
                        var bytesSentInBlock = 0
                        while (offset < allBytes.size) {
                            val count = Math.min(chunkSize, allBytes.size - offset)
                            val chunk = allBytes.copyOfRange(offset, offset + count)
                            val sent = curConnect.sendSync(chunk)
                            if (sent <= 0) {
                                throw java.io.IOException(
                                    "Gửi dữ liệu tới máy in Bluetooth thất bại tại byte " +
                                        "$offset/${allBytes.size} (sendSync trả về $sent)."
                                )
                            }
                            // Tiến theo số byte THẬT SỰ gửi được, không phải số muốn gửi.
                            offset += sent
                            bytesSentInBlock += sent

                            Thread.sleep(4)
                            if (bytesSentInBlock >= 1500) {
                                Thread.sleep(80)
                                bytesSentInBlock = 0
                            }
                        }
                    } else {
                        // USB/LAN/máy in tích hợp: cũng phải chia gói. Gửi cả cục cho đơn
                        // dài (ảnh vài chục–trăm KB) làm tràn buffer máy in/socket:
                        // sendSync chỉ gửi được một phần, phần còn lại bị mất. Máy in vẫn
                        // đợi cho đủ số byte mà lệnh GS v 0 đã khai báo nên treo luôn —
                        // ăn mất cả lệnh cắt và job in kế tiếp.
                        // Gói 4KB lớn hơn Bluetooth nhiều nên vẫn nhanh, không cần sleep.
                        sendAllSync(curConnect, allBytes, 4096)
                    }
                }

                Handler(Looper.getMainLooper()).post {
                    result.success(true)
                }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result.error("PRINT_ERROR", e.message, null)
                }
            }
        }
    }

    private fun getEscPosRasterBytes(bitmap: Bitmap): ByteArray {
        val width = bitmap.width
        val height = bitmap.height
        val widthBytes = (width + 7) / 8

        val stream = java.io.ByteArrayOutputStream()

        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        // Chia ảnh thành nhiều DẢI, mỗi dải là MỘT lệnh `GS v 0` riêng.
        //
        // Trước đây cả bill dài được nhồi vào một lệnh `GS v 0` duy nhất. Đơn ngắn thì
        // chạy tốt, nhưng đơn dài sinh ảnh cao hàng nghìn dòng — vượt giới hạn chiều cao
        // mỗi lệnh raster của máy in (máy Epson thường chỉ nhận vài trăm dòng/lệnh). Khi
        // vượt, máy in hủy chế độ raster và diễn giải các byte ảnh còn lại thành VĂN BẢN,
        // nên giấy ra đầy ký tự rác và không cắt.
        //
        // 128 dòng/dải nằm an toàn dưới giới hạn của mọi model phổ biến; các dải in liền
        // nhau nên ảnh vẫn liền mạch, không có khoảng trắng chen vào.
        val bandHeight = 128

        var y0 = 0
        while (y0 < height) {
            val bandRows = Math.min(bandHeight, height - y0)

            // GS v 0 m xL xH yL yH — yL/yH là chiều cao của DẢI này, luôn <= 128 nên
            // không bao giờ tràn 2 byte.
            stream.write(
                byteArrayOf(
                    0x1D, 0x76, 0x30, 0x00,
                    (widthBytes % 256).toByte(), (widthBytes / 256).toByte(),
                    (bandRows % 256).toByte(), (bandRows / 256).toByte()
                )
            )

            for (y in y0 until y0 + bandRows) {
                for (xByte in 0 until widthBytes) {
                    var byteVal = 0
                    for (bit in 0 until 8) {
                        val x = xByte * 8 + bit
                        if (x < width) {
                            val pixel = pixels[y * width + x]
                            val alpha = (pixel shr 24) and 0xff
                            if (alpha > 50) {
                                val red = (pixel shr 16) and 0xff
                                val green = (pixel shr 8) and 0xff
                                val blue = pixel and 0xff
                                val gray = (0.299 * red + 0.587 * green + 0.114 * blue).toInt()
                                // Ngưỡng 128 (giữa thang xám) là mức chuẩn cho nhị phân hoá.
                                //
                                // Ngưỡng 200 trước đây kéo cả pixel xám nhạt (180-199) của
                                // viền anti-alias thành đen tuyền, làm nét chữ phình ra lởm
                                // chởm — font càng lớn viền anti-alias càng dài nên càng lộ
                                // (dễ thấy ở cỡ 16-22). 128 chỉ giữ phần thân nét thật.
                                if (gray < 128) {
                                    byteVal = byteVal or (1 shl (7 - bit))
                                }
                            }
                        }
                    }
                    stream.write(byteVal)
                }
            }

            y0 += bandRows
        }

        return stream.toByteArray()
    }

    fun printTextESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        val printer = POSPrinter(curConnect)
        val text = call.argument<String>("text") ?: ""
        try {
            synchronized(lockFor(curConnect)) {
                printer.initializePrinter()
                    .printText(text, 0, POSConst.ALIGNMENT_LEFT, 0)
                    .feedLine()
                    .cutHalfAndFeed(1)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    fun printBarcodeESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        val printer = POSPrinter(curConnect)
        val code = call.argument<String>("code") ?: ""
        val typeVal = call.argument<String>("type") ?: "128"
        val width = call.argument<Int>("width") ?: 2
        val height = call.argument<Int>("height") ?: 162
        try {
            val type = when (typeVal) {
                "UPCA" -> 65
                "UPCE" -> 66
                "EAN13" -> 67
                "EAN8" -> 68
                "CODE39" -> 69
                "ITF" -> 70
                "CODEBAR" -> 71
                "CODE93" -> 72
                else -> 73
            }
            synchronized(lockFor(curConnect)) {
                printer.initializePrinter()
                    .printBarCode(code, type, width, height, 2)
                    .feedLine()
                    .cutHalfAndFeed(1)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    fun printQRCodeESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        val code = call.argument<String>("code") ?: ""
        val size = call.argument<Int>("size") ?: 8
        try {
            val stream = java.io.ByteArrayOutputStream()
            
            // 1. Initialize printer (ESC @)
            stream.write(byteArrayOf(0x1B, 0x40))
            
            // 2. Set alignment Center (ESC a 1)
            stream.write(byteArrayOf(0x1B, 0x61, 0x01))
            
            // 3. QR Code bytes
            val qrBytes = getQRCodeBytes(code, size)
            stream.write(qrBytes)
            
            // 4. Feed 5 lines (LF)
            stream.write(byteArrayOf(0x0A, 0x0A, 0x0A, 0x0A, 0x0A))
            
            // 5. Cut paper (GS V 66 1)
            stream.write(byteArrayOf(0x1D, 0x56, 0x42, 0x01))

            synchronized(lockFor(curConnect)) {
                curConnect.sendData(stream.toByteArray())
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    private fun getQRCodeBytes(code: String, size: Int): ByteArray {
        val bytes = code.toByteArray(Charsets.UTF_8)
        val pL = (bytes.size + 3) % 256
        val pH = (bytes.size + 3) / 256
        
        val stream = java.io.ByteArrayOutputStream()
        
        // Set model (Model 2)
        stream.write(byteArrayOf(0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x31, 0x00))
        
        // Set size
        stream.write(byteArrayOf(0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size.toByte()))
        
        // Set error correction level (L)
        stream.write(byteArrayOf(0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x44, 0x30))
        
        // Store data
        stream.write(byteArrayOf(0x1D, 0x28, 0x6B, pL.toByte(), pH.toByte(), 0x31, 0x50, 0x30))
        stream.write(bytes)
        
        // Print QR code
        stream.write(byteArrayOf(0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30))
        
        return stream.toByteArray()
    }

    fun openDrawer(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        try {
            val stream = java.io.ByteArrayOutputStream()
            // ESC p 0 25 250 (Pin 2) & ESC p 1 25 250 (Pin 5)
            stream.write(byteArrayOf(0x1B, 0x70, 0x00, 0x19, 0xFA.toByte(), 0x1B, 0x70, 0x01, 0x19, 0xFA.toByte()))
            val bytes = stream.toByteArray()
            synchronized(lockFor(curConnect)) {
                curConnect.sendData(bytes)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }
}