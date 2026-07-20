package com.printer.printer_label

import android.graphics.Bitmap
import android.os.Build

/**
 * Quản lý máy in nội bộ của Urovo thông qua Java Reflection.
 * Cách này giúp gọi trực tiếp vào SDK của Urovo (`android.device.PrinterManager`)
 * mà không cần phải nhúng file .jar của SDK vào project.
 */
class UrovoPrinterManager {
    private var printerManagerObj: Any? = null
    private var printerManagerClass: Class<*>? = null

    init {
        try {
            printerManagerClass = Class.forName("android.device.PrinterManager")
            printerManagerObj = printerManagerClass?.newInstance()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun isSupported(): Boolean {
        return printerManagerObj != null
    }

    fun openPrinter(): Boolean {
        if (!isSupported()) return false
        return try {
            val openMethod = printerManagerClass?.getMethod("open")
            openMethod?.invoke(printerManagerObj)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun closePrinter() {
        if (!isSupported()) return
        try {
            val closeMethod = printerManagerClass?.getMethod("close")
            closeMethod?.invoke(printerManagerObj)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun setupPage(width: Int, height: Int) {
        if (!isSupported()) return
        try {
            val setupPageMethod = printerManagerClass?.getMethod("setupPage", Int::class.javaPrimitiveType, Int::class.javaPrimitiveType)
            setupPageMethod?.invoke(printerManagerObj, width, height)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun drawBitmap(bitmap: Bitmap, x: Int, y: Int) {
        if (!isSupported()) return
        try {
            val drawBitmapMethod = printerManagerClass?.getMethod("drawBitmap", Bitmap::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType)
            drawBitmapMethod?.invoke(printerManagerObj, bitmap, x, y)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    fun drawText(text: String, x: Int, y: Int, fontName: String, fontSize: Int, isBold: Boolean, isItalic: Boolean, rotate: Int) {
        if (!isSupported()) return
        try {
            val drawTextMethod = printerManagerClass?.getMethod("drawText", String::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType, String::class.java, Int::class.javaPrimitiveType, Boolean::class.javaPrimitiveType, Boolean::class.javaPrimitiveType, Int::class.javaPrimitiveType)
            drawTextMethod?.invoke(printerManagerObj, text, x, y, fontName, fontSize, isBold, isItalic, rotate)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun printPage(rotate: Int): Int {
        if (!isSupported()) return -1
        return try {
            val printPageMethod = printerManagerClass?.getMethod("printPage", Int::class.javaPrimitiveType)
            val result = printPageMethod?.invoke(printerManagerObj, rotate)
            result as? Int ?: -1
        } catch (e: Exception) {
            e.printStackTrace()
            -1
        }
    }

    fun paperFeed(step: Int) {
        if (!isSupported()) return
        try {
            val paperFeedMethod = printerManagerClass?.getMethod("paperFeed", Int::class.javaPrimitiveType)
            paperFeedMethod?.invoke(printerManagerObj, step)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun setSpeedLevel(level: Int) {
        if (!isSupported()) return
        try {
            val setSpeedMethod = printerManagerClass?.getMethod("setSpeedLevel", Int::class.javaPrimitiveType)
            setSpeedMethod?.invoke(printerManagerObj, level)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun setGrayLevel(level: Int) {
        if (!isSupported()) return
        try {
            val setGrayMethod = printerManagerClass?.getMethod("setGrayLevel", Int::class.javaPrimitiveType)
            setGrayMethod?.invoke(printerManagerObj, level)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun prnDrawText(text: String, x: Int, y: Int, fontName: String, fontSize: Int, bold: Boolean, italic: Boolean, rotate: Int) {
        if (!isSupported()) return
        try {
            val method = printerManagerClass?.getMethod(
                "prn_drawText", 
                String::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType, 
                String::class.java, Int::class.javaPrimitiveType, Boolean::class.javaPrimitiveType, 
                Boolean::class.javaPrimitiveType, Int::class.javaPrimitiveType
            )
            method?.invoke(printerManagerObj, text, x, y, fontName, fontSize, bold, italic, rotate)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun drawBarcode(data: String, x: Int, y: Int, barcodeType: Int, width: Int, height: Int, rotate: Int) {
        if (!isSupported()) return
        try {
            val method = printerManagerClass?.getMethod(
                "drawBarcode",
                String::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType
            )
            method?.invoke(printerManagerObj, data, x, y, barcodeType, width, height, rotate)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    // Kiểm tra nhanh xem đây có phải là thiết bị Urovo không
    companion object {
        fun isUrovoDevice(): Boolean {
            val manufacturer = Build.MANUFACTURER.lowercase()
            val model = Build.MODEL.lowercase()
            return manufacturer.contains("urovo") || model.contains("urovo") || model.contains("i9100")
        }
    }
}
