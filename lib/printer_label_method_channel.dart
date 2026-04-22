import 'package:flutter/services.dart';

import 'src.dart';

class MethodChannelPrinterLabel extends PrinterLabelPlatform {
  final MethodChannel _channel = MethodChannel(PrinterChannel.method.name);
  final EventChannel _scanChannel = EventChannel(PrinterChannel.btScan.name);
  final EventChannel _usbChannel = EventChannel(PrinterChannel.usbEvents.name);

  @override
  Future<bool> checkConnect({String? deviceId}) async {
    if (deviceId == null) return false;
    return await _channel.invokeMethod(PrinterMethod.checkConnect.value, {
      "device_id": deviceId,
    });
  }

  @override
  Future<Map<String, bool>> getAllConnections() async {
    final result =
        await _channel.invokeMethod(PrinterMethod.checkConnect.value);
    return Map<String, bool>.from(result);
  }

  @override
  Future<bool> disconectPrinter({String? deviceId}) async {
    return await _channel.invokeMethod(PrinterMethod.disconnect.value, {
      "device_id": deviceId,
    });
  }

  @override
  Future<bool> connectLan({required String ipAddress}) async {
    return await _channel.invokeMethod(PrinterMethod.connectLan.value, {
      "ip_address": ipAddress,
    });
  }

  @override
  Future<String?> get platformVersion async {
    final String? version =
        await _channel.invokeMethod(PrinterMethod.getPlatformVersion.value);
    return version;
  }

  @override
  Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required BarcodeModel printBarcodeModel,
  }) async {
    final data = printBarcodeModel.toMap();
    if (deviceId != null) data["device_id"] = deviceId;
    if (connectionType != null) data["connection_type"] = connectionType.value;
    await _channel.invokeMethod(PrinterMethod.printBarcode.value, data);
  }

  @override
  Future<void> printLabel({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required LabelModel labelModel,
  }) async {
    final data = labelModel.toJson();
    if (deviceId != null) data["device_id"] = deviceId;
    if (connectionType != null) data["connection_type"] = connectionType.value;
    await _channel.invokeMethod(PrinterMethod.printLabel.value, data);
  }

  @override
  Future<void> printImage({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required ImageModel imageModel,
  }) async {
    final data = imageModel.toJson();
    if (deviceId != null) data["device_id"] = deviceId;
    if (connectionType != null) data["connection_type"] = connectionType.value;
    await _channel.invokeMethod(PrinterMethod.printImage.value, data);
  }

  @override
  Future<void> printESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel printThermalModel,
  }) async {
    final data = printThermalModel.toJson();
    if (deviceId != null) data["device_id"] = deviceId;
    if (connectionType != null) data["connection_type"] = connectionType;
    try {
      await _channel.invokeMethod(PrinterMethod.printImageEsc.value, data);
    } catch (e) {
      print("Error printing thermal: $e");
    }
  }

  @override
  Future<void> printAll({
    LabelModel? labelModel,
    PrintThermalModel? escModel,
    PrinterConnectionType? connectionType,
  }) async {
    final Map<String, dynamic> data;
    if (escModel != null) {
      data = escModel.toJson();
    } else if (labelModel != null) {
      data = labelModel.toJson();
    } else {
      return;
    }
    if (connectionType != null) data["connection_type"] = connectionType.value;
    await _channel.invokeMethod(PrinterMethod.printAll.value, data);
  }

  @override
  Future<bool> connectBluetooth({required String macAddress}) async {
    return await _channel.invokeMethod(PrinterMethod.connectBt.value, {
      "mac_address": macAddress,
    });
  }

  @override
  Future<List<BluetoothDeviceModel>> getBluetoothDevices() async {
    final result =
        await _channel.invokeMethod(PrinterMethod.getBluetoothDevices.value);
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
