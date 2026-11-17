import 'dart:convert';
import 'dart:typed_data';

import 'escpos_commands.dart';

/// Cách làm máy in "lên tiếng / cử động" để nhận ra đang xem máy nào (không in gì ra giấy).
enum BeepStyle {
  /// Máy hoá đơn ESC/POS: `ESC B` (còi).
  escpos,

  /// Máy tem TSPL: `SOUND` (còi).
  tsplSound,

  /// Máy tem TSPL không có còi: `HOME` — cuộn tem nhích tới khe tem đầu tiên (nghe tiếng động cơ, thấy tem
  /// chạy; không in gì).
  tsplHome,
}

/// Lệnh kêu bíp ngắn để người dùng NHẬN RA máy in nào đang cắm / đang chọn (không in gì ra giấy):
/// máy hoá đơn ESC/POS dùng `ESC B`, máy tem TSPL dùng `SOUND`. Máy không có còi thì bỏ qua lệnh.
abstract final class PrinterBeep {
  /// Byte lệnh bíp cho máy tem ([label] = true) hoặc máy hoá đơn.
  static Uint8List bytes({required bool label}) =>
      style(label ? BeepStyle.tsplSound : BeepStyle.escpos);

  /// Byte lệnh của một cách bíp.
  static Uint8List style(BeepStyle s) => switch (s) {
    BeepStyle.escpos => Uint8List.fromList(EscPosCommands.beep),
    BeepStyle.tsplSound => Uint8List.fromList(ascii.encode('SOUND 5,200\r\n')),
    BeepStyle.tsplHome => Uint8List.fromList(ascii.encode('HOME\r\n')),
  };

  /// Thứ tự các cách thử khi khách bấm bíp mà "không nghe thấy": cách đúng với loại máy trước ([label]:
  /// `true` tem, `false` hoá đơn, `null` chưa rõ loại), rồi các cách còn lại. Máy chưa rõ loại thử ESC/POS
  /// trước vì lệnh nhị phân đó máy tem bỏ qua, còn lệnh chữ của máy tem có thể in ra một dòng trên máy hoá đơn.
  static List<BeepStyle> plan({bool? label}) => switch (label) {
    true => [BeepStyle.tsplSound, BeepStyle.tsplHome, BeepStyle.escpos],
    false => [BeepStyle.escpos, BeepStyle.tsplSound],
    null => [BeepStyle.escpos, BeepStyle.tsplSound, BeepStyle.tsplHome],
  };
}
