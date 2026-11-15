/// Trạng thái giấy của máy in ESC/POS.
enum PaperStatus {
  ok,
  nearEnd,
  paperEnd,
  coverOpen,

  /// Máy không trả lời lệnh hỏi trạng thái (nhiều máy giá rẻ) — vẫn in bình thường.
  unknown;

  /// Không được gửi phiếu: máy vẫn nhận dữ liệu vào bộ nhớ rồi in khi thay giấy
  /// xong -> phiếu ra trễ, nhân viên in lại thì ra 2 phiếu.
  bool get blocksPrinting => this == paperEnd || this == coverOpen;

  /// Byte trả lời `DLE EOT n` hợp lệ: bit 1 và bit 4 = 1, bit 0 và bit 7 = 0.
  static bool isStatusByte(int b) => (b & 0x93) == 0x12;

  /// Suy trạng thái từ byte trả lời của `DLE EOT 4` ([roll]) và `DLE EOT 2`
  /// ([offline], có thể không có) — cùng quy tắc bản native Android.
  static PaperStatus parse({int? roll, int? offline}) {
    if (roll == null) return unknown;
    if (offline != null && (offline & 0x04) != 0) return coverOpen;
    if ((roll & 0x60) != 0 || (offline != null && (offline & 0x20) != 0)) {
      return paperEnd;
    }
    if ((roll & 0x0C) != 0) return nearEnd;
    return ok;
  }
}

/// Lỗi in do trạng thái máy in — mang mã lỗi giống app (`PRINTER_OUT_OF_PAPER`...).
class PrinterStatusException implements Exception {
  const PrinterStatusException(this.status);

  final PaperStatus status;

  String get code => switch (status) {
    PaperStatus.coverOpen => 'PRINTER_COVER_OPEN',
    _ => 'PRINTER_OUT_OF_PAPER',
  };

  @override
  String toString() => 'PrinterStatusException($code)';
}
