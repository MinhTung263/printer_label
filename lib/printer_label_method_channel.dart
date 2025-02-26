import 'package:flutter/services.dart';

import 'src.dart';

class MethodChannelPrinterLabel extends PrinterLabelPlatform {
  final MethodChannel _channel = MethodChannel('flutter_printer_label');

  Future<void> connectLan({
    required String ipAddress,
  }) async {
    await _channel.invokeMethod('connect_lan', {
      "ip_address": ipAddress,
    });
  }

  @override
  Future<bool> printImage({
    required List<Map<String, dynamic>> productList,
  }) async {
    try {
      final Map<String, dynamic> params = {
        'products': productList,
      };
      final bool? result = await _channel.invokeMethod<bool>(
        'print_image',
        params,
      );
      return result ?? false;
    } catch (e) {
      print('Error while printing image: $e');
      return false;
    }
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

  @override
  Future<void> printMultiLabel({
    required BarcodeImageModel imageModel,
  }) async {
    await _channel.invokeMethod('print_multiLabel', imageModel.toMap());
  }

  @override
  Future<void> printThermal({
    required PrintThermalModel printThermalModel,
  }) async {
    await _channel.invokeMethod(
      'print_thermal',
      printThermalModel.toJson(),
    );
  }
}
