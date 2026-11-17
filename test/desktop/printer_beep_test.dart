import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  test('bíp mặc định: máy tem dùng SOUND, máy hoá đơn dùng ESC B', () {
    expect(ascii.decode(PrinterBeep.bytes(label: true)), 'SOUND 5,200\r\n');
    expect(PrinterBeep.bytes(label: false).take(2), [0x1B, 0x42]);
  });

  test('các cách bíp: tem không có còi thì nhích tem (HOME), không in gì', () {
    expect(ascii.decode(PrinterBeep.style(BeepStyle.tsplHome)), 'HOME\r\n');
    expect(PrinterBeep.style(BeepStyle.escpos), [0x1B, 0x42, 0x03, 0x02]);
  });

  test(
    'thứ tự thử: đúng loại máy trước; máy chưa rõ loại thử lệnh nhị phân ESC/POS trước',
    () {
      expect(PrinterBeep.plan(label: true).first, BeepStyle.tsplSound);
      expect(PrinterBeep.plan(label: true), contains(BeepStyle.tsplHome));
      expect(PrinterBeep.plan(label: false).first, BeepStyle.escpos);
      // Máy hoá đơn không bị thử HOME (lệnh chữ không cần thiết).
      expect(
        PrinterBeep.plan(label: false),
        isNot(contains(BeepStyle.tsplHome)),
      );
      expect(PrinterBeep.plan().first, BeepStyle.escpos);
      expect(PrinterBeep.plan(), hasLength(3));
    },
  );
}
