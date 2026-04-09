import 'package:flutter/services.dart';

import 'src.dart';

class MethodChannelPrinterLabel extends PrinterLabelPlatform {
  final MethodChannel _channel = MethodChannel('flutter_printer_label');
  final EventChannel _scanChannel =
      const EventChannel('flutter_printer_label/bt_scan');
  final EventChannel _usbChannel =
      const EventChannel('flutter_printer_label/usb_events');

  @override
  Future<bool> checkConnect({String? deviceId}) async {
    if (deviceId == null) return false;
    return await _channel.invokeMethod('checkConnect', {
      "device_id": deviceId,
    });
  }

  @override
  Future<Map<String, bool>> getAllConnections() async {
    final result = await _channel.invokeMethod('checkConnect');
    return Map<String, bool>.from(result);
  }

  @override
  Future<bool> disconectPrinter({String? deviceId}) async {
    return await _channel.invokeMethod('disconnect', {
      "device_id": deviceId,
    });
  }

  @override
  Future<bool> connectLan({
    required String ipAddress,
  }) async {
    return await _channel.invokeMethod('connect_lan', {
      "ip_address": ipAddress,
    });
  }

  @override
  Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  @override
  Future<void> printBarcode({
    required String deviceId,
    required BarcodeModel printBarcodeModel,
  }) async {
    final data = printBarcodeModel.toMap();
    data["device_id"] = deviceId;
    await _channel.invokeMethod('print_barcode', data);
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
    required String deviceId,
    required ImageModel imageModel,
  }) async {
    final data = imageModel.toJson();
    data["device_id"] = deviceId;
    await _channel.invokeMethod('print_image', data);
  }

  @override
  Future<void> printESC({
    required String deviceId,
    required PrintThermalModel printThermalModel,
  }) async {
    final data = printThermalModel.toJson();
    data["device_id"] = deviceId;
    try {
      await _channel.invokeMethod(
        'print_image_esc',
        data,
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

  /// Phát sự kiện khi USB được cắm vào (connected=true) hoặc rút ra (connected=false).
  /// `deviceId` là USB device path — dùng làm device_id khi gọi các lệnh print.
  @override
  Stream<UsbConnectionEvent> get usbDeviceStream {
    return _usbChannel.receiveBroadcastStream().map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      return UsbConnectionEvent(
        deviceId: map['device_id'] as String,
        connected: map['connected'] as bool,
      );
    });
  }
}
