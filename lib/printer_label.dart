import 'package:flutter/services.dart';

import 'src.dart';

const MethodChannel _channel = MethodChannel('flutter_printer_label');

class PrinterLabel {
  static Future<void> connectUSB() async {
    _channel.invokeMethod('connect_usb');
  }

  static Future<void> printImage(
    ImageModel model,
  ) async {
    _channel.invokeMethod(
      'print_image',
      model.toMap(),
    );
  }

  static Future<void> printBarcode(
    BarcodeModel printBarcodeModel,
  ) async {
    await _channel.invokeMethod('print_barcode', printBarcodeModel.toMap());
  }

  static void setupConnectionStatusListener(
    ValueChanged<bool> onStatusChange,
  ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'connectionStatus') {
        final isConnected = call.arguments as bool;
        onStatusChange(isConnected);
      }
    });
  }
}
