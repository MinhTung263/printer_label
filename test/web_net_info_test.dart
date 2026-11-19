import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

// Trang /port_stat.htm thật của HPRT (rút gọn).
String page(String mac, String ip, String dhcp) =>
    '''
<TR><TH>Interface Status</TH></TR>
<TR><TD>Mac&nbsp;Address</TD><TD class=num>$mac</TD></TR>
<TR><TD>IP&nbsp;Address</TD><TD class=num>$ip</TD></TR>
<TR><TD>Subnet&nbsp;Mask</TD><TD class=num>255.255.255.0</TD></TR>
<TR><TD>Gate&nbsp;Way</TD><TD class=num>192.168.50.1</TD></TR>
<TR><TD>DHCP</TD><TD class=num>$dhcp</TD></TR>
<TR><TD>DHCP Timeout</TD><TD class=num>30</TD></TR>
''';

void main() {
  test('HPRT tắt DHCP: MAC thập phân → hex, nhận ra IP tĩnh', () {
    final i = PrinterLabel.parseWebNetInfo(
      page('0-71-80-61-180-164', '192.168.50.200', 'Disabled'),
    )!;
    expect(i.mac, '00:47:50:3D:B4:A4');
    expect(i.ip, '192.168.50.200');
    expect(i.mask, '255.255.255.0');
    expect(i.gateway, '192.168.50.1');
    expect(i.dhcp, isFalse);
  });

  test('HPRT bật DHCP', () {
    final i = PrinterLabel.parseWebNetInfo(
      page('0-71-80-37-204-188', '192.168.50.75', 'Enabled'),
    )!;
    expect(i.mac, '00:47:50:25:CC:BC');
    expect(i.dhcp, isTrue);
  });

  test('MAC dạng hex có dấu gạch / hai chấm cũng đọc được', () {
    expect(
      PrinterLabel.parseWebNetInfo(
        page('00-47-50-3D-B4-A4', '10.0.0.5', 'Enabled'),
      )!.mac,
      '00:47:50:3D:B4:A4',
    );
    expect(
      PrinterLabel.parseWebNetInfo(
        page('00:47:50:3d:b4:a4', '10.0.0.5', 'Enabled'),
      )!.mac,
      '00:47:50:3D:B4:A4',
    );
  });

  test('trang lạ / thiếu MAC hoặc IP → null', () {
    expect(
      PrinterLabel.parseWebNetInfo('<html>404 - file not found</html>'),
      isNull,
    );
    expect(
      PrinterLabel.parseWebNetInfo(page('0-0-0-0-0-0', '10.0.0.5', 'Enabled')),
      isNull,
    );
    expect(
      PrinterLabel.parseWebNetInfo(
        page('0-71-80-61-180-164', 'abc', 'Enabled'),
      ),
      isNull,
    );
  });
}
