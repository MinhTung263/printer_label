package com.example.printer_label//package com.example.printer_label

import android.content.Context
import android.graphics.BitmapFactory
import android.hardware.usb.UsbManager
import android.os.Bundle
import com.example.printer_label.utils.Constant
import com.example.printer_label.utils.UIUtils
import com.jeremyliao.liveeventbus.LiveEventBus
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import net.posprinter.IConnectListener
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.TSPLConst
import net.posprinter.TSPLPrinter
import net.posprinter.model.AlgorithmType

class MainActivity: FlutterActivity(){
    private var curConnect: IDeviceConnection? = null
    private val CHANNEL = "flutter_printer_label"
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Register Flutter plugins
        GeneratedPluginRegistrant.registerWith(flutterEngine!!)
        // Initialize POSConnect
        POSConnect.init(this)  // Initialize POSConnect library

        getStatusConnectUsb()
        connectMethod()
    }
    private val connectListener = IConnectListener { code,connInfo, msg ->
        when (code) {
            POSConnect.CONNECT_SUCCESS -> {
                //UIUtils.toast(this, R.string.con_success)
                LiveEventBus.get<Boolean>(Constant.EVENT_CONNECT_STATUS).post(true)
            }
            POSConnect.CONNECT_FAIL -> {
                //UIUtils.toast(this,R.string.con_failed)
                LiveEventBus.get<Boolean>(Constant.EVENT_CONNECT_STATUS).post(false)
            }
            POSConnect.CONNECT_INTERRUPT -> {
                //UIUtils.toast(this,R.string.con_has_disconnect)
                LiveEventBus.get<Boolean>(Constant.EVENT_CONNECT_STATUS).post(false)
            }
            POSConnect.SEND_FAIL -> {
                UIUtils.toast(this,R.string.send_failed)
            }
            POSConnect.USB_DETACHED -> {
                UIUtils.toast(this,R.string.usb_detached)
            }
            POSConnect.USB_ATTACHED -> {
                UIUtils.toast(this,R.string.usb_attached)
            }
        }
    }

    private fun connectUSB(pathName: String) {
        curConnect?.close()
        curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_USB)
        curConnect!!.connect(pathName, connectListener)
    }

    private fun connectNet(ipAddress: String) {
        curConnect?.close()
        curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_ETHERNET)
        curConnect!!.connect(ipAddress, connectListener)
    }

    fun connectBt(macAddress: String) {
        curConnect?.close()
        curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_BLUETOOTH)
        curConnect!!.connect(macAddress, connectListener)
    }
    fun connectMAC(macAddress: String) {
        curConnect?.close()
        curConnect = POSConnect.connectMac(macAddress, connectListener)
    }

    fun connectSerial(port: String, boudrate: String) {
        curConnect?.close()
        curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_SERIAL)
        curConnect!!.connect("$port,$boudrate", connectListener)
    }
    private fun actitonConnectUSB() {
        val pathName = getUsbDevicePath(this)
        if (pathName != null) {
            connectUSB(pathName)
        } else {
            // Handle the case where no USB device is found
        }

    }


    private fun getUsbDevicePath(context: Context): String? {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val deviceList = usbManager.deviceList
        if (deviceList.isNotEmpty()) {
            // Get the first available USB device (or loop through if needed)
            val usbDevice = deviceList.values.firstOrNull()
            // This is just an example; you would need to use UsbDevice.getDeviceId() or other details to identify the device
            return usbDevice?.deviceName  // Returns something like "/dev/bus/usb/001/001"
        }
        return null
    }
    private  fun getStatusConnectUsb(){
        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL).apply {
            // Assuming LiveEventBus is set up properly in your Android project
            LiveEventBus.get<Boolean>(Constant.EVENT_CONNECT_STATUS).observe(this@MainActivity) { isConnected ->
                invokeMethod("connectionStatus", isConnected)
            }
        }
    }
    private fun connectMethod(){
        MethodChannel(flutterEngine!!.dartExecutor, CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "connect_usb" -> {
                        actitonConnectUSB()
                    }
                    "connect_lan" -> {
                        val ipAddress = call.argument<String>("ip_address")
                        if(!ipAddress.isNullOrEmpty()){
                            connectNet(ipAddress)
                        }
                    }
                    "print_barcode" -> {
                        printBarcode(call,result)

                    }
                    "print_image" -> {
                        printImage(call)

                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }
    private fun printBarcode(call: MethodCall,result: MethodChannel.Result) {

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
        printer.barcode(barcodeX, barcodeY, barcodeType, barcodeHeight, TSPLConst.READABLE_CENTER,TSPLConst.ROTATION_0,2,2,barcodeContent)
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

    private fun printImage(call: MethodCall){
        val printer = TSPLPrinter(curConnect)
        val imageData: ByteArray? = call.argument<ByteArray>("image_data")
        if (imageData != null) {
            val quantity = call.argument<Int>("quantity") ?: 1
            val size = call.argument<Map<String, Double>>("size")
            val (sizeWidth, sizeHeight) = extractSizeImage(size)
            val width = call.argument<Int>("widthImage") ?: 600
            val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData!!.size)
            val x = call.argument<Int>("x") ?: 0
            val y = call.argument<Int>("y") ?: 50
            if (bitmap != null) {
                printer.sizeMm(sizeWidth, sizeHeight)
                .cls()
                .bitmap(x, y, TSPLConst.BMP_MODE_OVERWRITE, width, bitmap, AlgorithmType.Threshold)
                .print(quantity)
            }
        }
    }

}



