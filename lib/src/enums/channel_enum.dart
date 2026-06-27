/// Defines channels for communication between Flutter and Native platforms (MethodChannel & EventChannel).
enum PrinterChannel {
  /// Main MethodChannel for invoking asynchronous printer functions.
  method('flutter_printer_label'),

  /// EventChannel for streaming discovered Bluetooth devices.
  btScan('flutter_printer_label/bt_scan'),

  /// EventChannel for streaming USB connection state changes (attach/detach events).
  usbEvents('flutter_printer_label/usb_events');

  const PrinterChannel(this.name);

  /// The unique string identifier of the channel.
  final String name;
}
