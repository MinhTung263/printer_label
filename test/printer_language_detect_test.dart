import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

void main() {
  group('phân loại câu trả lời trạng thái (khớp PrinterCapabilities.kt)', () {
    Uint8List b(List<int> v) => Uint8List.fromList(v);

    test('ESC/POS: mọi byte phải đúng khung, tối đa 4 byte', () {
      expect(PrinterLanguageProbe.classifyEscPos(b([0x12])), isTrue);
      expect(PrinterLanguageProbe.classifyEscPos(b([0x16, 0x12])), isTrue);
      // Lẫn một byte sai khung (VD câu hỏi bị dội lại) -> không tin.
      expect(PrinterLanguageProbe.classifyEscPos(b([0x12, 0x10])), isFalse);
      expect(PrinterLanguageProbe.classifyEscPos(b([0x10, 0x04, 0x04])), isFalse);
      expect(PrinterLanguageProbe.classifyEscPos(b([0x12, 0x12, 0x12, 0x12, 0x12])), isFalse);
      expect(PrinterLanguageProbe.classifyEscPos(b([])), isFalse);
    });

    test('TSPL: đúng một mã trong bảng trạng thái', () {
      for (final code in [0x00, 0x01, 0x05, 0x0D, 0x10, 0x20, 0x80]) {
        expect(PrinterLanguageProbe.classifyTspl(b([code])), isTrue, reason: '$code');
      }
      // Ký tự ASCII / mã ngoài bảng (trước đây lọt vì chỉ cần < 0x80).
      for (final code in [0x06, 0x41, 0x7E, 0x12, 0xFF]) {
        expect(PrinterLanguageProbe.classifyTspl(b([code])), isFalse, reason: '$code');
      }
    });
  });

  group('nhận biết qua thông tin dò mạng', () {
    test('model Gprinter khổ hoá đơn -> máy hoá đơn', () {
      for (final name in ['GP 80 Printer', 'GP-80250I', 'gp_58 printer', 'GP58MB', ' GP 80']) {
        expect(PrinterLanguageProbe.isReceiptModelName(name), isTrue, reason: name);
      }
    });

    test('model máy tem / không rõ -> không kết luận', () {
      for (final name in ['GP-1324D', 'GP-3120TL', 'GP-9025T', 'XP-365B', '', 'Printer']) {
        expect(PrinterLanguageProbe.isReceiptModelName(name), isFalse, reason: name);
      }
      expect(PrinterLanguageProbe.isReceiptModelName(null), isFalse);
    });

    test('fromDiscovery: hãng chỉ làm máy hoá đơn hoặc model hoá đơn', () {
      expect(PrinterLanguageProbe.fromDiscovery(vendor: 'Epson'), PrinterLanguage.receipt);
      expect(PrinterLanguageProbe.fromDiscovery(model: 'GP 80 Printer'), PrinterLanguage.receipt);
      expect(PrinterLanguageProbe.fromDiscovery(vendor: 'Xprinter'), PrinterLanguage.unknown);
      expect(PrinterLanguageProbe.fromDiscovery(vendor: 'Gprinter', model: 'GP-1324D'), PrinterLanguage.unknown);
      expect(PrinterLanguageProbe.fromDiscovery(), PrinterLanguage.unknown);
    });
  });

  group('tem thử chỉ có chữ', () {
    test('chỉ gồm lệnh TSPL dạng chữ ASCII, không có BITMAP', () {
      final bytes = PrinterLanguageProbe.textTestLabel(widthMm: 50, heightMm: 22.5);
      expect(bytes.every((x) => x == 0x0D || x == 0x0A || (x >= 0x20 && x < 0x7F)), isTrue);
      final text = ascii.decode(bytes);
      expect(text, contains('SIZE 50 mm,22.5 mm\r\n'));
      expect(text, contains('TEXT 16,16,"3",0,1,1,"LABEL OK"\r\n'));
      expect(text, endsWith('PRINT 1,1\r\n'));
      expect(text, isNot(contains('BITMAP')));
    });

    test('bỏ ký tự ngoài ASCII và dấu nháy khỏi nội dung', () {
      final text = ascii.decode(PrinterLanguageProbe.textTestLabel(text: 'Tem "thử" OK'));
      expect(text, contains('"Tem th OK"'));
    });
  });
}
