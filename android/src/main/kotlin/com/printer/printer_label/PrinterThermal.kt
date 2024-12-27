package com.printer.printer_label

import android.graphics.BitmapFactory
import net.posprinter.IDeviceConnection
import net.posprinter.POSConst
import net.posprinter.POSPrinter
import io.flutter.plugin.common.MethodCall
class PrinterThermal {
    fun printImage(call: MethodCall, curConnect: IDeviceConnection) {
        val printer = POSPrinter(curConnect);
        val image: ByteArray? = call.argument<ByteArray>("image")
        val size: Int? = call.argument<Int>("size")
        if (image != null) {
            val bitmap = BitmapFactory.decodeByteArray(image, 0, image.size)
            printer.initializePrinter()
                .printBitmap(bitmap, POSConst.ALIGNMENT_CENTER, size ?: 384)
                .feedLine()
                .cutHalfAndFeed(1)
        }
    }
}