import 'package:flutter/services.dart';

import '../src.dart';

class ESCPrintService {
  ESCPrintService._();
  static final ESCPrintService instance = ESCPrintService._();

  Future<void> print({
    required PrintThermalModel model,
  }) async {
    await PrinterLabel.printESC(
      printThermalModel: model,
    );
  }

  Future<void> printExample() async {
    final image =
        await loadImageFromAssets("packages/printer_label/images/ticket.png");
    await PrinterLabel.printESC(
      printThermalModel: PrintThermalModel(image: image),
    );
  }

  Future<Uint8List> loadImageFromAssets(String path) async {
    final byteData = await rootBundle.load(path);
    return byteData.buffer.asUint8List();
  }
}
