import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../../enums/enum.src.dart';
import '../../models/src.dart';
import 'esc_print_service_impl.dart';

abstract class ESCPrintServicePlatform extends PlatformInterface {
  ESCPrintServicePlatform() : super(token: _token);

  static const Object _token = Object();

  static ESCPrintServicePlatform _instance = ESCPrintServiceImpl();

  static ESCPrintServicePlatform get instance => _instance;

  static set instance(ESCPrintServicePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Captures the given [widget] as an image and prints it using ESC/POS protocol.
  Future<void> printWidget({
    required Widget widget,
    required TicketSize size,
    String? deviceId,
    PrinterConnectionType? connectionType,
    double? pixelRatio,
    bool openDrawer,
  });

  /// Chụp [widget] một lần rồi in song song ra tất cả [deviceIds].
  ///
  /// Dùng khi cần in cùng một hóa đơn ra nhiều máy (máy ngoài + máy tích hợp).
  /// Ảnh chỉ được render một lần và các lệnh gửi chạy song song để không phải
  /// đợi từng máy in xong tuần tự.
  /// [openDrawer] = true thì mở két TRƯỚC khi in, trên CÁC MÁY ĐANG IN lượt này
  /// ([deviceIds]). Máy có két nhưng không in lượt này sẽ không bị đụng tới.
  Future<void> printWidgetToDevices({
    required Widget widget,
    required TicketSize size,
    required List<String?> deviceIds,
    double? pixelRatio,
    bool openDrawer,
  });

  /// In hóa đơn. [openDrawer] = true thì mở két TRƯỚC khi gửi bill (thanh toán tiền mặt).
  /// Xem [PrinterLabel.printESC] để biết lý do mở trước thay vì sau.
  Future<void> print({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel model,
    bool openDrawer,
  });

  /// Opens the connected cash drawer via ESC/POS command (ESC p) or native cash drawer port.
  Future<bool> openDrawer({
    String? deviceId,
    PrinterConnectionType? connectionType,
  });

  /// Opens the cash drawer on multiple specified printer devices concurrently.
  Future<void> openDrawerMultiDevices({
    required List<String> deviceIds,
  });



  Future<void> printText({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
  });

  Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    String type = "128",
    int width = 2,
    int height = 162,
  });

  Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int size = 8,
  });
}
