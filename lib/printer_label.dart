import 'package:flutter/services.dart';

import 'src.dart';

PrinterLabelPlatform get _platform => PrinterLabelPlatform.instance;

class PrinterLabel {
  static Future<String?> get platformVersion => _platform.platformVersion;

  static Future<void> connectUSB() => _platform.connectUSB();

  static void getConnectionStatus(
    ValueChanged<bool> onStatusChange,
  ) =>
      _platform.setupConnectionStatusListener(onStatusChange);

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

  static Future<void> printBarcode({
    required BarcodeModel printBarcodeModel,
  }) {
    return _platform.printBarcode(printBarcodeModel: printBarcodeModel);
  }
}
