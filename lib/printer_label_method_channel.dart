import 'package:flutter/services.dart';

import 'src.dart';

class MethodChannelPrinterLabel extends PrinterLabelPlatform {
  final MethodChannel _channel = MethodChannel('flutter_printer_label');
  final EventChannel _scanChannel =
      const EventChannel('flutter_printer_label/bt_scan');

  Future<bool> checkConnect({String? deviceId}) async {
    return await _channel.invokeMethod('checkConnect', {
      "device_id": deviceId,
    });
  }

  Future<Map<String, bool>> getAllConnections() async {
    final result = await _channel.invokeMethod('checkConnect');
    return Map<String, bool>.from(result);
  }

  Future<bool> disconectPrinter({String? deviceId}) async {
    return await _channel.invokeMethod('disconnect', {
      "device_id": deviceId,
    });
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
    required String deviceId,
    required LabelModel labelModel,
  }) async {
    final data = labelModel.toLabel();
    data["device_id"] = deviceId;
    await _channel.invokeMethod('print_label', data);
  }

  @override
  Future<void> printImage({
    required ImageModel imageModel,
  }) async {
    await _channel.invokeMethod('print_image', imageModel.toJson());
  }

  @override
  Future<void> printESC({
    required PrintThermalModel printThermalModel,
  }) async {
    try {
      await _channel.invokeMethod(
        'print_image_esc',
        printThermalModel.toJson(),
      );
    } catch (e) {
      print("Error printing thermal: $e");
    }
  }

  @override
  Future<bool> connectBluetooth({
    required String macAddress,
  }) async {
    return await _channel.invokeMethod('connect_bt', {
      "mac_address": macAddress,
    });
  }

  @override
  Future<List<BluetoothDeviceModel>> getBluetoothDevices() async {
    final result = await _channel.invokeMethod('get_bluetooth_devices');
    return List<Map<dynamic, dynamic>>.from(result)
        .map((e) => BluetoothDeviceModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Stream<BluetoothDeviceModel> get bluetoothScanStream {
    return _scanChannel
        .receiveBroadcastStream()
        .map((e) => BluetoothDeviceModel.fromMap(Map<String, dynamic>.from(e)));
  }
}
