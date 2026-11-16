import 'dart:isolate';
import 'dart:typed_data';

import 'escpos_commands.dart';
import 'escpos_raster.dart';
import 'printer_port.dart';

/// In ảnh hoá đơn (PNG) ra một [PrinterPort] — cùng luồng với app Android:
/// (mở két) → hỏi giấy → khởi tạo → ảnh → đẩy giấy → cắt, [copies] bản liền nhau.
abstract final class EscPosPrinter {
  /// Ảnh PNG tới cỡ này (byte) mã hoá không cần isolate (≈30–50ms cho phiếu dài).
  static const int _inlineMaxBytes = 160 * 1024;

  /// Ném [FormatException] nếu không đọc được ảnh, [PrinterStatusException] khi
  /// hết giấy / mở nắp, [SocketException]... khi không kết nối được máy in.
  static Future<void> printImage(
    PrinterPort port,
    Uint8List png, {
    int copies = 1,
    bool openDrawer = false,
    bool checkStatus = true,
    bool beep = false,
    bool cut = true,
  }) async {
    // Giải mã + mã hoá ở isolate riêng: ảnh hoá đơn dài làm đứng giao diện.
    // Ảnh nhỏ (phiếu thường) mã hoá ngay — tạo isolate tốn thêm 100–300ms (nhất là bản debug); chỉ ảnh
    // lớn mới đưa sang isolate để không đứng giao diện.
    final raster = png.length <= _inlineMaxBytes
        ? EscPosRaster.encodeImageBytes(png)
        : await Isolate.run(() => EscPosRaster.encodeImageBytes(png));
    if (raster == null) throw const FormatException('Ảnh hoá đơn không hợp lệ');
    if (openDrawer) {
      // Lỗi mở két không chặn in.
      try {
        await port.send(
          Uint8List.fromList(EscPosCommands.openDrawer),
          checkStatus: false,
        );
      } catch (_) {}
    }
    final receipt = EscPosCommands.receipt(raster, copies: copies, cut: cut);
    await port.send(
      beep ? Uint8List.fromList([...receipt, ...EscPosCommands.beep]) : receipt,
      checkStatus: checkStatus,
    );
  }
}
