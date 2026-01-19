package com.printer.printer_label

import android.annotation.TargetApi
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
import android.hardware.usb.UsbManager
import android.os.Build
import android.widget.Toast
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import net.posprinter.IConnectListener
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.POSConst
import net.posprinter.POSPrinter
import net.posprinter.TSPLConst
import net.posprinter.TSPLPrinter
import net.posprinter.model.AlgorithmType

/** SamplePluginFlutterPlugin */
class PrinterLabelPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var CHANNEL = "flutter_printer_label"
    public var mContext: Context? = null
    var curConnect: IDeviceConnection? = null
    private var pendingConnectResult: MethodChannel.Result? = null
    private var pendingConnectType: String? = null
    private lateinit var usbReceiver: UsbConnectionReceiver
    private var printThermal = PrinterThermal()
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL)
        channel.setMethodCallHandler(this)
        mContext = flutterPluginBinding.getApplicationContext()
        POSConnect.init(mContext)
        usbReceiver = UsbConnectionReceiver(channel, this)
        val filter = IntentFilter(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        flutterPluginBinding.applicationContext.registerReceiver(usbReceiver, filter)
        checkAndRequestUsbPermission(mContext!!)
    }

    @RequiresApi(Build.VERSION_CODES.HONEYCOMB_MR1)
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")

            "checkConnect" -> {
                result.success(curConnect?.isConnect() ?: false)
            }

            "disconnect" -> {
                disconnectPrinter(result)
            }

            "connect_lan" -> {
                val ipAddress = call.argument<String>("ip_address")
                if (ipAddress.isNullOrEmpty()) {
                    result.success(false)
                    return
                }
                connectNet(ipAddress,result)
            }

            "print_barcode" -> {
                printBarcode(call, result)

            }

            "print_label" -> {
                printLabel(call, result)
            }

            "print_image_esc" -> {
                printThermal.printImageESC(call, curConnect!!, result)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun disconnectPrinter(result: MethodChannel.Result) {
        try {
            curConnect?.close()
            curConnect = null
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCONNECT_ERROR", e.message, null)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        curConnect?.close()
        curConnect = null
        binding.applicationContext.unregisterReceiver(usbReceiver)
    }

    private val connectListener = IConnectListener { code, connInfo, msg ->
        val type = pendingConnectType ?: "UNKNOWN"
        when (code) {
            POSConnect.CONNECT_SUCCESS -> {
                pendingConnectResult?.success(true)
                pendingConnectResult = null
                toast("Kết nối ${type} thành công!")
            }

            POSConnect.CONNECT_FAIL -> {
                toast("Kết nối ${type} thất bại!")
                pendingConnectResult?.success(false)
                pendingConnectResult = null
            }

            POSConnect.CONNECT_INTERRUPT -> {
                toast("Kết nối ${type} bị gián đoạn!")
                pendingConnectResult?.success(false)
                pendingConnectResult = null
            }

            POSConnect.SEND_FAIL -> {
                toast("SEND_FAIL")
            }

            POSConnect.USB_DETACHED -> {
                toast("USB_DETACHED")
            }

            POSConnect.USB_ATTACHED -> {
                toast("USB_ATTACHED")
            }
        }
    }

    private fun toast(str: String) {
        Toast.makeText(mContext, str, Toast.LENGTH_SHORT).show()
    }

    @TargetApi(Build.VERSION_CODES.O)
    fun checkAndRequestUsbPermission(context: Context) {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val deviceList = usbManager.deviceList

        if (deviceList.isEmpty()) {
            return
        }

        val usbDevice = deviceList.values.firstOrNull() ?: return

        if (usbManager.hasPermission(usbDevice)) {
            connectUSB(usbDevice.deviceName)
        } else {
            val permissionIntent = PendingIntent.getBroadcast(
                context, 0, Intent(ACTION_USB_PERMISSION), PendingIntent.FLAG_IMMUTABLE
            )
            val usbReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == ACTION_USB_PERMISSION) {
                        if (usbManager.hasPermission(usbDevice)) {
                            connectUSB(usbDevice.deviceName)
                        }
                        context?.unregisterReceiver(this)
                    }
                }
            }
            val filter = IntentFilter(ACTION_USB_PERMISSION)
            context.registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED)
            usbManager.requestPermission(usbDevice, permissionIntent)
        }
    }


    fun connectUSB(pathName: String) {
        pendingConnectType = "USB"
        curConnect?.close()
        curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_USB)
        curConnect?.connect(pathName, connectListener)
    }

    private fun connectNet(ipAddress: String, result: MethodChannel.Result) {
        try {
            pendingConnectResult = result
            pendingConnectType = "LAN"
            curConnect?.close()
            curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_ETHERNET)
            curConnect?.connect(ipAddress, connectListener)

        } catch (e: Exception) {
            pendingConnectResult?.error("CONNECT_ERROR", e.message, null)
            pendingConnectResult = null
        }
    }


    private fun connectBt(macAddress: String) {
        curConnect?.close()
        curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_BLUETOOTH)
        curConnect!!.connect(macAddress, connectListener)
    }

    private fun connectMAC(macAddress: String) {
        curConnect?.close()
        curConnect = POSConnect.connectMac(macAddress, connectListener)
    }

    private fun connectSerial(port: String, boudrate: String) {
        curConnect?.close()
        curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_SERIAL)
        curConnect!!.connect("$port,$boudrate", connectListener)
    }


    private fun printBarcode(call: MethodCall, result: MethodChannel.Result) {
        val size = call.argument<Map<String, Double>>("size")
        val gap = call.argument<Map<String, Double>>("gap")
        val barcode = call.argument<Map<String, Any>>("barcode")
        val textList = call.argument<List<Map<String, Any>>>("text")
        val quantity = call.argument<Int>("quantity") ?: 1
        val (sizeWidth, sizeHeight) = extractSize(size)
        val (gapWidth, gapHeight) = extractGap(gap)
        // Initialize printer
        val printer = TSPLPrinter(curConnect)
        printer.sizeMm(sizeWidth, sizeHeight)
        printer.gapMm(gapWidth, gapHeight)
        printer.cls()
        barcode?.let {
            processBarcode(it, printer)
        }

        // Process text
        textList?.forEach { text ->
            processText(text, printer)
        }

        printer.print(quantity)
        result.success("Printed Successfully")

    }

    // Function to extract size from the map
    private fun extractSize(size: Map<String, Double>?): Pair<Double, Double> {
        val width = size?.get("width") ?: 200.0
        val height = size?.get("height") ?: 30.0
        return Pair(width, height)
    }

    // Function to extract gap from the map
    private fun extractGap(gap: Map<String, Double>?): Pair<Double, Double> {
        val width = gap?.get("width") ?: 0.0
        val height = gap?.get("height") ?: 0.0
        return Pair(width, height)
    }

    private fun extractSizeImage(size: Map<String, Int>?): Pair<Int, Int> {
        val width = size?.get("width") ?: 600
        val height = size?.get("height") ?: 20
        return Pair(width, height)
    }

    private fun processBarcode(barcode: Map<String, Any>, printer: TSPLPrinter) {
        val barcodeX = barcode["x"] as? Int ?: 0
        val barcodeY = barcode["y"] as? Int ?: 30
        val barcodeType = barcode["type"] as? String ?: TSPLConst.CODE_TYPE_93
        val barcodeHeight = barcode["height"] as? Int ?: 100
        val barcodeContent = barcode["barcodeContent"] as? String ?: ""
        printer.barcode(
            barcodeX, barcodeY, barcodeType, barcodeHeight, TSPLConst.READABLE_CENTER,
            TSPLConst.ROTATION_0, 2, 2, barcodeContent
        )
    }

    private fun processText(text: Map<String, Any>, printer: TSPLPrinter) {
        val textX = text["x"] as? Int ?: 0
        val textY = text["y"] as? Int ?: 144
        val font = text["font"] as? String ?: TSPLConst.FNT_16_24
        val rotation = text["rotation"] as? Int ?: TSPLConst.ROTATION_0
        val sizeX = text["sizeX"] as? Int ?: 1
        val sizeY = text["sizeY"] as? Int ?: 1
        val textData = text["data"] as? String ?: ""

        printer.text(textX, textY, font, rotation, sizeX, sizeY, textData)
    }

    private fun printLabel(call: MethodCall, result: MethodChannel.Result) {
        try {
            val type = call.argument<String>("type")
            if (type != "TSPL") {
                result.success(false)
                return
            }
            val images: List<ByteArray>? = call.argument<List<ByteArray>>("images")
            if (images.isNullOrEmpty()) {
                result.success(false)
                return
            }

            val printer = TSPLPrinter(curConnect)

            images.forEach { imageData ->
                val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
                if (bitmap != null) {
                    val size = call.argument<Map<String, Int>>("size")
                    val (sizeWidth, sizeHeight) = extractSizeImage(size)

                    val x = call.argument<Int>("x") ?: 0
                    val y = call.argument<Int>("y") ?: 0
                    val width = 900

                    printer
                        .sizeMm(sizeWidth.toDouble(), sizeHeight.toDouble())
                        .cls()
                        .bitmap(
                            x,
                            y,
                            TSPLConst.BMP_MODE_OVERWRITE,
                            width,
                            bitmap,
                            AlgorithmType.Threshold
                        )
                        .print(1)
                }
            }

            result.success(true)

        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }


    companion object {
        private const val ACTION_USB_PERMISSION = "com.example.USB_PERMISSION"
    }
}

