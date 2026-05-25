import 'dart:io';

import 'src.dart';

PrinterLabelPlatform get _platform => PrinterLabelPlatform.instance;

class PrinterLabel {
  static Future<String?> get platformVersion => _platform.platformVersion;

  static Future<bool> checkConnect({required String deviceId}) async {
    return Platform.isAndroid &&
        await _platform.checkConnect(deviceId: deviceId);
  }

  static Future<Map<String, bool>> getAllConnections() async {
    if (!Platform.isAndroid) return {};
    return await _platform.getAllConnections();
  }

  static Future<bool> disconectPrinter({String? deviceId}) async {
    return await _platform.disconectPrinter(deviceId: deviceId);
  }

  static Future<bool> connectLan({required String ipAddress}) async {
    return await _platform.connectLan(ipAddress: ipAddress);
  }

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

  // MARK: - Bluetooth
  /// iOS: khởi động BLE scan. Devices sẽ được emit qua [bluetoothScanStream].
  /// Phải gọi trước khi listen stream trên iOS.
  /// Android: no-op — Android tự scan khi enumerate devices.
  static Future<bool> startBluetoothScan() async {
    if (!Platform.isIOS) return false;
    return await _platform.startBluetoothScan();
  }

  static Future<bool> stopBluetoothScan() async {
    if (!Platform.isIOS) return false;
    return await _platform.stopBluetoothScan();
  }

  /// Connect tới printer.
  /// - iOS: [macAddress] là UUID identifier từ [BluetoothDeviceModel.identifier]
  /// - Android: [macAddress] là MAC address thực
  static Future<bool> connectBluetooth({required String macAddress}) async {
    return await _platform.connectBluetooth(macAddress: macAddress);
  }

  static Future<List<BluetoothDeviceModel>> getBluetoothDevices() async {
    return await _platform.getBluetoothDevices();
  }

  /// Stream BLE devices được discover.
  /// iOS: emit liên tục trong khi scan đang chạy.
  /// Gọi [startBluetoothScan] trước khi subscribe trên iOS.
  static Stream<BluetoothDeviceModel> get bluetoothScanStream =>
      _platform.bluetoothScanStream;

  static Stream<UsbConnectionEvent> get usbDeviceStream =>
      _platform.usbDeviceStream;
}
