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
  bool? _currentScanFilterPrinterOnly;
  Stream<UsbConnectionEvent>? _usbDeviceStream;

  @override
  Future<bool> bluetoothEnabled() async {
    return await _channel
            .invokeMethod<bool>(PrinterMethod.bluetooth_enabled.name) ??
        false;
  }

  @override
  Future<bool> checkConnect({String? deviceId}) async {
    final targetId = deviceId?.trim();
    if (targetId == null || targetId.isEmpty) return false;
    return await _channel.invokeMethod<bool>(PrinterMethod.checkConnect.name, {
          "device_id": targetId,
        }) ??
        false;
  }

  @override
  Future<PrinterStatus> checkPrinterStatus({String? deviceId, String? type}) async {
    final targetId = deviceId?.trim();
    final String? statusStr = await _channel.invokeMethod<String>(
      PrinterMethod.check_printer_status.name,
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
      PrinterMethod.checkConnect.name,
    );
    if (result == null) return {};
    return result.map((key, value) => MapEntry(key.toString(), value == true));
  }

  @override
  Future<bool> disconnectPrinter({String? deviceId}) async {
    final targetId = deviceId?.trim();
    return await _channel.invokeMethod<bool>(PrinterMethod.disconnect.name, {
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
    return await _channel.invokeMethod<bool>(PrinterMethod.connect_lan.name, {
          "ip_address": targetIp,
        }) ??
        false;
  }

  @override
  Future<bool> startBluetoothScan() async {
    return await _channel.invokeMethod<bool>(PrinterMethod.scan_bt.name) ??
        false;
  }

  @override
  Future<bool> stopBluetoothScan() async {
    return await _channel.invokeMethod<bool>(PrinterMethod.stop_scan_bt.name) ??
        false;
  }

  @override
  Future<String?> get platformVersion async {
    final String? version = await _channel
        .invokeMethod<String>(PrinterMethod.getPlatformVersion.name);
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
    await _channel.invokeMethod<void>(PrinterMethod.print_label.name, data);
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
    await _channel.invokeMethod<void>(PrinterMethod.print_image.name, data);
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
          PrinterMethod.print_image_esc.name, data);
    } catch (e, stack) {
      debugPrint("Error printing ESC: $e\n$stack");
      rethrow;
    }
  }

  @override
  Future<bool> connectBluetooth({required String macAddress}) async {
    final targetMac = macAddress.trim();
    if (targetMac.isEmpty) return false;
    return await _channel.invokeMethod<bool>(PrinterMethod.connect_bt.name, {
          "mac_address": targetMac,
        }) ??
        false;
  }

  @override
  Future<bool> autoConnectBuiltIn() async {
    return await _channel.invokeMethod<bool>(PrinterMethod.auto_connect_built_in.name) ?? false;
  }

  @override
  Future<bool> disconnectBuiltIn() async {
    return await disconnectPrinter(deviceId: 'BUILT_IN');
  }



  @override
  Future<bool> hasBuiltInPrinter() async {
    return await _channel.invokeMethod<bool>(PrinterMethod.has_built_in_printer.name) ?? false;
  }

  @override
  Future<int> getBuiltInPrinterPaperSize() async {
    return await _channel.invokeMethod<int>(PrinterMethod.get_built_in_printer_paper_size.name) ?? 0;
  }

  @override
  Future<List<BluetoothDeviceModel>> getBluetoothDevices({bool filterPrinterOnly = true}) async {
    final result = await _channel.invokeMethod<List>(
      PrinterMethod.get_bluetooth_devices.name,
      {'filter_printer_only': filterPrinterOnly},
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
  Stream<BluetoothDeviceModel> bluetoothScanStream({bool filterPrinterOnly = true}) {
    // Nếu filterPrinterOnly thay đổi → tạo lại stream mới với arguments mới
    if (_bluetoothScanStream == null || _currentScanFilterPrinterOnly != filterPrinterOnly) {
      _currentScanFilterPrinterOnly = filterPrinterOnly;
      _bluetoothScanStream = _scanChannel
          .receiveBroadcastStream({'filter_printer_only': filterPrinterOnly})
          .map((e) {
        final map = Map<Object?, Object?>.from(e as Map);
        return BluetoothDeviceModel.fromMap({
          'name': map['name']?.toString() ?? 'Unknown',
          'identifier': map['identifier']?.toString(),
          'mac': map['mac']?.toString(),
        });
      });
    }
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
    await _channel.invokeMethod<void>(PrinterMethod.print_text.name, data);
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
    await _channel.invokeMethod<void>(PrinterMethod.print_text_esc.name, data);
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
    await _channel.invokeMethod<void>(PrinterMethod.print_barcode.name, data);
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
    await _channel.invokeMethod<void>(PrinterMethod.print_qrcode.name, data);
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
    await _channel.invokeMethod<void>(PrinterMethod.print_barcode_esc.name, data);
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
    await _channel.invokeMethod<void>(PrinterMethod.print_qrcode_esc.name, data);
  }
}
