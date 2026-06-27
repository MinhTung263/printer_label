import 'package:flutter/services.dart';

import '../src.dart';

/// A high-level helper service for thermal receipt printing using ESC/POS protocol.
class ESCPrintService {
  ESCPrintService._();

  /// The singleton instance of the [ESCPrintService].
  static final ESCPrintService instance = ESCPrintService._();

  /// Prints a thermal receipt from the specified [model].
  Future<void> print({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel model,
  }) async {
    await PrinterLabel.printESC(
      deviceId: deviceId,
      connectionType: connectionType,
      printThermalModel: model,
    );
  }

  /// Prints a sample receipt template for test purposes.
  Future<void> printExample({
    String? deviceId,
    PrinterConnectionType? connectionType,
  }) async {
    final image =
        await loadImageFromAssets("packages/printer_label/images/ticket.png");
    await PrinterLabel.printESC(
      deviceId: deviceId,
      connectionType: connectionType,
      printThermalModel: PrintThermalModel(image: image, size: TicketSize.mm58),
    );
  }

  /// Utility helper to load raw image bytes from asset bundles.
  Future<Uint8List> loadImageFromAssets(String path) async {
    final byteData = await rootBundle.load(path);
    return byteData.buffer.asUint8List();
  }
}
