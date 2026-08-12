import 'package:flutter/widgets.dart';
import '../../enums/enum.src.dart';
import '../../models/src.dart';
import 'esc_print_service_interface.dart';

/// A high-level helper service for thermal receipt printing using ESC/POS protocol.
class ESCPrintService {
  ESCPrintService._();

  /// The singleton instance of the [ESCPrintService].
  static final ESCPrintService instance = ESCPrintService._();

  /// Captures the given [widget] as an image and prints it using ESC/POS protocol.
  Future<void> printWidget({
    required Widget widget,
    required TicketSize size,
    String? deviceId,
    PrinterConnectionType? connectionType,
    double? pixelRatio,
    bool openDrawer = false,
  }) {
    return ESCPrintServicePlatform.instance.printWidget(
      widget: widget,
      size: size,
      deviceId: deviceId,
      connectionType: connectionType,
      pixelRatio: pixelRatio ?? (size == TicketSize.mm58 ? 1.6 : 1.8),
      openDrawer: openDrawer,
    );
  }

  /// Chụp [widget] một lần rồi in song song ra tất cả [deviceIds].
  ///
  /// Phù hợp khi in cùng một hóa đơn ra nhiều máy cùng lúc (ví dụ nhiều máy
  /// ngoài kèm máy in tích hợp) mà không phải render lại ảnh hay in tuần tự.
  /// Đặt [openDrawer] = true khi thanh toán TIỀN MẶT — két mở trước khi in, chỉ trên
  /// các máy ĐANG IN lượt này ([deviceIds]).
  Future<void> printWidgetToDevices({
    required Widget widget,
    required TicketSize size,
    required List<String?> deviceIds,
    double? pixelRatio,
    bool openDrawer = false,
  }) {
    return ESCPrintServicePlatform.instance.printWidgetToDevices(
      widget: widget,
      size: size,
      deviceIds: deviceIds,
      pixelRatio: pixelRatio,
      openDrawer: openDrawer,
    );
  }

  /// Opens the cash drawer connected to the thermal printer via ESC/POS command (ESC p) or native cash drawer port.
  Future<bool> openDrawer({
    String? deviceId,
    PrinterConnectionType? connectionType,
  }) {
    return ESCPrintServicePlatform.instance.openDrawer(
      deviceId: deviceId,
      connectionType: connectionType,
    );
  }

  /// Opens the cash drawer on multiple specified printer devices concurrently.
  Future<void> openDrawerMultiDevices({
    required List<String> deviceIds,
  }) {
    return ESCPrintServicePlatform.instance.openDrawerMultiDevices(
      deviceIds: deviceIds,
    );
  }

  /// Prints a thermal receipt from the specified [model].
  ///
  /// Đặt [openDrawer] = true khi thanh toán TIỀN MẶT — két mở trước khi gửi bill nên
  /// không phải đợi hết cuộn giấy. Xem [PrinterLabel.printESC] để biết chi tiết.
  Future<void> print({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel model,
    bool openDrawer = false,
  }) {
    return ESCPrintServicePlatform.instance.print(
      deviceId: deviceId,
      connectionType: connectionType,
      model: model,
      openDrawer: openDrawer,
    );
  }

  /// Prints raw text directly using ESC/POS printer commands.
  Future<void> printText({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
  }) {
    return ESCPrintServicePlatform.instance.printText(
      deviceId: deviceId,
      connectionType: connectionType,
      text: text,
    );
  }

  /// Prints a raw 1D barcode directly using ESC/POS printer commands.
  Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    String type = "128",
    int width = 2,
    int height = 162,
  }) {
    return ESCPrintServicePlatform.instance.printBarcode(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      type: type,
      width: width,
      height: height,
    );
  }

  /// Prints a raw QR code directly using ESC/POS printer commands.
  Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int size = 8,
  }) {
    return ESCPrintServicePlatform.instance.printQRCode(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      size: size,
    );
  }
}
