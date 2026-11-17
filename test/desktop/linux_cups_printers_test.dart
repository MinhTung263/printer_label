import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  const out = '''
device for Xprinter_XP-80C: usb://Xprinter/XP-80C?serial=ABC123
device for Cups-PDF: cups-pdf:/
device for Office_Laser: ipp://192.168.1.20/ipp/print
device for Kitchen: socket://192.168.1.50:9100
device for Tem_Zebra: usb://Zebra%20Technologies/ZTC%20GK420t?serial=1
device for Fax_Out: usb://Virtual/Fax
''';

  test('chỉ giữ hàng in USB thật (bỏ ảo, PDF, fax, mạng)', () {
    final q = LinuxCupsPrinters.parse(out);
    expect([for (final e in q) e.name], ['Xprinter_XP-80C', 'Tem_Zebra']);
    expect(q.first.uri, startsWith('usb://Xprinter/'));
  });

  test('lpstat rỗng / lỗi → không có máy', () {
    expect(LinuxCupsPrinters.parse(''), isEmpty);
    expect(LinuxCupsPrinters.parse('lpstat: No destinations added.'), isEmpty);
  });

  test('máy đã thấy trực tiếp thì không liệt kê lại hàng in CUPS của nó', () {
    const uri = 'usb://Xprinter/XP-80C?serial=ABC123';
    expect(LinuxCupsPrinters.isDuplicate(uri, ['Xprinter XP-80C']), isTrue);
    expect(LinuxCupsPrinters.isDuplicate(uri, ['Epson TM-T20']), isFalse);
    expect(LinuxCupsPrinters.isDuplicate(uri, const []), isFalse);
  });

  test('địa chỉ lpq: là máy in USB cục bộ', () {
    expect(UsbPrinters.isLocal('lpq:Xprinter_XP-80C'), isTrue);
    expect(UsbPrinters.label('lpq:Xprinter_XP-80C'), 'Xprinter XP-80C');
  });
}
