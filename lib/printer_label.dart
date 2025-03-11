import 'dart:io';

import 'src.dart';

PrinterLabelPlatform get _platform => PrinterLabelPlatform.instance;

class PrinterLabel {
  static Future<String?> get platformVersion => _platform.platformVersion;

  static Future<bool> checkConnect() async {
    return Platform.isAndroid && await _platform.checkConnect();
  }

  static Future<void> connectLan({required String ipAddress}) async {
    return await _platform.connectLan(ipAddress: ipAddress);
  }

  static Future<bool> printImage({
    required List<Map<String, dynamic>> productList,
  }) async {
    return await _platform.printImage(
      productList: productList,
    );
  }

  static Future<void> printMultiLabel({
    required BarcodeImageModel barcodeImageModel,
  }) async {
    return await _platform.printMultiLabel(imageModel: barcodeImageModel);
  }

  static Future<void> printBarcode({
    required BarcodeModel printBarcodeModel,
  }) async {
    return await _platform.printBarcode(printBarcodeModel: printBarcodeModel);
  }

  static Future<void> printThermal({
    required PrintThermalModel printThermalModel,
  }) async {
    return await _platform.printThermal(printThermalModel: printThermalModel);
  }
}
