import 'dart:typed_data';

import 'paper_status.dart';
import 'tcp_printer_port.dart';

/// Máy in nói ngôn ngữ nào.
enum PrinterLanguage {
  /// Chỉ trả lời lệnh ESC/POS — máy in hoá đơn.
  receipt,

  /// Chỉ trả lời lệnh TSPL — máy in tem.
  label,

  /// Trả lời cả hai (máy in hai chế độ): người dùng chọn.
  both,

  /// Không trả lời lệnh nào (máy tắt, khác mạng, hoặc không hỗ trợ hỏi trạng thái).
  unknown,
}

/// Dò máy in LAN là máy in hoá đơn (ESC/POS) hay máy in tem (TSPL) bằng hai câu hỏi
/// trạng thái:
///
/// - ESC/POS: `DLE EOT 4` → byte trạng thái dạng `0b0xx1xx10`.
/// - TSPL: `ESC ! ?` → máy in tem trả MỘT byte trạng thái (0x00 sẵn sàng, 0x01 mở nắp...).
///
/// Máy in hoá đơn không hiểu `ESC ! ?` (nó đổi kiểu chữ rồi im lặng) nên sau câu hỏi
/// gửi `ESC @` để đưa về trạng thái ban đầu.
abstract final class PrinterLanguageProbe {
  static final Uint8List _askEscPos = Uint8List.fromList([0x10, 0x04, 0x04]);
  static final Uint8List _askTspl = Uint8List.fromList([0x1B, 0x21, 0x3F]);
  static final Uint8List _reset = Uint8List.fromList([0x1B, 0x40]);

  static Future<PrinterLanguage> probeLan(
    String host, {
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 700),
  }) async {
    final p = TcpPrinterPort(host, port: port);
    final escpos = classifyEscPos(
      await p.exchange(_askEscPos, timeout: timeout),
    );
    final tspl = classifyTspl(await p.exchange(_askTspl, timeout: timeout));
    // Đưa máy in hoá đơn về lại kiểu chữ ban đầu (câu hỏi TSPL đổi kiểu chữ của nó).
    await p.send(_reset, checkStatus: false);
    return decide(escpos: escpos, tspl: tspl);
  }

  /// Trả lời `DLE EOT 4` hợp lệ: có byte trạng thái ESC/POS.
  static bool classifyEscPos(Uint8List? reply) =>
      reply != null && reply.any(PaperStatus.isStatusByte);

  /// Trả lời `ESC ! ?` hợp lệ: đúng MỘT byte trạng thái (< 0x80 và không phải khung
  /// trạng thái ESC/POS) — máy in hoá đơn không trả lời câu này.
  static bool classifyTspl(Uint8List? reply) =>
      reply != null && reply.length == 1 && reply.first < 0x80;

  /// Tên model có vẻ là máy in TEM (nhãn / mã vạch) — dùng khi hai câu hỏi trạng thái
  /// không đủ kết luận (máy không trả lời, hoặc trả lời cả hai kiểu).
  static bool looksLikeLabelModel(String? model) {
    final m = (model ?? '').toLowerCase();
    if (m.isEmpty) return false;
    return _labelModel.hasMatch(m);
  }

  static final RegExp _labelModel = RegExp(
    r'label|barcode|tem\b|tspl|tsc\b|ttp-?\d|tdp-?\d|zebra|argox|'
    r'xp-?(3[0-9]{2}|4[0-9]{2})b?\b|xp-?(dt|h)\d|gk-?\d{3}|'
    r'gp-?(1124|1134|1324|1524|2120|3120|3150)|ht-?(300|330)|dl-?(8|7)\d{2}',
  );

  /// Đọc ngôn ngữ máy in từ chuỗi định danh IEEE 1284 máy USB tự báo
  /// (`MFG:..;CMD:TSPL2;MDL:..;CLS:PRINTER;`): `CMD:` liệt kê các lệnh máy hiểu. TSPL / ZPL /
  /// EPL / CPCL / DPL → máy tem; ESC/POS → máy hoá đơn; có cả hai → [PrinterLanguage.both].
  /// `null` khi chuỗi không có `CMD:`.
  static PrinterLanguage? fromIeee1284(String deviceId) {
    final cmds = ieeeCommands(deviceId);
    if (cmds == null) return null;
    final label = cmds.any(
      (t) => RegExp(
        r'^(TSPL|ZPL|EPL|EZPL|CPCL|DPL|TSC|BPLA|BPLB|SBPL|ZJ)',
      ).hasMatch(t),
    );
    final receipt = cmds.any(
      (t) => RegExp(r'^(ESC/?POS|EPSON|STAR)').hasMatch(t),
    );
    return decide(escpos: receipt, tspl: label);
  }

  /// Các lệnh máy in tự báo trong `CMD:` / `COMMAND SET:` của chuỗi IEEE 1284, viết hoa, bỏ khoảng trắng
  /// và gạch dưới (`ESC POS` / `ESC_POS` → `ESCPOS`); `null` khi chuỗi không có `CMD:`.
  ///
  /// Mỗi hãng viết một kiểu (`ESC/POS`, `ESCPOS`, `ESC POS`, `EPSON`, `TSPL2`, `ZPL II`...) nên so khớp theo
  /// ĐẦU từng lệnh sau khi chuẩn hoá — khớp chuỗi con làm `POSTSCRIPT` (chứa "TSC") bị nhận nhầm là máy tem.
  static List<String>? ieeeCommands(String deviceId) {
    final m = RegExp(
      r'(?:^|;)\s*(?:CMD|COMMAND SET):([^;]*)',
      caseSensitive: false,
    ).firstMatch(deviceId);
    if (m == null) return null;
    return [
      for (final t in m.group(1)!.split(RegExp(r'[,;]')))
        if (t.trim().isNotEmpty)
          t.toUpperCase().replaceAll(RegExp(r'[\s_]+'), ''),
    ];
  }

  static PrinterLanguage decide({required bool escpos, required bool tspl}) =>
      switch ((escpos, tspl)) {
        (true, true) => PrinterLanguage.both,
        (true, false) => PrinterLanguage.receipt,
        (false, true) => PrinterLanguage.label,
        _ => PrinterLanguage.unknown,
      };
}
