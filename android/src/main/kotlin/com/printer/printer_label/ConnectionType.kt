package com.printer.printer_label

enum class ConnectionType {
    USB, LAN, BT;

    fun displayName(): String = when (this) {
        USB -> "USB"
        LAN -> "LAN"
        BT -> "Bluetooth"
    }
}