enum PrinterChannel {
  method('flutter_printer_label'),
  btScan('flutter_printer_label/bt_scan'),
  usbEvents('flutter_printer_label/usb_events');

  const PrinterChannel(this.name);
  final String name;
}
