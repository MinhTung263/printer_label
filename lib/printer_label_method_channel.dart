import 'package:flutter/services.dart';

import 'src.dart';

class MethodChannelPrinterLabel extends PrinterLabelPlatform {
  final MethodChannel _channel = MethodChannel('flutter_printer_label');

  Future<void> connectUSB() async {
    await _channel.invokeMethod('connect_usb');
  }

  Future<void> connectLan({
    required String ipAddress,
  }) async {
    await _channel.invokeMethod('connect_lan', {
      "ip_address": ipAddress,
    });
  }

  Future<void> printImage({
    required ImageModel imageModel,
  }) async {
    await _channel.invokeMethod(
      'print_image',
      imageModel.toMap(),
    );
  }

  Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  Future<void> printBarcode({
    required BarcodeModel printBarcodeModel,
  }) async {
    await _channel.invokeMethod('print_barcode', printBarcodeModel.toMap());
  }

  Future<bool> getConnectionStatus() async {
    return await _channel.invokeMethod('getConnectionStatus');
  }
}
