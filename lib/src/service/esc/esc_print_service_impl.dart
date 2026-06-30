import 'package:flutter/widgets.dart';
import '../../enums/enum.src.dart';
import '../../models/src.dart';
import '../../platform/printer_label.dart';
import '../../utils/image_resize.dart';
import '../../utils/widget_capture_helper.dart';
import 'esc_print_service_interface.dart';

class ESCPrintServiceImpl extends ESCPrintServicePlatform {
  @override
  Future<void> printWidget({
    required Widget widget,
    required TicketSize size,
    String? deviceId,
    PrinterConnectionType? connectionType,
    double pixelRatio = 2.5,
  }) async {
    final imageBytes = await WidgetCaptureHelper.captureFromLongWidget(
      widget,
      pixelRatio: pixelRatio,
    );
    return print(
      deviceId: deviceId,
      connectionType: connectionType,
      model: PrintThermalModel(image: imageBytes, size: size),
    );
  }

  @override
  Future<void> print({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel model,
  }) async {
    // Tự động tối ưu hóa kích thước ảnh cho máy in receipt để tăng tốc độ truyền qua Bluetooth
    final resizedImage = await resizeThermalImage(
      imageBytes: model.image,
      size: model.size,
    );

    final optimizedModel = PrintThermalModel(
      image: resizedImage,
      size: model.size,
    );

    await PrinterLabel.printESC(
      deviceId: deviceId,
      connectionType: connectionType,
      printThermalModel: optimizedModel,
    );
  }

  @override
  Future<void> printText({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
  }) {
    return PrinterLabel.printTextESC(
      deviceId: deviceId,
      connectionType: connectionType,
      text: text,
    );
  }

  @override
  Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    String type = "128",
    int width = 2,
    int height = 162,
  }) {
    return PrinterLabel.printBarcodeESC(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      type: type,
      width: width,
      height: height,
    );
  }

  @override
  Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int size = 8,
  }) {
    return PrinterLabel.printQRCodeESC(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      size: size,
    );
  }
}
