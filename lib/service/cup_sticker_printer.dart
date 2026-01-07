import 'dart:typed_data';

import '../enums/enum.src.dart';
import '../src.dart';

class CupStickerPrinter {
  const CupStickerPrinter._();

  static Future<void> print({
    required List<Uint8List> imageBytesList,
    required CupStickerSize size,
  }) async {
    final images = <Uint8List>[];

    for (final bytes in imageBytesList) {
      images.add(
        await resizeImage(
          imageBytes: bytes,
          widthMm: size.widthMm,
          heightMm: size.heightMm,
        ),
      );
    }

    final model = LabelModel(
      images: images,
      labelPerRow: LabelPerRow.one.copyWith(
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
}
