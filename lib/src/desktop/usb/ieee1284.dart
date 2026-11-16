/// Chuỗi định danh IEEE 1284 mà máy in USB tự báo, VD
/// `SERN:03365B350113;MFG:4BARCODE;CMD:TSPL2;MDL:3B-300B;CLS:PRINTER;`.
abstract final class Ieee1284 {
  /// Tách thành `{KHOÁ: giá trị}` (khoá viết hoa; tên đầy đủ `MANUFACTURER` / `MODEL` /
  /// `COMMAND SET` được đưa về `MFG` / `MDL` / `CMD`).
  static Map<String, String> parse(String id) {
    final out = <String, String>{};
    for (final part in id.split(';')) {
      final i = part.indexOf(':');
      if (i <= 0) continue;
      var key = part.substring(0, i).trim().toUpperCase();
      key = switch (key) {
        'MANUFACTURER' => 'MFG',
        'MODEL' => 'MDL',
        'COMMAND SET' => 'CMD',
        'CLASS' => 'CLS',
        _ => key,
      };
      final value = part.substring(i + 1).trim();
      if (value.isNotEmpty) out[key] = value;
    }
    return out;
  }

  /// Tên dễ đọc "Hãng Model" (VD `4BARCODE 3B-300B`); rỗng khi không có.
  static String name(String id) {
    final m = parse(id);
    final mfg = m['MFG'] ?? '';
    final mdl = m['MDL'] ?? '';
    if (mdl.toLowerCase().startsWith(mfg.toLowerCase()) && mfg.isNotEmpty) {
      return mdl; // model đã có tên hãng ở đầu
    }
    return [mfg, mdl].where((e) => e.isNotEmpty).join(' ');
  }

  /// Chuỗi là của một MÁY IN (`CLS:PRINTER`, hoặc có `CMD:` lệnh máy in).
  static bool isPrinter(String id) {
    final m = parse(id);
    return (m['CLS'] ?? '').toUpperCase() == 'PRINTER' || m.containsKey('CMD');
  }
}
