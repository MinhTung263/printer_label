import 'package:flutter/services.dart';
import '../../enums/enum.src.dart';
import '../../models/src.dart';
import '../../platform/printer_label.dart';
import 'esc_print_service_interface.dart';

class ESCPrintServiceImpl extends ESCPrintServicePlatform {
  @override
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

  @override
  Future<void> printExample({
    String? deviceId,
    PrinterConnectionType? connectionType,
  }) async {
    final image = await loadImageFromAssets("packages/printer_label/images/ticket.png");
    await PrinterLabel.printESC(
      deviceId: deviceId,
      connectionType: connectionType,
      printThermalModel: PrintThermalModel(image: image, size: TicketSize.mm58),
    );
  }

  @override
  Future<Uint8List> loadImageFromAssets(String path) async {
    final byteData = await rootBundle.load(path);
    return byteData.buffer.asUint8List();
  }
}
