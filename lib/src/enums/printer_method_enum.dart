enum PrinterMethod {
  getPlatformVersion('getPlatformVersion'),
  checkConnect('checkConnect'),
  disconnect('disconnect'),
  connectLan('connect_lan'),
  connectBt('connect_bt'),
  scanBt('scan_bt'),
  stopScanBt('stop_scan_bt'),
  getBluetoothDevices('get_bluetooth_devices'),
  printLabel('print_label'),
  printImage('print_image'),
  printImageEsc('print_image_esc'),
  printAll('print_all'),
  bluetoothEnabled('bluetooth_enabled'),
  printText('print_text'),
  printTextESC('print_text_esc'),
  printBarcode('print_barcode'),
  printQRCode('print_qrcode'),
  printBarcodeESC('print_barcode_esc'),
  printQRCodeESC('print_qrcode_esc');

  const PrinterMethod(this.value);
  final String value;
}
