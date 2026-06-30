import 'package:flutter/widgets.dart';
import '../../enums/enum.src.dart';
import '../../models/src.dart';
import 'esc_print_service_interface.dart';

/// A high-level helper service for thermal receipt printing using ESC/POS protocol.
class ESCPrintService {
  ESCPrintService._();

  /// The singleton instance of the [ESCPrintService].
  static final ESCPrintService instance = ESCPrintService._();

  /// Captures the given [widget] as an image and prints it using ESC/POS protocol.
  Future<void> printWidget({
    required Widget widget,
    required TicketSize size,
    String? deviceId,
    PrinterConnectionType? connectionType,
    double pixelRatio = 2.5,
  }) {
    return ESCPrintServicePlatform.instance.printWidget(
      widget: widget,
      size: size,
      deviceId: deviceId,
      connectionType: connectionType,
      pixelRatio: pixelRatio,
    );
  }

  /// Prints a thermal receipt from the specified [model].
  Future<void> print({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel model,
  }) {
    return ESCPrintServicePlatform.instance.print(
      deviceId: deviceId,
      connectionType: connectionType,
      model: model,
    );
  }



  /// Prints raw text directly using ESC/POS printer commands.
  Future<void> printText({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
  }) {
    return ESCPrintServicePlatform.instance.printText(
      deviceId: deviceId,
      connectionType: connectionType,
      text: text,
    );
  }

  /// Prints a raw 1D barcode directly using ESC/POS printer commands.
  Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    String type = "128",
    int width = 2,
    int height = 162,
  }) {
    return ESCPrintServicePlatform.instance.printBarcode(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      type: type,
      width: width,
      height: height,
    );
  }

  /// Prints a raw QR code directly using ESC/POS printer commands.
  Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int size = 8,
  }) {
    return ESCPrintServicePlatform.instance.printQRCode(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      size: size,
    );
  }
}
