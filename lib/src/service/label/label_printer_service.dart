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
}
