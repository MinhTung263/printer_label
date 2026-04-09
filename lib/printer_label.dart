import 'dart:io';

import 'src.dart';

PrinterLabelPlatform get _platform => PrinterLabelPlatform.instance;

class PrinterLabel {
  static Future<String?> get platformVersion => _platform.platformVersion;

  static Future<bool> checkConnect({required String deviceId}) async {
    return Platform.isAndroid &&
        await _platform.checkConnect(deviceId: deviceId);
  }

  static Future<bool> disconectPrinter() async {
    return await _platform.disconectPrinter();
  }

  static Future<bool> connectLan({required String ipAddress}) async {
    return await _platform.connectLan(ipAddress: ipAddress);
  }

  static Future<void> printLabel({
    required String deviceId,
    required LabelModel barcodeImageModel,
  }) async {
    return await _platform.printLabel(
        deviceId: deviceId, labelModel: barcodeImageModel);
  }

  static Future<void> printPrintImage({
    required String deviceId,
    required ImageModel model,
  }) async {
    return await _platform.printImage(deviceId: deviceId, imageModel: model);
  }

  static Future<void> printBarcode({
    required String deviceId,
    required BarcodeModel printBarcodeModel,
  }) async {
    return await _platform.printBarcode(
        deviceId: deviceId, printBarcodeModel: printBarcodeModel);
  }

  static Future<void> printESC({
    required String deviceId,
    required PrintThermalModel printThermalModel,
  }) async {
    return await _platform.printESC(
        deviceId: deviceId, printThermalModel: printThermalModel);
  }

  static Future<bool> connectBluetooth({
    required String macAddress,
  }) async {
    return await _platform.connectBluetooth(macAddress: macAddress);
  }

  static Future<List<BluetoothDeviceModel>> getBluetoothDevices() async {
    return await _platform.getBluetoothDevices();
  }

  static Stream<BluetoothDeviceModel> get bluetoothScanStream =>
      _platform.bluetoothScanStream;

  /// Stream nhận sự kiện USB cắm vào/rút ra.
  /// Lắng nghe stream này để lấy `deviceId` và dùng khi gọi printLabel/printESC/v.v.
  static Stream<UsbConnectionEvent> get usbDeviceStream =>
      _platform.usbDeviceStream;
}
