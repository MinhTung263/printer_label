import 'package:flutter/services.dart';

import 'src.dart';

class PrinterLabel {
  static const MethodChannel _channel = MethodChannel('flutter_printer_label');


  static Future<void> connectUSB() async {
    await _channel.invokeMethod('connect_usb');
  }

  static Future<void> connectLan({
    required String ipAddress,
  }) async {
    await _channel.invokeMethod('connect_lan', {
      "ip_address": ipAddress,
    });
  }

  static Future<void> printImage({
    required ImageModel model,
  }) async {
    await _channel.invokeMethod(
      'print_image',
      model.toMap(),
    );
  }

  static Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  static Future<void> printBarcode({
    required BarcodeModel printBarcodeModel,
  }) async {
    await _channel.invokeMethod('print_barcode', printBarcodeModel.toMap());
  }

  static Future<void> setupConnectionStatusListener(
    ValueChanged<bool> onStatusChange,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'connectionStatus') {
        final isConnected = call.arguments as bool;
        onStatusChange(isConnected);
      }
    });
  }
}
