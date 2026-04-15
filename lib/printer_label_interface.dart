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

  /// [connectionType] = "USB" | "LAN" | "BT" — nếu cung cấp sẽ tìm connection theo loại.
  /// [deviceId] — dùng khi muốn chỉ định thiết bị cụ thể.
  /// Nếu cả hai đều null, lấy connection active đầu tiên.
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

  /// In cùng payload [labelModel] tới tất cả thiết bị đang active.
  Future<void> printAll({required LabelModel labelModel});

  Future<bool> connectBluetooth({required String macAddress});

  Future<List<BluetoothDeviceModel>> getBluetoothDevices();

  Stream<BluetoothDeviceModel> get bluetoothScanStream;

  Stream<UsbConnectionEvent> get usbDeviceStream;
}
