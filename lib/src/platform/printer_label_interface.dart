import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../src.dart';

/// Abstract class defining the printer hardware communication APIs (TSPL and ESC/POS)
/// between Dart/Flutter and Native SDKs (Android/iOS).
abstract class PrinterLabelPlatform extends PlatformInterface {
  PrinterLabelPlatform() : super(token: _token);

  static final Object _token = Object();

  static PrinterLabelPlatform _instance = MethodChannelPrinterLabel();

  /// Gets the current instance of the platform interface.
  static PrinterLabelPlatform get instance => _instance;

  /// Sets the current instance of the platform interface (primarily used for Mocking/Testing).
  static set instance(PrinterLabelPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Gets the platform operating system version string (Android/iOS).
  Future<String?> get platformVersion;
  
  /// Checks if Bluetooth is currently enabled on the device.
  Future<bool> bluetoothEnabled();

  /// Checks the connection status of a specific printer by its [deviceId].
  ///
  /// If [deviceId] is null, checks if any printer connection is active.
  Future<bool> checkConnect({String? deviceId});

  /// Queries the operational status of a specific printer by [deviceId].
  ///
  /// Specify [type] as either "TSPL" or "ESC" to check specific protocols.
  /// Returns a [PrinterStatus] value.
  Future<PrinterStatus> checkPrinterStatus({String? deviceId, String? type});

  /// Gets a map of all currently active printer connections (only supported on Android).
  ///
  /// Returns a [Map] containing `deviceId` as keys and their connection states (`true`/`false`) as values.
  Future<Map<String, bool>> getAllConnections();

  /// Disconnects a specific printer connection by [deviceId].
  ///
  /// If [deviceId] is null or empty, disconnects all active printer connections.
  Future<bool> disconnectPrinter({String? deviceId});

  /// [Deprecated] Use [disconnectPrinter] instead.
  @Deprecated('Use disconnectPrinter instead')
  Future<bool> disconectPrinter({String? deviceId}) => disconnectPrinter(deviceId: deviceId);

  /// Connects to a network LAN printer using the specified [ipAddress].
  Future<bool> connectLan({required String ipAddress});

  /// iOS: Starts scanning for Bluetooth Low Energy (BLE) devices.
  ///
  /// Discovered devices are emitted through [bluetoothScanStream].
  /// Android: No-op (scanning is automatically handled when retrieving devices).
  Future<bool> startBluetoothScan();

  /// iOS: Stops scanning for Bluetooth Low Energy (BLE) devices.
  /// Android: No-op.
  Future<bool> stopBluetoothScan();

  /// Prints labels using TSPL commands (Barcode, Text, Graphic) defined in [labelModel].
  ///
  /// Specify [deviceId] and [connectionType] to print to a specific target printer.
  Future<void> printLabel({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required LabelModel labelModel,
  });

  /// Prints a rasterized image using the TSPL protocol.
  ///
  /// Takes an [imageModel] containing image byte data, coordinates, and dimensions.
  Future<void> printImage({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required ImageModel imageModel,
  });


  /// Prints a thermal receipt using ESC/POS commands from [printThermalModel].
  Future<void> printESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel printThermalModel,
  });

  /// Connects to a Bluetooth printer using its identifier [macAddress].
  ///
  /// - iOS: [macAddress] represents the CBPeripheral UUID string.
  /// - Android: [macAddress] represents the physical MAC address (e.g., `AA:BB:CC:DD:EE:FF`).
  Future<bool> connectBluetooth({required String macAddress});

  /// Automatically turns on Bluetooth (if supported/allowed) and connects to
  /// the internal emulated Bluetooth printer on built-in printer POS devices.
  /// Returns `true` if connected successfully, `false` otherwise.
  Future<bool> autoConnectBuiltIn();

  /// Disconnects the built-in printer (only supported on Android).
  Future<bool> disconnectBuiltIn();



  /// Checks if the current Android device has a built-in thermal printer.
  /// Always returns `false` on iOS.
  Future<bool> hasBuiltInPrinter();

  /// Gets the paper width of the built-in printer in millimeters (e.g., 58 or 80).
  /// Returns `0` if the device has no built-in thermal printer.
  /// Always returns `0` on iOS.
  Future<int> getBuiltInPrinterPaperSize();

  /// Retrieves a list of previously paired (bonded) Bluetooth devices.
  /// If [filterPrinterOnly] is true (default), only devices recognized as printers are returned.
  Future<List<BluetoothDeviceModel>> getBluetoothDevices({bool filterPrinterOnly = true});

  /// Stream emitting discovered Bluetooth devices during active scans.
  ///
  /// If [filterPrinterOnly] is true (default), only devices recognized as printers are emitted.
  /// Call [startBluetoothScan] before listening to this stream on iOS.
  Stream<BluetoothDeviceModel> bluetoothScanStream({bool filterPrinterOnly = true});

  /// Stream emitting USB connection events (attach/detach) for USB printers (Android only).
  Stream<UsbConnectionEvent> get usbDeviceStream;

  /// Prints raw text directly using TSPL printer commands.
  Future<void> printText({
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
  });

  /// Prints raw text directly using ESC/POS printer commands.
  Future<void> printTextESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
  });

  /// Prints raw barcode directly using TSPL printer commands.
  Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int x = 0,
    int y = 0,
    int height = 100,
    String type = "128",
    int width = 40,
    int heightMM = 30,
  });

  /// Prints raw QR code directly using TSPL printer commands.
  Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int x = 0,
    int y = 0,
    int size = 4,
    int width = 40,
    int heightMM = 30,
  });

  /// Prints raw barcode directly using ESC/POS printer commands.
  Future<void> printBarcodeESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    String type = "128",
    int width = 2,
    int height = 162,
  });

  /// Prints raw QR code directly using ESC/POS printer commands.
  Future<void> printQRCodeESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int size = 8,
  });
}
