import 'package:flutter/material.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../../enums/enum.src.dart';
import 'label_printer_service_impl.dart';

abstract class LabelPrintServicePlatform extends PlatformInterface {
  LabelPrintServicePlatform() : super(token: _token);

  static const Object _token = Object();

  static LabelPrintServicePlatform _instance = LabelPrintServiceImpl();

  static LabelPrintServicePlatform get instance => _instance;

  static set instance(LabelPrintServicePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> printLabels<T>({
    required List<T> items,
    required BuildContext context,
    required LabelPerRow labelPerRow,
    PrinterConnectionType? connectionType,
    String? deviceId,
    required Widget Function(T item) itemBuilder,
    required int Function(T item) quantity,
  });

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
  });

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
  });

  Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int x = 0,
    int y = 0,
    int size = 4,
    int width = 40,
    int heightMM = 30,
  });
}
