import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../src.dart';

/// A specialized printer service for rendering and printing cup stickers/labels.
class CupStickerPrinter {
  const CupStickerPrinter._();

  /// Prints raw image bytes list as cup stickers, automatically resizing them to match [size].
  static Future<void> printSticker({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required List<Uint8List> imageBytesList,
    required CupStickerSize size,
  }) async {
    final images = <Uint8List>[];

    for (final bytes in imageBytesList) {
      images.add(await resizeImage(imageBytes: bytes, size: size));
    }

    final model = LabelModel(
      images: images,
      labelPerRow: LabelPerRow.single.copyWith(
        width: size.widthMm.toInt(),
        height: size.heightMm.toInt(),
        x: 0,
        y: 0,
      ),
    );
    await PrinterLabel.printLabel(
      deviceId: deviceId,
      connectionType: connectionType,
      labelModel: model,
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
  }) async {
    final images = <Uint8List>[];

    for (final widget in widgets) {
      if (context != null && !context.mounted) return;
      final bytes = await LabelFromWidget.captureFromWidget(
        widget,
        context: context,
      );
      final resized = await resizeImage(
        imageBytes: bytes,
        size: size,
        paddingMm: paddingMm,
      );
      images.add(resized);
    }

    final widthMm = size.widthMm.toInt() + (widthOffsetMm ?? 0);
    final model = LabelModel(
      images: images,
      labelPerRow: LabelPerRow.single.copyWith(
        width: widthMm,
        height: size.heightMm.toInt(),
        x: 0,
        y: 0,
      ),
    );

    await PrinterLabel.printLabel(
      deviceId: deviceId,
      connectionType: connectionType,
      labelModel: model,
    );
  }

  /// Captures a [widget] and resizes it to match [size] — returns the exact
  /// image bytes that the printer would receive via [printWithWidgets].
  static Future<Uint8List> captureSticker({
    required Widget widget,
    required CupStickerSize size,
    BuildContext? context,
    double? paddingMm,
  }) async {
    final raw = await LabelFromWidget.captureFromWidget(
      widget,
      context: context,
    );
    return resizeImage(imageBytes: raw, size: size, paddingMm: paddingMm);
  }
}
