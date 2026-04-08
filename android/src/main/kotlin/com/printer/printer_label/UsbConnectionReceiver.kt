package com.printer.printer_label

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import io.flutter.plugin.common.MethodChannel

class UsbConnectionReceiver(
        private val methodChannel: MethodChannel,
        private val printerLabelPlugin: PrinterLabelPlugin
) : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val device: UsbDevice? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(
                    UsbManager.EXTRA_DEVICE,
                    UsbDevice::class.java
                )
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            }
        when (action) {
            UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                device?.let { printerLabelPlugin.handleUsbDeviceAttached(it) }
            }
            UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                printerLabelPlugin.handleUsbDeviceDetached(device)
            }
        }
    }
}
