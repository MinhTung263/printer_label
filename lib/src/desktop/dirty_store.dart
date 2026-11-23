import 'dart:convert';
import 'dart:io';

/// Sổ "máy in này có thể đang dở một lệnh ảnh", LƯU BỀN xuống đĩa (tệp JSON nhỏ).
///
/// Ảnh hoá đơn đi bằng lệnh raster `GS v 0` khai báo trước số byte. Lần gửi trước đứt giữa chừng (rút dây, mất Wi-Fi,
/// Agent bị tắt / crash / mất điện) thì máy in vẫn chờ nốt phần ảnh còn thiếu và NUỐT phiếu kế tiếp làm dữ liệu ảnh -> ký
/// tự lạ, giấy chạy dài. Trước đây cờ chỉ nằm trong bộ nhớ nên Agent khởi động lại là mất.
///
/// Ghi sổ TRƯỚC byte đầu của lệnh in; chỉ xoá khi lệnh đã gửi xong. Khoá = `tcp://host:port` của máy in.
/// Mặc định lưu trong thư mục tạm; app Agent nên trỏ [path] vào thư mục dữ liệu riêng của mình.
class DirtyStore {
  DirtyStore({String? path}) : _path = path;

  String? _path;
  Set<String>? _keys;

  /// Đường dẫn tệp sổ (đổi được để lưu ở thư mục dữ liệu của app).
  String get path =>
      _path ??
      '${Directory.systemTemp.path}${Platform.pathSeparator}printer_label_dirty.json';

  set path(String value) {
    _path = value;
    _keys = null; // nạp lại từ tệp mới
  }

  Set<String> _load() {
    final cached = _keys;
    if (cached != null) return cached;
    var loaded = <String>{};
    try {
      final file = File(path);
      if (file.existsSync()) {
        final raw = jsonDecode(file.readAsStringSync());
        if (raw is List) loaded = raw.whereType<String>().toSet();
      }
    } catch (_) {
      // Tệp hỏng / không đọc được: coi như sạch (lần gửi sau vẫn xả vì lệnh ESC/POS luôn xả).
    }
    return _keys = loaded;
  }

  void _save(Set<String> keys) {
    try {
      File(path).writeAsStringSync(jsonEncode(keys.toList()), flush: true);
    } catch (_) {
      // Không ghi được (đĩa chỉ đọc...): bỏ qua, vẫn còn cờ trong bộ nhớ.
    }
  }

  bool isDirty(String id) => _load().contains(id);

  /// Đánh dấu và ghi đĩa NGAY: tiến trình bị kill ngay sau đó vẫn còn cờ.
  void mark(String id) {
    final keys = _load();
    if (keys.add(id)) _save(keys);
  }

  /// Bỏ đánh dấu. Mất lần ghi này chỉ gây thêm một lần xả thừa, vô hại.
  void clear(String id) {
    final keys = _load();
    if (keys.remove(id)) _save(keys);
  }
}
