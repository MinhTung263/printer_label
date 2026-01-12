import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../src.dart';

class CupStickerPrinter {
  const CupStickerPrinter._();

  static Future<void> printSticker({
    required List<Uint8List> imageBytesList,
    required CupStickerSize size,
  }) async {
    final images = <Uint8List>[];

    for (final bytes in imageBytesList) {
      images.add(
        await resizeImage(
          imageBytes: bytes,
          size: size,
        ),
      );
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
      barcodeImageModel: model,
    );
  }

  static Future<void> printWithWidgets({
    required List<Widget> widgets,
    BuildContext? context,
    required CupStickerSize size,
    int? widthOffsetMm,
    double? paddingMm,
  }) async {
    final images = <Uint8List>[];

    for (final widget in widgets) {
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
    final heightMm = size.heightMm.toInt();

    final model = LabelModel(
      images: images,
      labelPerRow: LabelPerRow.single.copyWith(
        width: widthMm,
        height: heightMm,
        x: 0,
        y: 0,
      ),
    );

    await PrinterLabel.printLabel(
      barcodeImageModel: model,
    );
  }
}
