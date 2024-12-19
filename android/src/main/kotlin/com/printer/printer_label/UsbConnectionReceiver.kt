package com.printer.printer_label

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import io.flutter.plugin.common.MethodChannel

class UsbConnectionReceiver(private val methodChannel: MethodChannel,private val printerLabelPlugin: PrinterLabelPlugin) : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action: String = intent.action ?: return
        if (UsbManager.ACTION_USB_DEVICE_ATTACHED == action) {
            val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            if (device != null) {
                printerLabelPlugin.actitonConnectUSB()
            }
        } else if (UsbManager.ACTION_USB_DEVICE_DETACHED == action) {
            methodChannel.invokeMethod("connectionStatus", false)
        }
    }
}