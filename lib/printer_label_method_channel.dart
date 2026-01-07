import 'package:flutter/services.dart';

import 'src.dart';

class MethodChannelPrinterLabel extends PrinterLabelPlatform {
  final MethodChannel _channel = MethodChannel('flutter_printer_label');

  Future<bool> checkConnect() async {
    return await _channel.invokeMethod('checkConnect');
  }

  Future<bool> connectLan({
    required String ipAddress,
  }) async {
    return await _channel.invokeMethod('connect_lan', {
      "ip_address": ipAddress,
    });
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

  @override
  Future<void> printLabel({
    required LabelModel labelModel,
  }) async {
    await _channel.invokeMethod('print_label', labelModel.toLabel());
  }

  @override
  Future<void> printImage({
    required ImageModel imageModel,
  }) async {
    await _channel.invokeMethod('print_image', imageModel.toJson());
  }

  @override
  Future<void> printThermal({
    required PrintThermalModel printThermalModel,
  }) async {
    try {
      await _channel.invokeMethod(
        'print_thermal',
        printThermalModel.toJson(),
      );
    } catch (e) {
      print("Error printing thermal: $e");
    }
  }
}
