import 'dart:typed_data';

import 'paper_status.dart';

/// Đường gửi byte thô tới một máy in (LAN, USB, COM...). Không qua driver/spooler
/// của hệ điều hành nên máy tính không phải cài driver máy in.
abstract interface class PrinterPort {
  /// Mã ổn định của máy in (VD `tcp://192.168.1.50:9100`) — dùng để khoá tuần tự.
  String get id;

  /// Gửi [data] tới máy in. Khi [checkStatus] thì hỏi trạng thái giấy trước và
  /// ném [PrinterStatusException] nếu hết giấy / mở nắp (không gửi phiếu).
  Future<void> send(Uint8List data, {bool checkStatus = true});

  /// Hỏi trạng thái giấy; [PaperStatus.unknown] nếu máy không trả lời.
  Future<PaperStatus> queryStatus();
}
