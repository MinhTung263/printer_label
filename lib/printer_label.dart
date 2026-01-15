import 'dart:io';

import 'src.dart';

PrinterLabelPlatform get _platform => PrinterLabelPlatform.instance;

class PrinterLabel {
  static Future<String?> get platformVersion => _platform.platformVersion;

  static Future<bool> checkConnect() async {
    return Platform.isAndroid && await _platform.checkConnect();
  }

  static Future<bool> disconectPrinter() async {
    return await _platform.disconectPrinter();
  }

  static Future<bool> connectLan({required String ipAddress}) async {
    return await _platform.connectLan(ipAddress: ipAddress);
  }

  static Future<void> printLabel({
    required LabelModel barcodeImageModel,
  }) async {
    return await _platform.printLabel(labelModel: barcodeImageModel);
  }

  static Future<void> printPrintImage({
    required ImageModel model,
  }) async {
    return await _platform.printImage(imageModel: model);
  }

  static Future<void> printBarcode({
    required BarcodeModel printBarcodeModel,
  }) async {
    return await _platform.printBarcode(printBarcodeModel: printBarcodeModel);
  }

  static Future<void> printESC({
    required PrintThermalModel printThermalModel,
  }) async {
    return await _platform.printESC(printThermalModel: printThermalModel);
  }
}
