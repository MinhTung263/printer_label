/// Trạng thái giấy của máy in ESC/POS.
enum PaperStatus {
  ok,
  nearEnd,
  paperEnd,
  coverOpen,

  /// Máy tem (TSPL): kẹt giấy / sai khổ khe tem.
  jam,

  /// Máy tem in truyền nhiệt (ruy-băng mực): hết cuộn mực.
  ribbonEnd,

  /// Máy không trả lời lệnh hỏi trạng thái (nhiều máy giá rẻ) — vẫn in bình thường.
  unknown;

  /// Không được gửi phiếu: máy vẫn nhận dữ liệu vào bộ nhớ rồi in khi thay giấy
  /// xong -> phiếu ra trễ, nhân viên in lại thì ra 2 phiếu.
  bool get blocksPrinting =>
      this == paperEnd || this == coverOpen || this == jam || this == ribbonEnd;

  /// Byte trả lời `DLE EOT n` hợp lệ: bit 1 và bit 4 = 1, bit 0 và bit 7 = 0.
  static bool isStatusByte(int b) => (b & 0x93) == 0x12;

  /// Byte trả lời `<ESC>!?` của máy tem TSPL: các bit trạng thái nằm trong 6 bit thấp (0x00–0x3F).
  /// Chữ cái / byte khác là máy không hiểu lệnh này.
  static bool isTsplStatusByte(int b) => b >= 0 && b <= 0x3F;

  /// Suy trạng thái từ byte `<ESC>!?` (TSPL): `0x01` mở nắp, `0x02` kẹt giấy, `0x04` hết giấy,
  /// `0x08` hết ruy-băng, `0x10` tạm dừng, `0x20` đang in. Đang in / tạm dừng vẫn nhận lệnh
  /// (máy tự xếp hàng) nên không chặn.
  static PaperStatus parseTspl(int b) {
    if (!isTsplStatusByte(b)) return unknown;
    if ((b & 0x01) != 0) return coverOpen;
    if ((b & 0x04) != 0) return paperEnd;
    if ((b & 0x08) != 0) return ribbonEnd;
    if ((b & 0x02) != 0) return jam;
    return ok;
  }

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
