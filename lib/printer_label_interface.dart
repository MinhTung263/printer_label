import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src.dart';

abstract class PrinterLabelPlatform extends PlatformInterface {
  PrinterLabelPlatform() : super(token: _token);

  static final Object _token = Object();

  static PrinterLabelPlatform _instance = MethodChannelPrinterLabel();

  /// The default instance of [PrinterLabelPlatform] to use.
  ///
  /// Defaults to [PrinterLabelPlatform].
  static PrinterLabelPlatform get instance => _instance;

  static set instance(PrinterLabelPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> get platformVersion;

  Future<bool> checkConnect();

  Future<bool> disconectPrinter();

  Future<bool> connectLan({
    required String ipAddress,
  });

  Future<void> printLabel({
    required LabelModel labelModel,
  });

  Future<void> printImage({
    required ImageModel imageModel,
  });

  Future<void> printBarcode({
    required BarcodeModel printBarcodeModel,
  });

  Future<void> printESC({
    required PrintThermalModel printThermalModel,
  });
}
