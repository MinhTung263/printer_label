import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  test('quét hẹp: chỉ dải /24 của máy, bỏ IP của chính máy', () async {
    final t = await LanPrinterScanner.scanTargets([
      '192.168.1.20',
    ], wide: false);
    expect(t.length, 253);
    expect(t, contains('192.168.1.1'));
    expect(t, isNot(contains('192.168.1.20')));
    expect(t, isNot(contains('192.168.0.5')));
  });

  test('quét rộng: cả khối 4 dải /24 liền nhau (phủ mạng /23, /22)', () async {
    final t = await LanPrinterScanner.scanTargets(['192.168.1.20']);
    expect(t, contains('192.168.0.5'));
    expect(t, contains('192.168.2.100'));
    expect(t, contains('192.168.3.254'));
    expect(t, isNot(contains('192.168.4.1')));
    expect(t.length, 4 * 254 - 1);
    // Máy ở dải .5 thì khối là 4..7.
    final u = await LanPrinterScanner.scanTargets(['10.0.5.9']);
    expect(u, contains('10.0.4.1'));
    expect(u, contains('10.0.7.1'));
    expect(u, isNot(contains('10.0.3.1')));
  });

  test('quét rộng thêm máy trong bảng ARP ngoài các dải, không lặp', () async {
    final t = await LanPrinterScanner.scanTargets(
      ['192.168.1.20'],
      arp: ['172.16.9.9', '192.168.2.7', '192.168.1.20'],
    );
    expect(t.where((h) => h == '172.16.9.9'), hasLength(1));
    expect(t.where((h) => h == '192.168.2.7'), hasLength(1));
    expect(t, isNot(contains('192.168.1.20')));
  });

  test('hai card mạng: gộp các khối, giới hạn số máy tối đa', () async {
    final t = await LanPrinterScanner.scanTargets([
      '192.168.1.20',
      '10.1.1.2',
      '172.16.1.2',
    ]);
    expect(t.length, lessThanOrEqualTo(LanPrinterScanner.maxHosts));
    expect(t, contains('10.1.0.9'));
  });
}
