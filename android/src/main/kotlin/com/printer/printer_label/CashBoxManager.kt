package com.printer.printer_label

import android.content.Context
import android.os.Build
import android.os.IBinder

/**
 * Quản lý mở két tiền (CashBox RJ12 / RJ11) trực tiếp trên các thiết bị POS Android 
 * (iMin, Sunmi, Urovo, Pax, Telpo, Landicorp, Smartpeak, Kozen, v.v.)
 * thông qua Java Reflection gọi vào System OS Service của từng hãng mà không cần máy in rời.
 */
object CashBoxManager {

    // Danh sách từ khóa các hãng máy POS phổ biến có cổng RJ11/RJ12 trên thiết bị
    private val POS_VENDOR_KEYWORDS = listOf(
        "imin", "swan", "i24d", 
        "sunmi", "urovo", "pax", 
        "telpo", "landicorp", "smartpeak", 
        "kozen", "centerm", "hisense", "wizarpos"
    )

    fun isSupportedDevice(): Boolean {
        return try {
            val manufacturer = Build.MANUFACTURER.lowercase()
            val model = Build.MODEL.lowercase()
            val brand = Build.BRAND.lowercase()

            // 1. Kiểm tra theo tên thương hiệu / model máy POS
            val isKnownPosVendor = POS_VENDOR_KEYWORDS.any { keyword ->
                manufacturer.contains(keyword) || brand.contains(keyword) || model.contains(keyword)
            }
            if (isKnownPosVendor) return true

            // 2. Thử kiểm tra sự tồn tại của Service hệ thống két tiền
            hasSystemCashBoxService()
        } catch (t: Throwable) {
            false
        }
    }

    private fun hasSystemCashBoxService(): Boolean {
        return try {
            val smClass = Class.forName("android.os.ServiceManager")
            val getServiceMethod = smClass.getMethod("getService", String::class.java)
            val iminService = getServiceMethod.invoke(null, "iminservice")
            val sunmiService = getServiceMethod.invoke(null, "sunmi_printer")
            iminService != null || sunmiService != null
        } catch (t: Throwable) {
            false
        }
    }

    fun openCashBox(context: Context?): Boolean {
        return try {
            if (!isSupportedDevice()) return false
            executeOpenCashBox(context)
        } catch (t: Throwable) {
            false
        }
    }

    private fun executeOpenCashBox(context: Context?): Boolean {
        // --- 1. HÃNG IMIN (iMin Swan 1, Swan 2, D4, D3, D2, M2...) ---
        if (tryOpenIminCashBox(context)) return true

        // --- 2. HÃNG SUNMI (Sunmi T2, T2s, D2, S2, V2...) ---
        if (tryOpenSunmiCashBox(context)) return true

        // --- 3. HÃNG UROVO ---
        if (tryOpenUrovoCashBox(context)) return true

        return false
    }

    /**
     * Kích mở két native trên thiết bị iMin OS
     */
    private fun tryOpenIminCashBox(context: Context?): Boolean {
        // 1.1 Thử ServiceManager.getService("iminservice")
        try {
            val smClass = Class.forName("android.os.ServiceManager")
            val getServiceMethod = smClass.getMethod("getService", String::class.java)
            val binder = getServiceMethod.invoke(null, "iminservice") as? IBinder
            if (binder != null) {
                val stubClass = Class.forName("android.os.imin.IIMinService\$Stub")
                val asInterfaceMethod = stubClass.getMethod("asInterface", IBinder::class.java)
                val iMinService = asInterfaceMethod.invoke(null, binder)
                if (iMinService != null) {
                    val methods = iMinService.javaClass.declaredMethods
                    for (m in methods) {
                        if (m.name.equals("openCashBox", ignoreCase = true)) {
                            m.isAccessible = true
                            if (m.parameterTypes.isEmpty()) {
                                m.invoke(iMinService)
                                return true
                            } else if (m.parameterTypes.size == 1 && m.parameterTypes[0] == Boolean::class.javaPrimitiveType) {
                                m.invoke(iMinService, true)
                                return true
                            } else if (m.parameterTypes.size == 1 && m.parameterTypes[0] == Int::class.javaPrimitiveType) {
                                m.invoke(iMinService, 1)
                                return true
                            }
                        }
                    }
                }
            }
        } catch (t: Throwable) {}

        // 1.2 Thử SystemApi của iMin
        try {
            val sysClass = Class.forName("com.imin.library.SystemApi")
            val instanceMethod = sysClass.getMethod("getInstance")
            val instance = instanceMethod.invoke(null)
            if (instance != null) {
                val methods = instance.javaClass.declaredMethods
                for (m in methods) {
                    if (m.name.equals("openCashBox", ignoreCase = true)) {
                        m.isAccessible = true
                        if (m.parameterTypes.isEmpty()) {
                            m.invoke(instance)
                            return true
                        } else if (m.parameterTypes.size == 1 && m.parameterTypes[0] == Context::class.java) {
                            m.invoke(instance, context)
                            return true
                        }
                    }
                }
            }
        } catch (t: Throwable) {}

        // 1.3 Thử IminPrintUtils
        try {
            val iminClass = Class.forName("com.imin.printerlib.IminPrintUtils")
            val instanceMethod = iminClass.getMethod("getInstance")
            val instance = instanceMethod.invoke(null)
            if (instance != null) {
                if (context != null) {
                    try {
                        val initMethod = iminClass.getMethod("initPrinter", Context::class.java)
                        initMethod.invoke(instance, context)
                    } catch (t: Throwable) {}
                }
                val openMethod = iminClass.getMethod("openCashBox")
                openMethod.invoke(instance)
                return true
            }
        } catch (t: Throwable) {}

        // 1.4 Broadcast Intent iMin
        if (context != null) {
            try {
                val intent = android.content.Intent("net.imin.printer.openCashBox")
                intent.setPackage("net.imin.printer")
                context.sendBroadcast(intent)
                return true
            } catch (t: Throwable) {}
        }

        return false
    }

    /**
     * Kích mở két native trên thiết bị Sunmi OS
     */
    private fun tryOpenSunmiCashBox(context: Context?): Boolean {
        if (context == null) return false
        try {
            val intent = android.content.Intent("com.sunmi.drawer.OPEN")
            intent.setPackage("com.sunmi.extprinterservice")
            context.sendBroadcast(intent)
            return true
        } catch (t: Throwable) {}

        try {
            val intent = android.content.Intent("woyou.aidl.service.openDrawer")
            intent.setPackage("woyou.aidl.service")
            context.sendBroadcast(intent)
            return true
        } catch (t: Throwable) {}

        return false
    }

    /**
     * Kích mở két native trên thiết bị Urovo OS
     */
    private fun tryOpenUrovoCashBox(context: Context?): Boolean {
        try {
            val printerClass = Class.forName("android.device.PrinterManager")
            val instance = printerClass.newInstance()
            val openDrawerMethod = printerClass.getMethod("openDrawer")
            openDrawerMethod.invoke(instance)
            return true
        } catch (t: Throwable) {}
        return false
    }
}
