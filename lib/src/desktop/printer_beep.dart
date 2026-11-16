import 'dart:convert';
import 'dart:typed_data';

import 'escpos_commands.dart';

/// Lệnh kêu bíp ngắn để người dùng NHẬN RA máy in nào đang cắm / đang chọn (không in gì ra giấy):
/// máy hoá đơn ESC/POS dùng `ESC B`, máy tem TSPL dùng `SOUND`. Máy không có còi thì bỏ qua lệnh.
abstract final class PrinterBeep {
  /// Byte lệnh bíp cho máy tem ([label] = true) hoặc máy hoá đơn.
  static Uint8List bytes({required bool label}) => label
      ? Uint8List.fromList(ascii.encode('SOUND 5,200\r\n'))
      : Uint8List.fromList(EscPosCommands.beep);
}
