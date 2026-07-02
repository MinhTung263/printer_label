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

                if (isBluetooth && !isTargetBuiltIn) {
                    // Cấu hình vừa tầm cân bằng cho máy in Bluetooth ngoài: Gói 120 bytes, delay 4ms, nghỉ 80ms mỗi 1500 bytes
                    val chunkSize = 120
                    var offset = 0
                    var bytesSentInBlock = 0
                    while (offset < allBytes.size) {
                        val count = Math.min(chunkSize, allBytes.size - offset)
                        val chunk = allBytes.copyOfRange(offset, offset + count)
                        curConnect.sendSync(chunk)
                        offset += count
                        bytesSentInBlock += count
                        
                        Thread.sleep(4)
                        if (bytesSentInBlock >= 1500) {
                            Thread.sleep(80)
                            bytesSentInBlock = 0
                        }
                    }
                } else {
                    // In lập tức không trễ đối với cổng USB, LAN hoặc máy in tích hợp sẵn
                    curConnect.sendSync(allBytes)
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
        
        // GS v 0 0 xL xH yL yH
        val xL = widthBytes % 256
        val xH = widthBytes / 256
        val yL = height % 256
        val yH = height / 256
        
        stream.write(byteArrayOf(0x1D, 0x76, 0x30, 0x00, xL.toByte(), xH.toByte(), yL.toByte(), yH.toByte()))
        
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        
        for (y in 0 until height) {
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
                            // Tăng ngưỡng lên 200 giúp giữ nguyên chất lượng ảnh gốc, làm chữ in ra đen đậm, sắc nét
                            if (gray < 200) {
                                byteVal = byteVal or (1 shl (7 - bit))
                            }
                        }
                    }
                }
                stream.write(byteVal)
            }
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
            printer.initializePrinter()
                .printText(text, 0, POSConst.ALIGNMENT_LEFT, 0)
                .feedLine()
                .cutHalfAndFeed(1)
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
            printer.initializePrinter()
                .printBarCode(code, type, width, height, 2)
                .feedLine()
                .cutHalfAndFeed(1)
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
            
            curConnect.sendData(stream.toByteArray())
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
}