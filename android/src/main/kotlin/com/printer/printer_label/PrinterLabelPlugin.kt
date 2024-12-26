package com.printer.printer_label

import android.app.PendingIntent
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
    private var curConnect: IDeviceConnection? = null
    private lateinit var usbReceiver: UsbConnectionReceiver
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL)
        channel.setMethodCallHandler(this)
        mContext = flutterPluginBinding.getApplicationContext()
        POSConnect.init(mContext)
        usbReceiver = UsbConnectionReceiver(channel, this)
        val filter = IntentFilter(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        flutterPluginBinding.applicationContext.registerReceiver(usbReceiver, filter)
    }

    @RequiresApi(Build.VERSION_CODES.HONEYCOMB_MR1)
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "connect_usb" -> {
                actitonConnectUSB()
            }

            "connect_lan" -> {
                val ipAddress = call.argument<String>("ip_address")
                if (!ipAddress.isNullOrEmpty()) {
                    connectNet(ipAddress)
                }
            }

            "print_barcode" -> {
                printBarcode(call, result)

            }

            "print_image" -> {
                printImage(call, result)
            }

            "print_multiLabel" -> {
                printMultiLabel(call)
            }

            "print_thermal" -> {
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

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        binding.applicationContext.unregisterReceiver(usbReceiver)
    }

    private val connectListener = IConnectListener { code, connInfo, msg ->
        when (code) {
            POSConnect.CONNECT_SUCCESS -> {
                toast("CONNECT_SUCCESS")
                channel.invokeMethod("connectionStatus", true)
            }

            POSConnect.CONNECT_FAIL -> {
                toast("CONNECT_FAIL")
                channel.invokeMethod("connectionStatus", false)
            }

            POSConnect.CONNECT_INTERRUPT -> {
                toast("CONNECT_INTERRUPT")
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

    @RequiresApi(Build.VERSION_CODES.HONEYCOMB_MR1)
    fun actitonConnectUSB() {
        val pathName = getUsbDevicePath(mContext!!)
        if (pathName != null) {
            connectUSB(pathName)
        }
    }

    @RequiresApi(Build.VERSION_CODES.HONEYCOMB_MR1)
    fun getUsbDevicePath(context: Context): String? {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val deviceList = usbManager.deviceList
        if (deviceList.isNotEmpty()) {
            val usbDevice = deviceList.values.firstOrNull()
            if (usbDevice != null && usbManager.hasPermission(usbDevice)) {
                return usbDevice.deviceName
            } else {
                val permissionIntent = PendingIntent.getBroadcast(
                    context, 0, Intent(ACTION_USB_PERMISSION), PendingIntent.FLAG_IMMUTABLE
                )
                usbManager.requestPermission(usbDevice, permissionIntent)
            }
        }
        return null
    }

    fun connectUSB(pathName: String) {
        curConnect?.close()
        curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_USB)
        curConnect!!.connect(pathName, connectListener)

    }

    private fun connectNet(ipAddress: String) {
        curConnect?.close()
        curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_ETHERNET)
        curConnect!!.connect(ipAddress, connectListener)
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

    private fun extractSizeImage(size: Map<String, Double>?): Pair<Double, Double> {
        val width = size?.get("width") ?: 600.0
        val height = size?.get("height") ?: 30.0
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

    private fun printImage(call: MethodCall, result: MethodChannel.Result) {
        try {
            val printer = TSPLPrinter(curConnect)
            val productList: List<Map<String, Any>> = call.argument("products") ?: run {
                result.error("INVALID_ARGUMENT", "Products argument is missing", null)
                return
            }
            for (product in productList) {
                val imageData: ByteArray? = product["image_data"] as? ByteArray
                if (imageData != null) {
                    val quantity = product["quantity"] as? Int ?: 1
                    val size = product["size"] as? Map<String, Double>
                    val (sizeWidth, sizeHeight) = extractSizeImage(size)
                    val width = product["widthImage"] as? Int ?: 600
                    val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
                    val x = product["x"] as? Int ?: 0
                    val y = product["y"] as? Int ?: 50
                    if (bitmap != null) {
                        printer.sizeMm(sizeWidth, sizeHeight)
                            .cls()
                            .bitmap(
                                x,
                                y,
                                TSPLConst.BMP_MODE_OVERWRITE,
                                width,
                                bitmap,
                                AlgorithmType.Threshold
                            )
                            .print(quantity)
                    }
                }
            }
            result.success(true)
        } catch (e: Exception) {
            // Trả kết quả lỗi về Flutter
            result.error("PRINT_ERROR", "Failed to print image: ${e.message}", null)
        }
    }

    private fun printMultiLabel(call: MethodCall) {
        val images: List<ByteArray>? = call.argument<List<ByteArray>>("images")
        val printer = TSPLPrinter(curConnect)
        images?.forEach { imageData ->
            val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
            if (bitmap != null) {
                val size = call.argument<Map<String, Double>>("size")
                val (sizeWidth, sizeHeight) = extractSizeImage(size)
                val width = call.argument<Int>("widthImage") ?: 600
                val x = call.argument<Int>("x") ?: 0
                val y = call.argument<Int>("y") ?: 50
                val quantity = 1
                printer.sizeMm(sizeWidth, sizeHeight)
                    .cls()
                    .bitmap(
                        x,
                        y,
                        TSPLConst.BMP_MODE_OVERWRITE,
                        width,
                        bitmap,
                        AlgorithmType.Threshold
                    )
                    .print(quantity)
            }
        }
    }

    companion object {
        private const val ACTION_USB_PERMISSION = "com.example.USB_PERMISSION"
    }
}

