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

  Future<void> _autoConnectIfNeeded(String? deviceId) async {
    try {
      // Chỉ tự động kích hoạt máy in tích hợp sẵn nếu không chỉ định thiết bị in ngoại vi cụ thể (deviceId null hoặc rỗng)
      if (deviceId == null || deviceId.trim().isEmpty) {
        final isConnected = await PrinterLabel.checkConnect();
        if (!isConnected) {
          final ok = await PrinterLabel.autoConnectBuiltIn();
          if (!ok) {
            // Tự động mở màn hình cấp quyền trong Cài đặt hệ thống
            await PrinterLabel.openPermissionSettings();
            throw Exception(
                'Không thể tự động kết nối máy in tích hợp sẵn. Đang mở Cài đặt ứng dụng để bạn bật Bluetooth/cấp quyền.');
          }
        }
      }
    } catch (e) {
      if (e.toString().contains('Không thể tự động kết nối')) {
        rethrow;
      }
    }
  }

  @override
  Future<void> print({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel model,
  }) async {
    await _autoConnectIfNeeded(deviceId);

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
    await _autoConnectIfNeeded(deviceId);
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
    await _autoConnectIfNeeded(deviceId);
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
    await _autoConnectIfNeeded(deviceId);
    return PrinterLabel.printQRCodeESC(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      size: size,
    );
  }
}
