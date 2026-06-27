package com.printer.printer_label

import android.graphics.BitmapFactory
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.posprinter.IDeviceConnection
import net.posprinter.POSConst
import net.posprinter.POSPrinter

class PrinterThermal {
    fun printImageESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        val printer = POSPrinter(curConnect)
        val type = call.argument<String>("type")
        if (type != "ESC") {
            result.success(false)
            return
        }
        try {
            val image: ByteArray? = call.argument<ByteArray>("image")
            val size: Int? = call.argument<Int>("size")

            if (image == null) {
                result.error("PRINT_ERROR", "Image data is null", null)
                return
            }

            val bitmap = BitmapFactory.decodeByteArray(image, 0, image.size)
            val printResult =
                printer.initializePrinter()
                    .printBitmap(bitmap, POSConst.ALIGNMENT_CENTER, size ?: 576)
                    .feedLine()
                    .cutHalfAndFeed(1)
            result.success(printResult)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    fun printTextESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        val printer = POSPrinter(curConnect)
        val text = call.argument<String>("text") ?: ""
        try {
            val printResult =
                printer.initializePrinter()
                    .printText(text, 0, POSConst.ALIGNMENT_LEFT, 0)
                    .feedLine()
                    .cutHalfAndFeed(1)
            result.success(printResult)
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
            val printResult =
                printer.initializePrinter()
                    .printBarCode(code, type, width, height, 2)
                    .feedLine()
                    .cutHalfAndFeed(1)
            result.success(printResult)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    fun printQRCodeESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        val printer = POSPrinter(curConnect)
        val code = call.argument<String>("code") ?: ""
        val size = call.argument<Int>("size") ?: 8
        try {
            val printResult =
                printer.initializePrinter()
                    .printQRCode(code, size)
                    .feedLine()
                    .cutHalfAndFeed(1)
            result.success(printResult)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }
}