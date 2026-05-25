import 'package:flutter/services.dart';

import '../src.dart';

class ESCPrintService {
  ESCPrintService._();
  static final ESCPrintService instance = ESCPrintService._();

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

  Future<Uint8List> loadImageFromAssets(String path) async {
    final byteData = await rootBundle.load(path);
    return byteData.buffer.asUint8List();
  }
}
