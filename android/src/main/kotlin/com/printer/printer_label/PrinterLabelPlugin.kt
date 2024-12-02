package com.printer.printer_label

import android.content.Context
import android.graphics.BitmapFactory
import android.hardware.usb.UsbManager
import android.os.Build
import android.widget.Toast
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import com.printer.printer_label.utils.Constant
import com.jeremyliao.liveeventbus.LiveEventBus

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import net.posprinter.IConnectListener
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.TSPLConst
import net.posprinter.TSPLPrinter
import net.posprinter.model.AlgorithmType

/** SamplePluginFlutterPlugin */
class PrinterLabelPlugin: FlutterPlugin, MethodCallHandler {

  private lateinit var channel : MethodChannel
  private var CHANNEL = "flutter_printer_label"
  private var mContext: Context? = null
  private var curConnect: IDeviceConnection? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
    channel.setMethodCallHandler(this)
    mContext = flutterPluginBinding.applicationContext
      getStatusConnectUsb(flutterPluginBinding)
    POSConnect.init(mContext)
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

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
    private  fun getStatusConnectUsb(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding){
        MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL).apply {
            LiveEventBus.get<Boolean>("EVENT_CONNECT_STATUS").observeForever { isConnected ->
                invokeMethod("connectionStatus", isConnected)
            }
        }
    }
  private val connectListener = IConnectListener { code,connInfo, msg ->
    when (code) {
      POSConnect.CONNECT_SUCCESS -> {
        toast("CONNECT_SUCCESS")
        LiveEventBus.get<Boolean>(Constant.EVENT_CONNECT_STATUS).post(true)
      }
      POSConnect.CONNECT_FAIL -> {
        toast("CONNECT_FAIL")
        LiveEventBus.get<Boolean>(Constant.EVENT_CONNECT_STATUS).post(false)
      }
      POSConnect.CONNECT_INTERRUPT -> {
        toast("CONNECT_INTERRUPT")
        LiveEventBus.get<Boolean>(Constant.EVENT_CONNECT_STATUS).post(false)
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
    Toast.makeText( mContext, str, Toast.LENGTH_SHORT).show()
  }
  @RequiresApi(Build.VERSION_CODES.HONEYCOMB_MR1)
  private fun actitonConnectUSB() {
    val pathName = getUsbDevicePath(mContext!!)
    if (pathName != null) {
      connectUSB(pathName)
    }
  }
  @RequiresApi(Build.VERSION_CODES.HONEYCOMB_MR1)
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
    printer.barcode(barcodeX, barcodeY, barcodeType, barcodeHeight, TSPLConst.READABLE_CENTER,
      TSPLConst.ROTATION_0,2,2,barcodeContent)
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

