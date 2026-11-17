import 'dart:convert';
import 'dart:typed_data';

/// Lệnh tem TSPL (máy in tem Xprinter / TSC / Gprinter...) — cùng chuỗi lệnh bản
/// Android gửi qua SDK: `SIZE` → `GAP` → `REFERENCE` → `DIRECTION` → (`HOME`) →
/// `CLS` → `BITMAP` → `PRINT`.
abstract final class TsplCommands {
  static String _mm(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  /// Một tem: ảnh [bitmap] (1 bit, [widthBytes] byte mỗi dòng, [heightDots] dòng).
  /// [copies]: số bản của tem này. [home]: dò khe decal trước khi in (khổ 3 tem).
  /// [referenceX] / [referenceY]: dời gốc toạ độ (chấm, 8 chấm = 1mm; dương = sang
  /// phải / xuống dưới) — chỉnh tem in lệch mà không phải sửa ảnh. [ribbon]: xem
  /// [TsplLabelSpec.ribbon].
  static Uint8List label({
    required Uint8List bitmap,
    required int widthBytes,
    required int heightDots,
    required num widthMm,
    required num heightMm,
    num gapMm = 2,
    num gapOffsetMm = 0,
    int copies = 1,
    bool home = false,
    int referenceX = 0,
    int referenceY = 0,
    bool? ribbon,
  }) {
    final head = [
      'SIZE ${_mm(widthMm)} mm,${_mm(heightMm)} mm',
      'GAP ${_mm(gapMm)} mm,${_mm(gapOffsetMm)} mm',
      // Máy in truyền nhiệt (ruy-băng mực): TSPL2 là `SET RIBBON ON` (không có "SET" thì máy
      // bỏ qua lệnh và in như nhiệt trực tiếp — ra tem trắng).
      if (ribbon != null) 'SET RIBBON ${ribbon ? 'ON' : 'OFF'}',
      'REFERENCE $referenceX,$referenceY',
      'DIRECTION 0',
      if (home) 'HOME',
      'CLS',
    ].map((l) => '$l\r\n').join();
    final out = BytesBuilder(copy: false)
      ..add(ascii.encode(head))
      // BITMAP x,y,widthBytes,height,mode(0=ghi đè),<dữ liệu thô>
      ..add(ascii.encode('BITMAP 0,0,$widthBytes,$heightDots,0,'))
      ..add(bitmap)
      ..add(ascii.encode('\r\nPRINT 1,${copies < 1 ? 1 : copies}\r\n'));
    return out.takeBytes();
  }

  /// Dò khe tem: máy in cuốn vài tem để học bề dài tem + khe thật của cuộn (`GAPDETECT`)
  /// — dùng khi tem in lệch dần theo từng hàng hoặc mới thay cuộn tem khác. [widthMm] /
  /// [heightMm] / [gapMm] là khổ đã khai báo (máy dò xong sẽ dùng số đo thật).
  static Uint8List gapDetect({
    required num widthMm,
    required num heightMm,
    num gapMm = 2,
  }) => ascii.encode(
    'SIZE ${_mm(widthMm)} mm,${_mm(heightMm)} mm\r\n'
    'GAP ${_mm(gapMm)} mm,0 mm\r\n'
    'GAPDETECT\r\n',
  );
}
