import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src.dart';

abstract class PrinterLabelPlatform extends PlatformInterface {
  PrinterLabelPlatform() : super(token: _token);

  static final Object _token = Object();

  static PrinterLabelPlatform _instance = MethodChannelPrinterLabel();

  static PrinterLabelPlatform get instance => _instance;

  static set instance(PrinterLabelPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> get platformVersion;

  Future<bool> checkConnect({String? deviceId});

  Future<Map<String, bool>> getAllConnections();

  Future<bool> disconectPrinter({String? deviceId});

  Future<bool> connectLan({required String ipAddress});

  /// iOS: bắt đầu scan BLE — devices stream qua [bluetoothScanStream]
  /// Android: no-op (Android tự scan)
  Future<bool> startBluetoothScan();

  Future<bool> stopBluetoothScan();

  Future<void> printLabel({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required LabelModel labelModel,
  });

  Future<void> printImage({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required ImageModel imageModel,
  });

  Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required BarcodeModel printBarcodeModel,
  });

  Future<void> printESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel printThermalModel,
  });

  Future<void> printAll({
    LabelModel? labelModel,
    PrintThermalModel? escModel,
    PrinterConnectionType? connectionType,
  });

  /// [identifier] trên iOS là UUID string của CBPeripheral.
  /// Trên Android là MAC address.
  /// Giữ tên param là macAddress để tương thích backward.
  Future<bool> connectBluetooth({required String macAddress});

  Future<List<BluetoothDeviceModel>> getBluetoothDevices();

  /// Stream các device được discover trong quá trình scan.
  /// Gọi [startBluetoothScan] trước khi listen trên iOS.
  Stream<BluetoothDeviceModel> get bluetoothScanStream;

  Stream<UsbConnectionEvent> get usbDeviceStream;
}
