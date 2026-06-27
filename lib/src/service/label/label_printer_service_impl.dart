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
}
