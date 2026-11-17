import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  _orderTests();
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

void _orderTests() {
  test(
    'thứ tự dò: máy trong bảng ARP trước, rồi cùng dải /24 của máy, rồi dải còn lại',
    () async {
      final t = await LanPrinterScanner.scanTargets(
        ['192.168.1.20'],
        arp: ['192.168.3.9', '192.168.1.77'],
      );
      expect(t.take(2), containsAll(['192.168.3.9', '192.168.1.77']));
      // Sau nhóm ARP: toàn bộ dải 192.168.1.x đứng trước dải khác.
      final firstOther = t.indexWhere(
        (h) => !h.startsWith('192.168.1.') && !{'192.168.3.9'}.contains(h),
      );
      final lastOwn = t.lastIndexWhere((h) => h.startsWith('192.168.1.'));
      expect(lastOwn, lessThan(firstOther));
      expect(t.toSet().length, t.length, reason: 'không lặp');
    },
  );

  test('quét báo máy in tới đâu gọi onFound tới đó', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((c) => c.destroy());
    final seen = <String>[];
    final r = await LanPrinterScanner.scan(
      port: server.port,
      wide: false,
      timeout: const Duration(milliseconds: 150),
      onFound: (f) => seen.add(f.host),
    );
    await server.close();
    expect(seen.toSet(), r.map((f) => f.host).toSet());
  });
}
