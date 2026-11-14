import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

void main() {
  test('Mã QR Wi-Fi chuẩn', () {
    final w = WifiQrInfo.parse('WIFI:T:WPA;S:sds mobile;P:abc12345;H:false;;')!;
    expect(w.ssid, 'sds mobile');
    expect(w.password, 'abc12345');
    expect(w.security, 'WPA');
  });
  test('Ký tự thoát và thứ tự khác', () {
    final w = WifiQrInfo.parse(r'WIFI:S:Quan\;Cafe;T:WPA;P:p\:a\;ss\\1;;')!;
    expect(w.ssid, 'Quan;Cafe');
    expect(w.password, r'p:a;ss\1');
  });
  test('Wi-Fi không mật khẩu', () {
    final w = WifiQrInfo.parse('WIFI:T:nopass;S:Guest;;')!;
    expect(w.ssid, 'Guest');
    expect(w.password, '');
  });
  test('Không phải mã Wi-Fi', () {
    expect(WifiQrInfo.parse('https://easypos.vn'), isNull);
    expect(WifiQrInfo.parse('WIFI:T:WPA;P:x;;'), isNull);
  });
}
