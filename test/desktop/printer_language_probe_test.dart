import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

/// Máy in giả: trả lời `DLE EOT 4` / `ESC ! ?` theo [escpos] / [tspl].
Future<ServerSocket> _fake({required bool escpos, required bool tspl}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((s) {
    s.listen((data) {
      final d = data.toList();
      if (escpos &&
          d.length >= 3 &&
          d[0] == 0x10 &&
          d[1] == 0x04 &&
          d[2] == 0x04) {
        s.add([0x12]); // trạng thái ESC/POS bình thường
      }
      if (tspl &&
          d.length >= 3 &&
          d[0] == 0x1B &&
          d[1] == 0x21 &&
          d[2] == 0x3F) {
        s.add([0x00]); // TSPL sẵn sàng
      }
    }, onDone: s.destroy);
  });
  return server;
}

void main() {
  Future<PrinterLanguage> probe({
    required bool escpos,
    required bool tspl,
  }) async {
    final server = await _fake(escpos: escpos, tspl: tspl);
    try {
      return await PrinterLanguageProbe.probeLan(
        '127.0.0.1',
        port: server.port,
        timeout: const Duration(milliseconds: 300),
      );
    } finally {
      await server.close();
    }
  }

  test('máy in hoá đơn (chỉ ESC/POS) → receipt', () async {
    expect(await probe(escpos: true, tspl: false), PrinterLanguage.receipt);
  });

  test('máy in tem (chỉ TSPL) → label', () async {
    expect(await probe(escpos: false, tspl: true), PrinterLanguage.label);
  });

  test('máy in hai chế độ → both', () async {
    expect(await probe(escpos: true, tspl: true), PrinterLanguage.both);
  });

  test('không trả lời gì → unknown', () async {
    expect(await probe(escpos: false, tspl: false), PrinterLanguage.unknown);
  });

  test('máy không kết nối được → ném lỗi kết nối (nơi gọi bắt)', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    await expectLater(
      PrinterLanguageProbe.probeLan(
        '127.0.0.1',
        port: port,
        timeout: const Duration(milliseconds: 100),
      ),
      throwsA(isA<SocketException>()),
    );
  });

  test('phân loại byte trả lời', () {
    expect(
      PrinterLanguageProbe.classifyEscPos(Uint8List.fromList([0x12])),
      isTrue,
    );
    expect(
      PrinterLanguageProbe.classifyEscPos(Uint8List.fromList([0x00])),
      isFalse,
    );
    expect(PrinterLanguageProbe.classifyEscPos(null), isFalse);
    expect(
      PrinterLanguageProbe.classifyTspl(Uint8List.fromList([0x00])),
      isTrue,
    );
    expect(
      PrinterLanguageProbe.classifyTspl(Uint8List.fromList([0x00, 0x01])),
      isFalse,
    );
    expect(
      PrinterLanguageProbe.classifyTspl(Uint8List.fromList([0xFF])),
      isFalse,
    );
  });

  test('tên model giống máy in tem (nhãn / mã vạch)', () {
    for (final m in [
      'Xprinter XP-420B',
      'XP-365B',
      'TSC TTP-244',
      'Zebra ZD220',
      'Gprinter GP-1324D',
      'HPRT HT300',
      'Label Printer',
      'Barcode printer',
    ]) {
      expect(PrinterLanguageProbe.looksLikeLabelModel(m), isTrue, reason: m);
    }
    for (final m in [
      'XP-80C',
      'XP-58IIH',
      'Epson TM-T82',
      'POS-80',
      null,
      '',
    ]) {
      expect(
        PrinterLanguageProbe.looksLikeLabelModel(m),
        isFalse,
        reason: '$m',
      );
    }
  });
}
