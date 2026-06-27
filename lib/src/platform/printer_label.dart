import 'dart:io';

import '../src.dart';

PrinterLabelPlatform get _platform => PrinterLabelPlatform.instance;

/// Primary public class providing connections and print interfaces
/// for Flutter applications. Supports label (TSPL) and thermal receipt (ESC/POS)
/// printing via Bluetooth, LAN, or USB connections.
class PrinterLabel {
  /// Gets the platform operating system version string (Android/iOS).
  static Future<String?> get platformVersion => _platform.platformVersion;

  /// Checks if Bluetooth is currently enabled on the device.
  static Future<bool> bluetoothEnabled() => _platform.bluetoothEnabled();

  /// Checks the connection status of a specific printer by its [deviceId].
  ///
  /// If [deviceId] is null, checks if any printer connection is active.
  static Future<bool> checkConnect({String? deviceId}) async {
    return await _platform.checkConnect(deviceId: deviceId);
  }

  /// Queries the operational status of a specific printer by its [deviceId].
  ///
  /// Specify [type] as either "TSPL" or "ESC" to check specific protocols.
  /// Returns a [PrinterStatus] value.
  static Future<PrinterStatus> checkPrinterStatus({
    String? deviceId,
    String? type,
  }) async {
    return await _platform.checkPrinterStatus(deviceId: deviceId, type: type);
  }

  /// Gets a map of all currently active printer connections (only supported on Android).
  ///
  /// Returns a [Map] containing `deviceId` as keys and their connection states (`true`/`false`) as values.
  static Future<Map<String, bool>> getAllConnections() async {
    if (!Platform.isAndroid) return {};
    return await _platform.getAllConnections();
  }

  /// Disconnects a specific printer connection by [deviceId].
  ///
  /// If [deviceId] is null or empty, disconnects all active printer connections.
  static Future<bool> disconnectPrinter({String? deviceId}) async {
    return await _platform.disconnectPrinter(deviceId: deviceId);
  }

  /// [Deprecated] Use [disconnectPrinter] instead.
  @Deprecated('Use disconnectPrinter instead')
  static Future<bool> disconectPrinter({String? deviceId}) async {
    return await _platform.disconnectPrinter(deviceId: deviceId);
  }

  /// Connects to a network LAN printer using the specified [ipAddress].
  static Future<bool> connectLan({required String ipAddress}) async {
    return await _platform.connectLan(ipAddress: ipAddress);
  }

  /// Prints labels using TSPL commands from [labelModel].
  ///
  /// Specify [deviceId] and [connectionType] to print to a specific target printer.
  static Future<void> printLabel({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required LabelModel labelModel,
  }) async {
    return await _platform.printLabel(
      deviceId: deviceId,
      connectionType: connectionType,
      labelModel: labelModel,
    );
  }

  /// Prints a rasterized image using the TSPL protocol.
  ///
  /// Takes an [imageModel] containing image byte data, coordinates, and dimensions.
  static Future<void> printImage({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required ImageModel imageModel,
  }) async {
    return await _platform.printImage(
      deviceId: deviceId,
      connectionType: connectionType,
      imageModel: imageModel,
    );
  }

  /// [Deprecated] Use [printImage] instead to align with the platform interface.
  @Deprecated('Use printImage instead')
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

  /// Prints a thermal receipt using ESC/POS commands from [printThermalModel].
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

  /// Broadcasts print commands to all active connections (or filtered by [connectionType]).
  ///
  /// Supports both label printing [labelModel] (TSPL) and thermal receipt printing [escModel] (ESC/POS).
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

  // ==========================================
  // BLUETOOTH SECTION
  // ==========================================

  /// iOS: Starts scanning for Bluetooth Low Energy (BLE) devices.
  ///
  /// Discovered devices are emitted through [bluetoothScanStream].
  /// Call before subscribing to the stream on iOS.
  /// Android: No-op (scanning is automatically handled when retrieving devices).
  static Future<bool> startBluetoothScan() async {
    if (!Platform.isIOS) return false;
    return await _platform.startBluetoothScan();
  }

  /// iOS: Stops scanning for Bluetooth Low Energy (BLE) devices.
  /// Android: No-op.
  static Future<bool> stopBluetoothScan() async {
    if (!Platform.isIOS) return false;
    return await _platform.stopBluetoothScan();
  }

  /// Connects to a Bluetooth printer using its identifier [macAddress].
  ///
  /// - iOS: [macAddress] represents the CBPeripheral UUID string.
  /// - Android: [macAddress] represents the physical MAC address (e.g., `AA:BB:CC:DD:EE:FF`).
  static Future<bool> connectBluetooth({required String macAddress}) async {
    return await _platform.connectBluetooth(macAddress: macAddress);
  }

  /// Retrieves a list of previously paired (bonded) Bluetooth devices.
  static Future<List<BluetoothDeviceModel>> getBluetoothDevices() async {
    return await _platform.getBluetoothDevices();
  }

  /// Stream emitting discovered Bluetooth devices during active scans.
  ///
  /// Call [startBluetoothScan] before listening to this stream on iOS.
  static Stream<BluetoothDeviceModel> get bluetoothScanStream =>
      _platform.bluetoothScanStream;

  /// Stream emitting USB connection events (attach/detach) for USB printers (Android only).
  static Stream<UsbConnectionEvent> get usbDeviceStream =>
      _platform.usbDeviceStream;

  /// Prints raw text directly using TSPL printer commands.
  static Future<void> printText({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
    int x = 0,
    int y = 0,
    int font = 0,
    int rotation = 0,
    int sizeX = 1,
    int sizeY = 1,
    int width = 40,
    int height = 30,
  }) {
    return _platform.printText(
      deviceId: deviceId,
      connectionType: connectionType,
      text: text,
      x: x,
      y: y,
      font: font,
      rotation: rotation,
      sizeX: sizeX,
      sizeY: sizeY,
      width: width,
      height: height,
    );
  }

  /// Prints raw text directly using ESC/POS printer commands.
  static Future<void> printTextESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
  }) {
    return _platform.printTextESC(
      deviceId: deviceId,
      connectionType: connectionType,
      text: text,
    );
  }

  /// Prints raw barcode directly using TSPL printer commands.
  static Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int x = 0,
    int y = 0,
    int height = 100,
    String type = "128",
    int width = 40,
    int heightMM = 30,
  }) {
    return _platform.printBarcode(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      x: x,
      y: y,
      height: height,
      type: type,
      width: width,
      heightMM: heightMM,
    );
  }

  /// Prints raw QR code directly using TSPL printer commands.
  static Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int x = 0,
    int y = 0,
    int size = 4,
    int width = 40,
    int heightMM = 30,
  }) {
    return _platform.printQRCode(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      x: x,
      y: y,
      size: size,
      width: width,
      heightMM: heightMM,
    );
  }

  /// Prints raw barcode directly using ESC/POS printer commands.
  static Future<void> printBarcodeESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    String type = "128",
    int width = 2,
    int height = 162,
  }) {
    return _platform.printBarcodeESC(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      type: type,
      width: width,
      height: height,
    );
  }

  /// Prints raw QR code directly using ESC/POS printer commands.
  static Future<void> printQRCodeESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int size = 8,
  }) {
    return _platform.printQRCodeESC(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      size: size,
    );
  }
}
