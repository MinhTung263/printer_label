import 'dart:io';

import 'src.dart';

PrinterLabelPlatform get _platform => PrinterLabelPlatform.instance;

class PrinterLabel {
  static Future<String?> get platformVersion => _platform.platformVersion;

  static Future<bool> checkConnect({required String deviceId}) async {
    return Platform.isAndroid &&
        await _platform.checkConnect(deviceId: deviceId);
  }

  static Future<bool> disconectPrinter({String? deviceId}) async {
    return await _platform.disconectPrinter(deviceId: deviceId);
  }

  static Future<bool> connectLan({required String ipAddress}) async {
    return await _platform.connectLan(ipAddress: ipAddress);
  }

  /// In label tới thiết bị chỉ định:
  ///  - [connectionType] = "USB" | "LAN" | "BT"  (ưu tiên)
  ///  - [deviceId] = path/MAC/IP cụ thể
  ///  - Cả hai null → dùng connection active đầu tiên
  static Future<void> printLabel({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required LabelModel barcodeImageModel,
  }) async {
    return await _platform.printLabel(
      deviceId: deviceId,
      connectionType: connectionType,
      labelModel: barcodeImageModel,
    );
  }

  static Future<void> printPrintImage({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required ImageModel model,
  }) async {
    return await _platform.printImage(
      deviceId: deviceId,
      connectionType: connectionType,
      imageModel: model,
    );
  }

  static Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required BarcodeModel printBarcodeModel,
  }) async {
    return await _platform.printBarcode(
      deviceId: deviceId,
      connectionType: connectionType,
      printBarcodeModel: printBarcodeModel,
    );
  }

  static Future<void> printESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel printThermalModel,
  }) async {
    return await _platform.printESC(
      deviceId: deviceId,
      connectionType: connectionType,
      printThermalModel: printThermalModel,
    );
  }

  /// In tới tất cả thiết bị đang active.
  /// Truyền [labelModel] để in TSPL, [escModel] để in ESC.
  /// [connectionType] lọc theo loại kết nối (LAN / BT / USB); null = tất cả.
  static Future<void> printAll({
    LabelModel? labelModel,
    PrintThermalModel? escModel,
    PrinterConnectionType? connectionType,
  }) async {
    return await _platform.printAll(
      labelModel: labelModel,
      escModel: escModel,
      connectionType: connectionType,
    );
  }

  static Future<bool> connectBluetooth({required String macAddress}) async {
    return await _platform.connectBluetooth(macAddress: macAddress);
  }

  static Future<List<BluetoothDeviceModel>> getBluetoothDevices() async {
    return await _platform.getBluetoothDevices();
  }

  static Stream<BluetoothDeviceModel> get bluetoothScanStream =>
      _platform.bluetoothScanStream;

  static Stream<UsbConnectionEvent> get usbDeviceStream =>
      _platform.usbDeviceStream;
}
