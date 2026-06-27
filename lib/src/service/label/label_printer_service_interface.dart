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
    required Widget Function(T item, Dimensions dimensions) itemBuilder,
    required int Function(T item) quantity,
  });
}
