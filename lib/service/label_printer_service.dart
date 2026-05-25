import 'package:flutter/material.dart';

import '../enums/enum.src.dart';
import '../models/src.dart';
import '../printer_label.dart';
import 'service.src.dart';

class LabelPrintService {
  LabelPrintService._();
  static final LabelPrintService instance = LabelPrintService._();

  Future<void> printLabels<T>({
    required List<T> items,
    required BuildContext context,
    required LabelPerRow labelPerRow,

    /// Chỉ định theo loại kết nối: "USB" | "LAN" | "BT"
    PrinterConnectionType? connectionType,

    /// Hoặc chỉ định thiết bị cụ thể theo id
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
      barcodeImageModel: model,
    );
  }
}
