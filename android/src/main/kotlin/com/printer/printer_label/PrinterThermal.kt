package com.printer.printer_label

import android.graphics.BitmapFactory
import net.posprinter.IDeviceConnection
import net.posprinter.POSConst
import net.posprinter.POSPrinter
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PrinterThermal {
    fun printTiket(call: MethodCall, curConnect: IDeviceConnection, result: MethodChannel.Result) {
        val printer = POSPrinter(curConnect)

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
                    .printBitmap(bitmap, POSConst.ALIGNMENT_CENTER, size ?: 384)
                    .feedLine()
                    .cutHalfAndFeed(1)
            result.success(printResult)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }
}