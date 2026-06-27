import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../enums/enum.src.dart';
import '../../models/src.dart';
import '../../platform/printer_label.dart';
import '../../utils/image_resize.dart';
import '../label/label_from_widget.dart';
import 'cup_sticker_printer_interface.dart';

class CupStickerPrinterImpl extends CupStickerPrinterPlatform {
  @override
  Future<void> printSticker({
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

  @override
  Future<void> printWithWidgets({
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

  @override
  Future<Uint8List> captureSticker({
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
