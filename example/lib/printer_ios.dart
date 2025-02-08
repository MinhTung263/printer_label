import 'package:flutter/services.dart';

class PrinterIos {
  static const MethodChannel _channel = MethodChannel('flutter_printer_label');

  static Future<Map<String, String>> openPrinterSelection() async {
    final result = await _channel.invokeMethod('getBluetoothDevice');

    if (result is Map) {
      return result
          .map((key, value) => MapEntry(key.toString(), value.toString()));
    } else {
      throw Exception('Unexpected result type: ${result.runtimeType}');
    }
  }

  static Future<void> printWithSelectedPrinter(
    Map<String, String> printer,
  ) async {
    try {
      await _channel.invokeMethod('printWithSelectedPrinter', printer);
    } catch (e) {
      print('Error: $e');
    }
  }

  static Future<void> printWithWifi() async {
    try {
      await _channel.invokeMethod('printWifi');
    } catch (e) {
      print('Error: $e');
    }
  }
}
