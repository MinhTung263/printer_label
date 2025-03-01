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

  Future<void> connectLan({
    required String ipAddress,
  });

  Future<bool> printImage({
    required List<Map<String, dynamic>> productList,
  });

  Future<void> printMultiLabel({
    required BarcodeImageModel imageModel,
  });

  Future<void> printBarcode({
    required BarcodeModel printBarcodeModel,
  });

  Future<void> printThermal({
    required PrintThermalModel printThermalModel,
  });
}
