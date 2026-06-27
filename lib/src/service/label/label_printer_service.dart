import 'package:flutter/material.dart';

import '../../enums/enum.src.dart';
import 'label_printer_service_interface.dart';

/// A high-level helper service for printing labels from Flutter widgets.
class LabelPrintService {
  LabelPrintService._();
  
  /// The singleton instance of the [LabelPrintService].
  static final LabelPrintService instance = LabelPrintService._();

  /// Captures and prints a list of [items] onto paper labels.
  /// 
  /// Uses [itemBuilder] to define the widget layout for each item,
  /// resolves quantities for each, packs them according to [labelPerRow],
  /// and forwards the print job to [LabelPrintServicePlatform].
  Future<void> printLabels<T>({
    required List<T> items,
    required BuildContext context,
    required LabelPerRow labelPerRow,

    /// Optional filter for connection type: USB, LAN, or Bluetooth
    PrinterConnectionType? connectionType,

    /// Optional target device ID (e.g. LAN IP address or Bluetooth UUID)
    String? deviceId,
    required Widget Function(T item, Dimensions dimensions) itemBuilder,
    required int Function(T item) quantity,
  }) {
    return LabelPrintServicePlatform.instance.printLabels<T>(
      items: items,
      context: context,
      labelPerRow: labelPerRow,
      connectionType: connectionType,
      deviceId: deviceId,
      itemBuilder: itemBuilder,
      quantity: quantity,
    );
  }

  /// Prints raw text directly using TSPL printer commands.
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
  }) {
    return LabelPrintServicePlatform.instance.printText(
      deviceId: deviceId,
      connectionType: connectionType,
      text: text,
      x: x,
      y: y,
      font: font,
      rotation: rotation,
      sizeX: sizeX,
      sizeY: sizeY,
      width: width,
      height: height,
    );
  }

  /// Prints a raw 1D barcode directly using TSPL printer commands.
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
  }) {
    return LabelPrintServicePlatform.instance.printBarcode(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      x: x,
      y: y,
      height: height,
      type: type,
      width: width,
      heightMM: heightMM,
    );
  }

  /// Prints a raw QR code directly using TSPL printer commands.
  Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int x = 0,
    int y = 0,
    int size = 4,
    int width = 40,
    int heightMM = 30,
  }) {
    return LabelPrintServicePlatform.instance.printQRCode(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      x: x,
      y: y,
      size: size,
      width: width,
      heightMM: heightMM,
    );
  }
}
