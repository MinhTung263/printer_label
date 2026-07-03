import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../../enums/enum.src.dart';
import '../../models/src.dart';
import 'esc_print_service_impl.dart';

abstract class ESCPrintServicePlatform extends PlatformInterface {
  ESCPrintServicePlatform() : super(token: _token);

  static const Object _token = Object();

  static ESCPrintServicePlatform _instance = ESCPrintServiceImpl();

  static ESCPrintServicePlatform get instance => _instance;

  static set instance(ESCPrintServicePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Captures the given [widget] as an image and prints it using ESC/POS protocol.
  Future<void> printWidget({
    required Widget widget,
    required TicketSize size,
    String? deviceId,
    PrinterConnectionType? connectionType,
    double? pixelRatio,
  });

  Future<void> print({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel model,
  });



  Future<void> printText({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
  });

  Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    String type = "128",
    int width = 2,
    int height = 162,
  });

  Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int size = 8,
  });
}
