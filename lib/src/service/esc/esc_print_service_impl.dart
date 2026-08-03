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
    double? pixelRatio,
  }) async {
    final imageBytes = await WidgetCaptureHelper.captureFromLongWidget(
      widget,
      pixelRatio: pixelRatio ?? (size == TicketSize.mm58 ? 1.6 : 1.8),
    );
    return print(
      deviceId: deviceId,
      connectionType: connectionType,
      model: PrintThermalModel(image: imageBytes, size: size),
    );
  }

  @override
  Future<void> printWidgetToDevices({
    required Widget widget,
    required TicketSize size,
    required List<String?> deviceIds,
    double? pixelRatio,
  }) async {
    if (deviceIds.isEmpty) return;

    // Chụp ảnh widget MỘT lần duy nhất rồi tối ưu kích thước, tránh render lại cho từng máy.
    final imageBytes = await WidgetCaptureHelper.captureFromLongWidget(
      widget,
      pixelRatio: pixelRatio ?? (size == TicketSize.mm58 ? 1.6 : 1.8),
    );
    final resizedImage = await resizeThermalImage(
      imageBytes: imageBytes,
      size: size,
    );
    final model = PrintThermalModel(image: resizedImage, size: size);

    // Gửi lệnh in tới tất cả máy SONG SONG. Native tuần tự hóa theo từng
    // connection nên các máy khác nhau không phải đợi nhau.
    await Future.wait(
      deviceIds.map(
        (id) => PrinterLabel.printESC(
          deviceId: id,
          printThermalModel: model,
        ),
      ),
    );
  }

  @override
  Future<bool> openDrawer({
    String? deviceId,
    PrinterConnectionType? connectionType,
  }) async {
    return PrinterLabel.openDrawer(
      deviceId: deviceId,
      connectionType: connectionType,
    );
  }

  @override
  Future<void> openDrawerMultiDevices({
    required List<String> deviceIds,
  }) async {
    await Future.wait(
      deviceIds.map(
        (id) => PrinterLabel.openDrawer(
          deviceId: id,
        ),
      ),
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
  }) async {
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
  }) async {
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
  }) async {
    return PrinterLabel.printQRCodeESC(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      size: size,
    );
  }
}
