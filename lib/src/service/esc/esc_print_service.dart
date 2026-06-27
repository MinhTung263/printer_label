import 'dart:typed_data';

import '../../enums/enum.src.dart';
import '../../models/src.dart';
import 'esc_print_service_interface.dart';

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
  }) {
    return ESCPrintServicePlatform.instance.print(
      deviceId: deviceId,
      connectionType: connectionType,
      model: model,
    );
  }

  /// Prints a sample receipt template for test purposes.
  Future<void> printExample({
    String? deviceId,
    PrinterConnectionType? connectionType,
  }) {
    return ESCPrintServicePlatform.instance.printExample(
      deviceId: deviceId,
      connectionType: connectionType,
    );
  }

  /// Utility helper to load raw image bytes from asset bundles.
  Future<Uint8List> loadImageFromAssets(String path) {
    return ESCPrintServicePlatform.instance.loadImageFromAssets(path);
  }
}
