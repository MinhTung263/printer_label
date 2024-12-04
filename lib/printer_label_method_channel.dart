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

  @override
  Future<void> printImage({
    required List<Map<String, dynamic>> productList,
  }) async {
    final Map<String, dynamic> params = {
      'products': productList,
    };
    await _channel.invokeMethod(
      'print_image',
      params,
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

  void setupConnectionStatusListener(
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
