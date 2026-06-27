import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../enums/enum.src.dart';
import 'cup_sticker_printer_interface.dart';

/// A specialized printer service for rendering and printing cup stickers/labels.
class CupStickerPrinter {
  const CupStickerPrinter._();

  /// Prints raw image bytes list as cup stickers, automatically resizing them to match [size].
  static Future<void> printSticker({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required List<Uint8List> imageBytesList,
    required CupStickerSize size,
  }) {
    return CupStickerPrinterPlatform.instance.printSticker(
      deviceId: deviceId,
      connectionType: connectionType,
      imageBytesList: imageBytesList,
      size: size,
    );
  }

  /// Builds sticker images from a list of Flutter [widgets] and prints them.
  /// 
  /// Renders widgets, resizes the output according to the [size] and optional [widthOffsetMm]
  /// or [paddingMm], and prints.
  static Future<void> printWithWidgets({
    required List<Widget> widgets,
    BuildContext? context,
    required CupStickerSize size,
    int? widthOffsetMm,
    double? paddingMm,
    String? deviceId,
    PrinterConnectionType? connectionType,
  }) {
    return CupStickerPrinterPlatform.instance.printWithWidgets(
      widgets: widgets,
      context: context,
      size: size,
      widthOffsetMm: widthOffsetMm,
      paddingMm: paddingMm,
      deviceId: deviceId,
      connectionType: connectionType,
    );
  }

  /// Captures a [widget] and resizes it to match [size] — returns the exact
  /// image bytes that the printer would receive via [printWithWidgets].
  static Future<Uint8List> captureSticker({
    required Widget widget,
    required CupStickerSize size,
    BuildContext? context,
    double? paddingMm,
  }) {
    return CupStickerPrinterPlatform.instance.captureSticker(
      widget: widget,
      size: size,
      context: context,
      paddingMm: paddingMm,
    );
  }
}
