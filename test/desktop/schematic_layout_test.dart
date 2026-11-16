import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

void main() {
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
