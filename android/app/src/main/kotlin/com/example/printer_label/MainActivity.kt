package com.example.printer_label//package com.example.printer_label

import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbManager
import android.os.Bundle
import android.util.Log
import android.widget.ArrayAdapter
import android.widget.Toast
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

class MainActivity: FlutterActivity(){
    private var curConnect: IDeviceConnection? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Register Flutter plugins
        GeneratedPluginRegistrant.registerWith(flutterEngine!!)
        // Initialize POSConnect
        POSConnect.init(this)  // Initialize POSConnect library

        // Set up listeners for connection status changes via LiveEventBus
        LiveEventBus.get<Boolean>(Constant.EVENT_CONNECT_STATUS).observe(this) { isConnected ->
            if (isConnected) {
                UIUtils.toast(this,R.string.con_success)
            } else {
                UIUtils.toast(this,R.string.con_failed)
            }
        }
        connectMethod()
    }
    private val connectListener = IConnectListener { code,connInfo, msg ->
        when (code) {
            POSConnect.CONNECT_SUCCESS -> {
                UIUtils.toast(this,R.string.con_success,)
                LiveEventBus.get<Boolean>(Constant.EVENT_CONNECT_STATUS).post(true)
            }
            POSConnect.CONNECT_FAIL -> {
                UIUtils.toast(this,R.string.con_failed)
                LiveEventBus.get<Boolean>(Constant.EVENT_CONNECT_STATUS).post(false)
            }
            POSConnect.CONNECT_INTERRUPT -> {
                UIUtils.toast(this,R.string.con_has_disconnect)
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

    fun connectNet(ipAddress: String) {
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

    private fun connectMethod(){
        MethodChannel(flutterEngine!!.dartExecutor, "flutter_printer_label")
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "connect_usb" -> {
                        connectUSB()
                    }
                    "print" -> {
                        printBarcode()

                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }
    private fun printBarcode() {
        TSPLPrinter(curConnect).sizeMm(60.0, 30.0)
            .gapMm(0.0, 0.0)
            .cls()
            .barcode(60, 50, TSPLConst.CODE_TYPE_128, 108, "abcdef12345")
            .print()
    }

    private fun connectUSB() {
        val pathName = getUsbDevicePath(this)
        if (pathName != null) {
            curConnect?.close()
            curConnect = POSConnect.createDevice(POSConnect.DEVICE_TYPE_USB)
            curConnect!!.connect(pathName, connectListener)
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

}



