import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  test('lpstat -v: tên hàng in + URI', () {
    const out = '''
device for EasyPOS_XPrinter_XP_80C_A1B2C3: usb://XPrinter/XP-80C?serial=00A1B2C3
device for HP_LaserJet: dnssd://HP%20LaserJet._ipp._tcp.local./?uuid=1
''';
    final q = MacCupsPrinters.parseLpstat(out);
    expect(q.map((e) => e.name), [
      'EasyPOS_XPrinter_XP_80C_A1B2C3',
      'HP_LaserJet',
    ]);
    expect(q.first.uri, 'usb://XPrinter/XP-80C?serial=00A1B2C3');
  });

  test('lpinfo -v: chỉ lấy máy in USB cắm trực tiếp', () {
    const out = '''
network ipp
direct usb://XPrinter/XP-80C?serial=00A1B2C3
direct usb://Printer/POS-80?location=14100000
network socket
''';
    expect(MacCupsPrinters.parseLpinfo(out), [
      'usb://XPrinter/XP-80C?serial=00A1B2C3',
      'usb://Printer/POS-80?location=14100000',
    ]);
  });

  test(
    'tên hiển thị + tên hàng in hợp lệ, không trùng giữa 2 máy cùng model',
    () {
      const a = 'usb://XPrinter/XP-80C?serial=00A1B2C3';
      const b = 'usb://XPrinter/XP-80C?serial=00D4E5F6';
      expect(MacCupsPrinters.modelOf(a), 'XPrinter XP-80C');
      expect(MacCupsPrinters.queueNameFor(a), 'EasyPOS_XPrinter_XP_80C_A1B2C3');
      expect(
        MacCupsPrinters.queueNameFor(a),
        isNot(MacCupsPrinters.queueNameFor(b)),
      );
      expect(
        MacCupsPrinters.queueNameFor('usb://Printer/POS%2080'),
        'EasyPOS_Printer_POS_80',
      );
      expect(UsbPrinters.isLocal('cups:EasyPOS_POS_80'), isTrue);
      expect(
        UsbPrinters.label('cups:EasyPOS_Printer_POS_80'),
        'Printer POS 80',
      );
    },
  );
}
