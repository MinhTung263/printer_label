import 'src.dart';

PrinterLabelPlatform get _platform => PrinterLabelPlatform.instance;

class PrinterLabel {
  static Future<String?> get platformVersion => _platform.platformVersion;

  static Future<bool> checkConnect() {
    return _platform.checkConnect();
  }

  static Future<void> connectLan({required String ipAddress}) {
    return _platform.connectLan(ipAddress: ipAddress);
  }

  static Future<bool> printImage({
    required List<Map<String, dynamic>> productList,
  }) {
    return _platform.printImage(
      productList: productList,
    );
  }

  static Future<void> printMultiLabel({
    required BarcodeImageModel barcodeImageModel,
  }) {
    return _platform.printMultiLabel(imageModel: barcodeImageModel);
  }

  static Future<void> printBarcode({
    required BarcodeModel printBarcodeModel,
  }) {
    return _platform.printBarcode(printBarcodeModel: printBarcodeModel);
  }

  static Future<void> printThermal({
    required PrintThermalModel printThermalModel,
  }) {
    return _platform.printThermal(printThermalModel: printThermalModel);
  }
}
