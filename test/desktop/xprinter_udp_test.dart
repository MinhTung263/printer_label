import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

List<int> _reply({
  String mac = '001aefcb2cb0',
  List<int> ip = const [192, 168, 1, 100],
  bool dhcp = false,
}) {
  final b = List<int>.filled(34, 0);
  b.setRange(0, 11, ascii.encode('XP0001FOUND'));
  for (var i = 0; i < 6; i++) {
    b[11 + i] = int.parse(mac.substring(i * 2, i * 2 + 2), radix: 16);
  }
  b.setRange(19, 23, ip);
  b.setRange(23, 27, const [255, 255, 255, 0]);
  b.setRange(27, 31, const [192, 168, 1, 1]);
  b[33] = dhcp ? 1 : 0;
  return b;
}

void main() {
  test('đọc gói trả lời XP0001FOUND (khớp gói máy in thật)', () {
    final f = XprinterUdp.parseReply(_reply())!;
    expect(f.mac, '00:1A:EF:CB:2C:B0');
    expect(f.ip, '192.168.1.100');
    expect(f.mask, '255.255.255.0');
    expect(f.gateway, '192.168.1.1');
    expect(f.dhcp, isFalse);
    expect(XprinterUdp.parseReply(_reply(dhcp: true))!.dhcp, isTrue);
  });

  test('gói lạ / ngắn / IP 0.0.0.0 bị bỏ qua', () {
    expect(XprinterUdp.parseReply(ascii.encode('XP0001FIND')), isNull);
    expect(XprinterUdp.parseReply(List.filled(34, 1)), isNull);
    expect(XprinterUdp.parseReply(_reply(ip: [0, 0, 0, 0])), isNull);
  });

  test('gói cấu hình mạng XP0001SAVE đúng bố cục 34 byte', () {
    final p = XprinterUdp.savePacket(
      mac: '00:1A:EF:CB:2C:B0',
      ip: '192.168.1.150',
      mask: '255.255.255.0',
      gateway: '192.168.1.1',
      dhcp: false,
    );
    expect(p.length, 34);
    expect(ascii.decode(p.sublist(0, 10)), 'XP0001SAVE');
    expect(p.sublist(10, 16), [0x00, 0x1A, 0xEF, 0xCB, 0x2C, 0xB0]);
    expect(p.sublist(16, 18), [0x22, 0x00]);
    expect(p.sublist(18, 22), [192, 168, 1, 150]);
    expect(p.sublist(22, 26), [255, 255, 255, 0]);
    expect(p.sublist(26, 30), [192, 168, 1, 1]);
    expect(p.sublist(30, 32), [0x8C, 0x23]);
    expect(p[32], 0);
    expect(
      () => XprinterUdp.savePacket(mac: '00:1A', ip: '1.2.3.4'),
      throwsArgumentError,
    );
  });

  group('ghép kết quả dò UDP với quét cổng 9100', () {
    const printer = XprinterUdpFound(
      mac: '00:1A:EF:CB:2C:B0',
      ip: '192.168.1.100',
    );

    test(
      'IP bị thiết bị khác dùng (ARP khác MAC máy in) → ipConflict',
      () async {
        final r = await LanPrinterScanner.mergeUdp(
          [const LanPrinterFound('192.168.1.100', 9100)],
          [printer],
          arpMacOf: (_) async => '56:23:38:9F:DA:CD',
        );
        expect(r.single.issue, LanPrinterIssue.ipConflict);
        expect(r.single.mac, '00:1A:EF:CB:2C:B0');
      },
    );

    test('ARP khớp + cổng in mở → bình thường, gắn MAC', () async {
      final r = await LanPrinterScanner.mergeUdp(
        [const LanPrinterFound('192.168.1.100', 9100)],
        [printer],
        arpMacOf: (_) async => '00:1a:ef:cb:2c:b0',
      );
      expect(r.single.issue, LanPrinterIssue.none);
    });

    test(
      'chỉ thấy qua UDP, quét chậm mở được cổng → thêm vào, không lỗi',
      () async {
        final r = await LanPrinterScanner.mergeUdp(
          const [],
          [printer],
          probeSlow: (_) async => true,
          arpMacOf: (_) async => '00:1A:EF:CB:2C:B0',
        );
        expect(r.single.host, '192.168.1.100');
        expect(r.single.issue, LanPrinterIssue.none);
      },
    );

    test('chỉ thấy qua UDP, không mở được cổng in → unreachable', () async {
      final r = await LanPrinterScanner.mergeUdp(
        const [],
        [printer],
        probeSlow: (_) async => false,
        arpMacOf: (_) async => null,
      );
      expect(r.single.issue, LanPrinterIssue.unreachable);
    });
  });
}
