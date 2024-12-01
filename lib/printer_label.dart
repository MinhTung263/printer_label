import 'src.dart';

PrinterLabelPlatform get _platform => PrinterLabelPlatform.instance;

class PrinterLabel {
  static Future<String?> get platformVersion => _platform.platformVersion;

  static Future<void> connectUSB() => _platform.connectUSB();

  static Future<bool> getConnectionStatus() => _platform.getConnectionStatus();

  static Future<void> connectLan({required String ipAddress}) {
    return _platform.connectLan(ipAddress: ipAddress);
  }

  static Future<void> printImage({
    required ImageModel imageModel,
  }) {
    return _platform.printImage(imageModel: imageModel);
  }

  static Future<void> printBarcode({
    required BarcodeModel printBarcodeModel,
  }) {
    return _platform.printBarcode(printBarcodeModel: printBarcodeModel);
  }
}
