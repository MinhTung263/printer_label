import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';
import 'package:printer_label/desktop.dart' show TsplLabelSpec;

void main() {
  _jewelryTests();
  test(
    'bố cục tỉ lệ: hình xem trước và ảnh in cùng một bố cục (chỉ khác tỉ lệ kích thước)',
    () {
      // Tem 35×22mm: ảnh in 280×176 chấm, hình xem trước 125×78.6 điểm ảnh.
      final print = SchematicTemLayout.of(280, 176);
      final screen = SchematicTemLayout.of(125, 125 * 176 / 280);
      final k = 280 / 125;
      void same(Box a, Box b) {
        expect(a.left, closeTo(b.left * k, 0.01));
        expect(a.top, closeTo(b.top * k, 0.01));
        expect(a.right, closeTo(b.right * k, 0.01));
        expect(a.bottom, closeTo(b.bottom * k, 0.01));
      }

      same(print.frame, screen.frame);
      same(print.bar1, screen.bar1);
      same(print.bar2, screen.bar2);
      same(print.code, screen.code);
      // Cùng số vạch mã vạch ở mọi kích thước.
      expect(print.bars.length, screen.bars.length);
    },
  );

  test('mọi thành phần nằm trong khung, khung thụt vào khỏi mép tem', () {
    final l = SchematicTemLayout.of(280, 176);
    expect(l.frame.left, greaterThan(0));
    expect(l.frame.top, greaterThan(0));
    expect(l.frame.right, lessThan(280));
    expect(l.frame.bottom, lessThan(176));
    for (final b in [l.bar1, l.bar2, l.code]) {
      expect(b.left, greaterThan(l.frame.left));
      expect(b.top, greaterThan(l.frame.top));
      expect(b.right, lessThan(l.frame.right));
      expect(b.bottom, lessThan(l.frame.bottom));
    }
  });
}

void _jewelryTests() {
  test(
    'tem vàng bạc: chữ bên trái, mã QR vuông bên phải, mọi thứ trong khung',
    () {
      final l = SchematicTemLayout.of(400, 96, jewelry: true);
      expect(l.jewelry, isTrue);
      expect(l.price, isNotNull);
      expect(l.code.width, closeTo(l.code.height, 0.01), reason: 'QR vuông');
      expect(l.code.left, greaterThan(l.bar1.right), reason: 'QR không đè chữ');
      expect(l.bars, isEmpty);
      expect(l.qrCells, isNotEmpty);
      for (final b in [l.bar1, l.bar2, l.price!, l.code, ...l.qrCells]) {
        expect(b.left, greaterThanOrEqualTo(l.frame.left));
        expect(b.top, greaterThanOrEqualTo(l.frame.top));
        expect(b.right, lessThanOrEqualTo(l.frame.right + 0.001));
        expect(b.bottom, lessThanOrEqualTo(l.frame.bottom + 0.001));
      }
    },
  );

  test(
    'tem vàng bạc: hình xem trước và ảnh in cùng bố cục (chỉ khác tỉ lệ)',
    () {
      final print = SchematicTemLayout.of(400, 96, jewelry: true);
      final screen = SchematicTemLayout.of(125, 30, jewelry: true);
      const k = 400 / 125;
      expect(print.code.left, closeTo(screen.code.left * k, 0.01));
      expect(print.price!.right, closeTo(screen.price!.right * k, 0.01));
      expect(print.qrCells.length, screen.qrCells.length);
    },
  );

  test('tem thường không đổi: không có thanh giá / ô QR', () {
    final l = SchematicTemLayout.of(280, 176);
    expect(l.jewelry, isFalse);
    expect(l.price, isNull);
    expect(l.qrCells, isEmpty);
    expect(l.bars, isNotEmpty);
  });

  test('TsplLabelSpec.isJewelry: 300dpi hoặc ruy-băng', () {
    const base = TsplLabelSpec(widthMm: 50, heightMm: 12);
    expect(base.isJewelry, isFalse);
    expect(base.copyWith(dpi: 300).isJewelry, isTrue);
    expect(base.copyWith(ribbon: true).isJewelry, isTrue);
    expect(base.copyWith(ribbon: false).isJewelry, isFalse);
  });
}
