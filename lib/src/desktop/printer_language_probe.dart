import 'dart:convert';
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

  /// Hỏi TSPL TRƯỚC rồi mới hỏi ESC/POS (giống `PrinterCapabilities.kt`): firmware
  /// TSPL đọc lệnh theo dòng, ba byte `DLE EOT 4` còn trong bộ đệm làm câu `<ESC>!?`
  /// sau đó bị hiểu sai. Hỏi ĐỦ cả hai để nhận ra máy in HAI CHẾ ĐỘ (in được cả hoá đơn
  /// lẫn tem — VD PDIT) -> [PrinterLanguage.both].
  ///
  /// `ESC @` (đưa máy hoá đơn về kiểu chữ ban đầu — câu hỏi TSPL đổi kiểu chữ của nó)
  /// chỉ gửi cho máy CHỈ hiểu ESC/POS: byte lạ nằm lại bộ đệm của máy hiểu TSPL làm hỏng
  /// dòng lệnh đầu của lệnh tem kế tiếp.
  static Future<PrinterLanguage> probeLan(
    String host, {
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 700),
  }) async {
    final p = TcpPrinterPort(host, port: port);
    // Một kết nối cho cả hai câu hỏi (máy in LAN giá rẻ chỉ nhận một kết nối).
    final replies = await p.exchangeMany([
      _askTspl,
      _askEscPos,
    ], timeout: timeout);
    final tspl = classifyTspl(replies[0]);
    final escpos = classifyEscPos(replies[1]);
    if (escpos && !tspl) await p.send(_reset, checkStatus: false);
    return decide(escpos: escpos, tspl: tspl);
  }

  /// Số byte tối đa của một câu trả lời trạng thái hợp lệ.
  static const int _maxReplyBytes = 4;

  /// Trả lời `DLE EOT 4` hợp lệ: 1–4 byte và MỌI byte đều đúng khung trạng thái
  /// ESC/POS. Khung chặt loại được câu hỏi bị dội lại, chuỗi chữ, mẩu dữ liệu thừa.
  static bool classifyEscPos(Uint8List? reply) =>
      reply != null &&
      reply.isNotEmpty &&
      reply.length <= _maxReplyBytes &&
      reply.every(PaperStatus.isStatusByte);

  /// Mã trạng thái `<ESC>!?` của TSPL (bảng trạng thái của lệnh). Trước đây nhận mọi
  /// byte < 0x80 — lọt cả ký tự ASCII — nên "máy tem" không chứng minh được gì.
  /// Giữ khớp với `PrinterCapabilities.kt`.
  static const Set<int> _tsplStatus = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, //
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, //
    0x10, 0x20, 0x80,
  };

  /// Trả lời `ESC ! ?` hợp lệ: đúng MỘT mã trong bảng trạng thái TSPL — máy in hoá
  /// đơn không trả lời câu này.
  static bool classifyTspl(Uint8List? reply) =>
      reply != null && reply.length == 1 && _tsplStatus.contains(reply.first);

  /// Hãng chỉ làm máy in hoá đơn ESC/POS, không có máy in tem TSPL.
  static const Set<String> receiptOnlyVendors = {'Epson'};

  /// Tên model máy in HOÁ ĐƠN tự khai qua gói dò của hãng (VD module mạng Gprinter trả
  /// `DEVICENAME:GP 80 Printer` cho gói `B[]G`).
  ///
  /// Chỉ khớp tiền tố khổ giấy hoá đơn 58 / 80 (`GP 80 Printer`, `GP-58MB`,
  /// `GP-80250I`...): model máy tem Gprinter đều là 1124 / 1324 / 2120 / 3120 / 9025...
  /// Chặn nhầm một máy tem thật thì máy đó nhận ảnh ESC/POS và cũng in ra rác.
  static bool isReceiptModelName(String? model) =>
      model != null && _receiptModel.hasMatch(model);

  static final RegExp _receiptModel = RegExp(
    r'^\s*GP[\s\-_]?(58|80)',
    caseSensitive: false,
  );

  /// Kết luận từ thông tin dò mạng, không cần hỏi máy in: hãng chỉ làm máy hoá đơn
  /// ([receiptOnlyVendors]) hoặc model tự khai là máy hoá đơn ([isReceiptModelName])
  /// -> [PrinterLanguage.receipt]; còn lại [PrinterLanguage.unknown].
  static PrinterLanguage fromDiscovery({String? vendor, String? model}) =>
      (vendor != null && receiptOnlyVendors.contains(vendor)) ||
          isReceiptModelName(model)
      ? PrinterLanguage.receipt
      : PrinterLanguage.unknown;

  /// Tem thử CHỈ CÓ CHỮ (không có ảnh `BITMAP`) để người dùng xác nhận máy có phải
  /// máy tem không, khi máy không tự trả lời được.
  ///
  /// Máy tem in một tem có dòng [text]; máy hoá đơn in vài dòng ký tự lạ rồi dừng —
  /// không chạy hết cuộn vì không có dữ liệu nhị phân. Chỉ dùng ASCII (font có sẵn
  /// của TSPL không có tiếng Việt).
  static Uint8List textTestLabel({
    String text = 'LABEL OK',
    double widthMm = 40,
    double heightMm = 30,
  }) {
    String mm(double v) =>
        v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
    final safe = text
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
        .replaceAll('"', '');
    final lines = [
      'SIZE ${mm(widthMm)} mm,${mm(heightMm)} mm',
      'GAP 2 mm,0 mm',
      'DIRECTION 1',
      'CLS',
      'TEXT 16,16,"3",0,1,1,"$safe"',
      'PRINT 1,1',
    ];
    return Uint8List.fromList(ascii.encode('${lines.join('\r\n')}\r\n'));
  }

  /// Gửi [textTestLabel] tới máy in LAN. `false` nếu không kết nối / gửi được.
  static Future<bool> sendLanTestLabel(
    String host, {
    int port = 9100,
    String text = 'LABEL OK',
    double widthMm = 40,
    double heightMm = 30,
  }) async {
    try {
      await TcpPrinterPort(host, port: port).send(
        textTestLabel(text: text, widthMm: widthMm, heightMm: heightMm),
        checkStatus: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

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
