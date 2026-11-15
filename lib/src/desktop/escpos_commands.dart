import 'dart:typed_data';

/// Các lệnh ESC/POS dùng khi in hoá đơn — giống bản native Android.
abstract final class EscPosCommands {
  /// `ESC @` — khởi tạo máy in.
  static const List<int> init = [0x1B, 0x40];

  /// `ESC a 1` — căn giữa.
  static const List<int> alignCenter = [0x1B, 0x61, 0x01];

  /// Đẩy 5 dòng trước khi cắt.
  static const List<int> feed5 = [0x0A, 0x0A, 0x0A, 0x0A, 0x0A];

  /// `GS V 66 1` — đẩy giấy rồi cắt nửa.
  static const List<int> cut = [0x1D, 0x56, 0x42, 0x01];

  /// `ESC p` cho cả hai chân két (0 và 1). Máy không gắn két thì vô hại.
  static const List<int> openDrawer = [
    0x1B, 0x70, 0x00, 0x19, 0xFA, //
    0x1B, 0x70, 0x01, 0x19, 0xFA,
  ];

  /// `DLE EOT n` — hỏi trạng thái tức thời (n = 2: offline, n = 4: cuộn giấy).
  static List<int> realtimeStatus(int n) => [0x10, 0x04, n];

  /// Còi báo bếp `ESC B n t`: kêu 3 lần, mỗi lần 100ms (máy không có còi bỏ
  /// qua lệnh này).
  static const List<int> beep = [0x1B, 0x42, 0x03, 0x02];

  /// Phiếu chữ đơn giản (in thử): mỗi dòng một dòng, căn giữa, rồi cắt. Chữ
  /// tiếng Việt được bỏ dấu — in thô không có phông tiếng Việt.
  static Uint8List textTicket(List<String> lines) {
    final out = BytesBuilder(copy: false)
      ..add(init)
      ..add(alignCenter);
    for (final line in lines) {
      out
        ..add(asciiFold(line).codeUnits)
        ..addByte(0x0A);
    }
    out
      ..add(feed5)
      ..add(cut);
    return out.takeBytes();
  }

  static const _from =
      'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  static const _to =
      'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

  /// Bỏ dấu tiếng Việt; ký tự ngoài ASCII còn lại thành `?`.
  static String asciiFold(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final lower = ch.toLowerCase();
      final i = _from.indexOf(lower);
      if (i >= 0) {
        b.write(ch == lower ? _to[i] : _to[i].toUpperCase());
      } else {
        b.write(r < 0x80 ? ch : '?');
      }
    }
    return b.toString();
  }

  /// Một bản hoá đơn: khởi tạo, căn giữa, ảnh [raster], đẩy giấy, cắt.
  ///
  /// [copies] bản được NỐI SẴN thành một khối để gửi liền một lần — không để khoảng
  /// hở giữa các bản cho lệnh `ESC @` của bản sau huỷ phần đuôi bản trước.
  static Uint8List receipt(Uint8List raster, {int copies = 1}) {
    final one = BytesBuilder(copy: false)
      ..add(init)
      ..add(alignCenter)
      ..add(raster)
      ..add(feed5)
      ..add(cut);
    final oneCopy = one.takeBytes();
    if (copies <= 1) return oneCopy;
    final all = BytesBuilder(copy: false);
    for (var i = 0; i < copies; i++) {
      all.add(oneCopy);
    }
    return all.takeBytes();
  }
}
