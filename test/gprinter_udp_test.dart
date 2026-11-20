import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

void main() {
  const mac = [0x00, 0x47, 0x50, 0x25, 0xCC, 0xBC];
  String text(List<int> b) => String.fromCharCodes(b.map((e) => e));

  test('gói dò là B[]G', () {
    expect(GprinterUdp.searchPacket, [0x42, 0x5B, 0x5D, 0x47]);
  });

  test('macBytes đọc MAC có hoặc không dấu', () {
    expect(GprinterUdp.macBytes('00:47:50:25:CC:BC'), mac);
    expect(GprinterUdp.macBytes('00-47-50-25-cc-bc'), mac);
    expect(GprinterUdp.macBytes('004750 25CCBC'), mac);
    expect(GprinterUdp.macBytes('xyz'), isNull);
  });

  test('gói đặt IP: B[ + MAC + ] + YJKE02GPRINTERGPI + IP', () {
    final p = GprinterUdp.ipPacket(mac, '192.168.1.50');
    expect(p.sublist(0, 2), [0x42, 0x5B]);
    expect(p.sublist(2, 8), mac);
    expect(p[8], 0x5D);
    expect(text(p.sublist(9)), 'YJKE02GPRINTERGPI192.168.1.50');
  });

  test('gói netmask / gateway / DHCP / reboot', () {
    expect(
      text(GprinterUdp.maskPacket(mac, '255.255.255.0').sublist(9)),
      'YJKE02GPRINTERGPS255.255.255.0',
    );
    expect(
      text(GprinterUdp.gatewayPacket(mac, '192.168.1.1').sublist(9)),
      'YJKE02GPRINTERGPW192.168.1.1',
    );
    expect(
      text(GprinterUdp.dhcpPacket(mac, dhcp: true).sublist(9)),
      'YJKE02GPRINTERGPD1',
    );
    expect(
      text(GprinterUdp.dhcpPacket(mac, dhcp: false).sublist(9)),
      'YJKE02GPRINTERGPD0',
    );
    final r = GprinterUdp.rebootPacket(mac);
    expect(r.length, 15);
    expect(text(r.sublist(9)), 'EJKE02');
  });

  test('parseResponse tách KEY:VALUE;', () {
    final m = GprinterUdp.parseResponse(
      ascii.encode('ID:1;MAC:004750 25CCBC;IP:192.168.50.85;DHCP:Disable;'),
    );
    expect(m['IP'], '192.168.50.85');
    expect(m['DHCP'], 'Disable');
  });

  test('parseDevice đọc đủ thông tin máy', () {
    final info = GprinterUdp.parseDevice(
      ascii.encode(
        'ID:GP;DEVICENAME:GP-80;VER:2.0A;MFC:GP;SN:123;'
        'MAC:00475025CCBC;DHCP:Disable;DTIMEOUT:5;IP:192.168.50.85;'
        'SUBNETWORK:255.255.255.0;GATEWAY:192.168.50.1;PRNPORT:9100;',
      ),
    );
    expect(info, isNotNull);
    expect(info!.mac, '00:47:50:25:CC:BC');
    expect(info.ip, '192.168.50.85');
    expect(info.mask, '255.255.255.0');
    expect(info.gateway, '192.168.50.1');
    expect(info.dhcp, isFalse);
    expect(info.name, 'GP-80');
  });

  test('DHCP Enable → dhcp true', () {
    final info = GprinterUdp.parseDevice(
      ascii.encode('MAC:00475025CCBC;IP:10.0.0.5;DHCP:Enable;'),
    );
    expect(info!.dhcp, isTrue);
  });

  test('gói dội lại / không phải máy in bị loại', () {
    expect(GprinterUdp.parseDevice(ascii.encode('B[]G')), isNull);
    expect(GprinterUdp.parseDevice(ascii.encode('HELLO')), isNull);
    expect(GprinterUdp.parseDevice(ascii.encode('MAC:zz;IP:1.2.3.4;')), isNull);
    expect(
      GprinterUdp.parseDevice(ascii.encode('MAC:00475025CCBC;IP:abc;')),
      isNull,
    );
  });
}
