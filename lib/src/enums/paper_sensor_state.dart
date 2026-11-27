/// Trạng thái giấy máy in tự báo (lệnh ESC/POS `DLE EOT 4`, hỏi ngay trước mỗi lần in).
enum PaperSensorState {
  /// Còn giấy (máy có cảm biến gần hết thì nghĩa là chưa gần hết).
  ok,

  /// Cảm biến GẦN HẾT GIẤY báo — chỉ máy có cảm biến này mới báo được.
  nearEnd,

  /// Hết giấy.
  paperEnd,

  /// Đang mở nắp.
  coverOpen,

  /// Máy không trả lời lệnh hỏi trạng thái.
  unknown;

  static PaperSensorState? parse(String? raw) => switch (raw) {
    'OK' => ok,
    'NEAR_END' => nearEnd,
    'PAPER_END' => paperEnd,
    'COVER_OPEN' => coverOpen,
    'UNKNOWN' => unknown,
    _ => null,
  };
}
