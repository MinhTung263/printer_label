import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

void main() {
  test('Xprinter self-test', () {
    final info = LanSelfTestInfo.parse('''
Ethernet Configuration
IP Address: 192.168.123.100
Subnet Mask: 255.255.255.0
Gateway: 192.168.123.1
MAC Address: 00:61:6D:1A:C1:13
DHCP: Disable
''')!;
    expect(info.ip, '192.168.123.100');
    expect(info.mask, '255.255.255.0');
    expect(info.gateway, '192.168.123.1');
    expect(info.mac, '00:61:6D:1A:C1:13');
    expect(info.dhcp, false);
  });

  test('OCR lỗi: O thay 0, dấu phẩy, nhãn và giá trị tách dòng', () {
    final info = LanSelfTestInfo.parse('''
IP Addr
192,168.1.1O0
Default Gateway : 192.168.1.1
DHCP  ON
''')!;
    expect(info.ip, '192.168.1.100');
    expect(info.gateway, '192.168.1.1');
    expect(info.dhcp, true);
  });

  test('Epson status sheet', () {
    final info = LanSelfTestInfo.parse('''
<TCP/IP>
Get IP Address     : Manual
IP Address         : 10.0.0.25
Subnet Mask        : 255.255.255.0
Default Gateway    : 10.0.0.1
''')!;
    expect(info.ip, '10.0.0.25');
    expect(info.gateway, '10.0.0.1');
  });

  test('Không có IP', () {
    expect(LanSelfTestInfo.parse('Printer OK\nFirmware 1.2'), isNull);
  });
}
