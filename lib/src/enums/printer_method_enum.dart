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
  bluetoothEnabled('bluetooth_enabled');

  const PrinterMethod(this.value);
  final String value;
}
