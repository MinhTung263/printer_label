enum PrinterMethod {
  getPlatformVersion('getPlatformVersion'),
  checkConnect('checkConnect'),
  disconnect('disconnect'),
  connectLan('connect_lan'),
  connectBt('connect_bt'),
  getBluetoothDevices('get_bluetooth_devices'),
  printBarcode('print_barcode'),
  printLabel('print_label'),
  printImage('print_image'),
  printImageEsc('print_image_esc'),
  printAll('print_all');

  const PrinterMethod(this.value);
  final String value;
}
