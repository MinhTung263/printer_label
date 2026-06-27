import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../src.dart';

/// Implementation of the printer communication protocol using [MethodChannel] and [EventChannel].
class MethodChannelPrinterLabel extends PrinterLabelPlatform {
  final MethodChannel _channel = MethodChannel(PrinterChannel.method.name);
  final EventChannel _scanChannel = EventChannel(PrinterChannel.btScan.name);
  final EventChannel _usbChannel = EventChannel(PrinterChannel.usbEvents.name);

  // Cached streams to prevent recreating them on every getter access
  Stream<BluetoothDeviceModel>? _bluetoothScanStream;
  Stream<UsbConnectionEvent>? _usbDeviceStream;

  @override
  Future<bool> bluetoothEnabled() async {
    return await _channel
            .invokeMethod<bool>(PrinterMethod.bluetoothEnabled.value) ??
        false;
  }

  @override
  Future<bool> checkConnect({String? deviceId}) async {
    final targetId = deviceId?.trim();
    if (targetId == null || targetId.isEmpty) return false;
    return await _channel.invokeMethod<bool>(PrinterMethod.checkConnect.value, {
          "device_id": targetId,
        }) ??
        false;
  }

  @override
  Future<PrinterStatus> checkPrinterStatus({String? deviceId, String? type}) async {
    final targetId = deviceId?.trim();
    final String? statusStr = await _channel.invokeMethod<String>(
      PrinterMethod.checkPrinterStatus.value,
      {
        if (targetId != null && targetId.isNotEmpty) "device_id": targetId,
        if (type != null && type.isNotEmpty) "type": type,
      },
    );
    return PrinterStatus.fromValue(statusStr);
  }

  @override
  Future<Map<String, bool>> getAllConnections() async {
    final result = await _channel.invokeMethod<Map>(
      PrinterMethod.checkConnect.value,
    );
    if (result == null) return {};
    return result.map((key, value) => MapEntry(key.toString(), value == true));
  }

  @override
  Future<bool> disconnectPrinter({String? deviceId}) async {
    final targetId = deviceId?.trim();
    return await _channel.invokeMethod<bool>(PrinterMethod.disconnect.value, {
          "device_id": (targetId == null || targetId.isEmpty) ? null : targetId,
        }) ??
        false;
  }

  @override
  @Deprecated('Use disconnectPrinter instead')
  Future<bool> disconectPrinter({String? deviceId}) async {
    return await disconnectPrinter(deviceId: deviceId);
  }

  @override
  Future<bool> connectLan({required String ipAddress}) async {
    final targetIp = ipAddress.trim();
    if (targetIp.isEmpty) return false;
    return await _channel.invokeMethod<bool>(PrinterMethod.connectLan.value, {
          "ip_address": targetIp,
        }) ??
        false;
  }

  @override
  Future<bool> startBluetoothScan() async {
    return await _channel.invokeMethod<bool>(PrinterMethod.scanBt.value) ??
        false;
  }

  @override
  Future<bool> stopBluetoothScan() async {
    return await _channel.invokeMethod<bool>(PrinterMethod.stopScanBt.value) ??
        false;
  }

  @override
  Future<String?> get platformVersion async {
    final String? version = await _channel
        .invokeMethod<String>(PrinterMethod.getPlatformVersion.value);
    return version;
  }

  @override
  Future<void> printLabel({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required LabelModel labelModel,
  }) async {
    final data = {
      ...labelModel.toJson(),
      if (deviceId != null) "device_id": deviceId,
      if (connectionType != null) "connection_type": connectionType.value,
    };
    await _channel.invokeMethod<void>(PrinterMethod.printLabel.value, data);
  }

  @override
  Future<void> printImage({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required ImageModel imageModel,
  }) async {
    final data = {
      ...imageModel.toJson(),
      if (deviceId != null) "device_id": deviceId,
      if (connectionType != null) "connection_type": connectionType.value,
    };
    await _channel.invokeMethod<void>(PrinterMethod.printImage.value, data);
  }

  @override
  Future<void> printESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel printThermalModel,
  }) async {
    final data = {
      ...printThermalModel.toJson(),
      if (deviceId != null) "device_id": deviceId,
      if (connectionType != null) "connection_type": connectionType.value,
    };
    try {
      await _channel.invokeMethod<void>(
          PrinterMethod.printImageEsc.value, data);
    } catch (e, stack) {
      debugPrint("Error printing ESC: $e\n$stack");
      rethrow;
    }
  }

  @override
  Future<void> printAll({
    LabelModel? labelModel,
    PrintThermalModel? escModel,
    PrinterConnectionType? connectionType,
  }) async {
    final Map<String, dynamic> baseData;
    if (escModel != null) {
      baseData = escModel.toJson();
    } else if (labelModel != null) {
      baseData = labelModel.toJson();
    } else {
      return;
    }
    final data = {
      ...baseData,
      if (connectionType != null) "connection_type": connectionType.value,
    };
    await _channel.invokeMethod<void>(PrinterMethod.printAll.value, data);
  }

  @override
  Future<bool> connectBluetooth({required String macAddress}) async {
    final targetMac = macAddress.trim();
    if (targetMac.isEmpty) return false;
    return await _channel.invokeMethod<bool>(PrinterMethod.connectBt.value, {
          "mac_address": targetMac,
        }) ??
        false;
  }

  @override
  Future<List<BluetoothDeviceModel>> getBluetoothDevices() async {
    final result = await _channel.invokeMethod<List>(
      PrinterMethod.getBluetoothDevices.value,
    );
    if (result == null) return [];
    return result.map((e) {
      final map = Map<Object?, Object?>.from(e as Map);
      return BluetoothDeviceModel.fromMap({
        'name': map['name']?.toString() ?? 'Unknown',
        'identifier': map['identifier']?.toString(),
        'mac': map['mac']?.toString(),
      });
    }).toList();
  }

  @override
  Stream<BluetoothDeviceModel> get bluetoothScanStream {
    _bluetoothScanStream ??= _scanChannel.receiveBroadcastStream().map((e) {
      final map = Map<Object?, Object?>.from(e as Map);
      return BluetoothDeviceModel.fromMap({
        'name': map['name']?.toString() ?? 'Unknown',
        'identifier': map['identifier']?.toString(),
        'mac': map['mac']?.toString(),
      });
    });
    return _bluetoothScanStream!;
  }

  @override
  Stream<UsbConnectionEvent> get usbDeviceStream {
    _usbDeviceStream ??= _usbChannel.receiveBroadcastStream().map((e) {
      final map = Map<Object?, Object?>.from(e as Map);
      return UsbConnectionEvent(
        deviceId: (map['device_id'] ?? '').toString(),
        connected: map['connected'] == true,
      );
    });
    return _usbDeviceStream!;
  }

  @override
  Future<void> printText({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
    int x = 0,
    int y = 0,
    int font = 0,
    int rotation = 0,
    int sizeX = 1,
    int sizeY = 1,
    int width = 40,
    int height = 30,
  }) async {
    final data = {
      "text": text,
      "x": x,
      "y": y,
      "font": font,
      "rotation": rotation,
      "sizeX": sizeX,
      "sizeY": sizeY,
      "width": width,
      "height": height,
      if (deviceId != null) "device_id": deviceId,
      if (connectionType != null) "connection_type": connectionType.value,
    };
    await _channel.invokeMethod<void>(PrinterMethod.printText.value, data);
  }

  @override
  Future<void> printTextESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
  }) async {
    final data = {
      "text": text,
      if (deviceId != null) "device_id": deviceId,
      if (connectionType != null) "connection_type": connectionType.value,
    };
    await _channel.invokeMethod<void>(PrinterMethod.printTextESC.value, data);
  }

  @override
  Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int x = 0,
    int y = 0,
    int height = 100,
    String type = "128",
    int width = 40,
    int heightMM = 30,
  }) async {
    final data = {
      "code": code,
      "x": x,
      "y": y,
      "height": height,
      "type": type,
      "width": width,
      "heightMM": heightMM,
      if (deviceId != null) "device_id": deviceId,
      if (connectionType != null) "connection_type": connectionType.value,
    };
    await _channel.invokeMethod<void>(PrinterMethod.printBarcode.value, data);
  }

  @override
  Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int x = 0,
    int y = 0,
    int size = 4,
    int width = 40,
    int heightMM = 30,
  }) async {
    final data = {
      "code": code,
      "x": x,
      "y": y,
      "size": size,
      "width": width,
      "heightMM": heightMM,
      if (deviceId != null) "device_id": deviceId,
      if (connectionType != null) "connection_type": connectionType.value,
    };
    await _channel.invokeMethod<void>(PrinterMethod.printQRCode.value, data);
  }

  @override
  Future<void> printBarcodeESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    String type = "128",
    int width = 2,
    int height = 162,
  }) async {
    final data = {
      "code": code,
      "type": type,
      "width": width,
      "height": height,
      if (deviceId != null) "device_id": deviceId,
      if (connectionType != null) "connection_type": connectionType.value,
    };
    await _channel.invokeMethod<void>(PrinterMethod.printBarcodeESC.value, data);
  }

  @override
  Future<void> printQRCodeESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int size = 8,
  }) async {
    final data = {
      "code": code,
      "size": size,
      if (deviceId != null) "device_id": deviceId,
      if (connectionType != null) "connection_type": connectionType.value,
    };
    await _channel.invokeMethod<void>(PrinterMethod.printQRCodeESC.value, data);
  }
}
