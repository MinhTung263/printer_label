import 'package:flutter/material.dart';
import '../../enums/enum.src.dart';
import '../../models/src.dart';
import '../../platform/printer_label.dart';
import 'label_from_widget.dart';
import 'label_printer_service_interface.dart';

class LabelPrintServiceImpl extends LabelPrintServicePlatform {
  @override
  Future<void> printLabels<T>({
    required List<T> items,
    required BuildContext context,
    required LabelPerRow labelPerRow,
    PrinterConnectionType? connectionType,
    String? deviceId,
    required Widget Function(T item, Dimensions dimensions) itemBuilder,
    required int Function(T item) quantity,
  }) async {
    final images = await LabelFromWidget.captureImages<T>(
      items,
      context,
      labelPerRow: labelPerRow,
      itemBuilder: itemBuilder,
      quantity: quantity,
    );

    if (images.isEmpty) return;

    final model = LabelModel(
      images: images,
      labelPerRow: labelPerRow,
    );

    await PrinterLabel.printLabel(
      deviceId: deviceId,
      connectionType: connectionType,
      labelModel: model,
    );
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
  }) {
    return PrinterLabel.printText(
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
  }) {
    return PrinterLabel.printBarcode(
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
  }) {
    return PrinterLabel.printQRCode(
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
