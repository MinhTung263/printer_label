package com.printer.printer_label

import android.content.Context
import android.os.Build

/**
 * Kiểm tra xem thiết bị hiện tại có thuộc các hãng sản xuất máy POS tích hợp sẵn máy in hay không.
 */
fun isBuiltInPrinter(): Boolean {
    val manufacturer = Build.MANUFACTURER.lowercase()
    val model = Build.MODEL.lowercase()
    return manufacturer.contains("sunmi") ||
           manufacturer.contains("imin") ||
           manufacturer.contains("pax") ||
           manufacturer.contains("urovo") ||
           manufacturer.contains("smartpeak") ||
           manufacturer.contains("kozen") ||
           model.contains("sunmi") ||
           model.contains("imin") ||
           model.contains("pax") ||
           model.contains("urovo") ||
           model.contains("b68") ||
           model.contains("p068")
}

/**
 * Quét các gói package của hệ điều hành để xác định thiết bị có cài đặt Service máy in tích hợp hay không.
 */
fun hasBuiltInPrinter(context: Context?): Boolean {
    // 1. Kiểm tra nhanh thông qua Manufacturer và Model để tránh bị giới hạn Package Visibility trên Android 11+
    if (isBuiltInPrinter()) {
        return true
    }

    // 2. Kiểm tra package service nếu phương pháp trên không khớp
    val ctx = context ?: return false
    val pm = ctx.packageManager
    
    // Các package service máy in phổ biến của các hãng POS (Sunmi, iMin, Pax, Landi, Urovo, v.v.)
    val printerPackages = arrayOf(
        "com.sunmi.printerservice",         // Sunmi
        "woyou.aidl.service",               // Sunmi/iMin AIDL Service
        "net.imin.printer",                 // iMin
        "com.pax.sz.printerservice",        // Pax
        "com.landicorp.android.pinpadservice", // Landi
        "com.urovo.printerservice",         // Urovo Service
        "android.printservice.urovoprint"   // Urovo Print
    )

    for (pkg in printerPackages) {
        try {
            pm.getPackageInfo(pkg, 0)
            return true
        } catch (e: Exception) {
            // Tiếp tục kiểm tra package khác
        }
    }

    return false
}

/**
 * Lấy khổ giấy của máy in tích hợp sẵn (58mm hoặc 80mm).
 */
fun getBuiltInPrinterPaperSize(context: Context?): Int {
    if (!isBuiltInPrinter()) return 0
    
    // 1. Kiểm tra thuộc tính hệ thống (System Properties) của Sunmi
    val sunmiPaperProp = getSystemProperty("ro.sunmi.printer.paper") // "0" đại diện 80mm, "1" đại diện 58mm
    if (sunmiPaperProp == "0") return 80
    if (sunmiPaperProp == "1") return 58
    
    val sunmiHardwareProp = getSystemProperty("ro.sunmi.hardware.printer")
    if (sunmiHardwareProp.contains("80")) return 80
    if (sunmiHardwareProp.contains("58")) return 58
    
    // 2. Nhận dạng theo nhóm Model máy để phân biệt máy cầm tay và máy tính để bàn
    val model = Build.MODEL.lowercase()
    val isDesktopModel = model.contains("t1") || 
                         model.contains("t2") || 
                         model.contains("s2") || 
                         model.contains("d2") || 
                         model.contains("d3") || 
                         model.contains("d4") ||
                         model.contains("swan") ||
                         model.contains("mix")
                         
    if (isDesktopModel) {
        return 80
    }
    
    // Mặc định đối với các thiết bị POS cầm tay (V2, V2s, V3, M2, A920, Urovo...) là khổ giấy 58mm
    return 58
}

private fun getSystemProperty(key: String): String {
    return try {
        val c = Class.forName("android.os.SystemProperties")
        val get = c.getMethod("get", String::class.java)
        get.invoke(c, key) as String
    } catch (e: Exception) {
        ""
    }
}
