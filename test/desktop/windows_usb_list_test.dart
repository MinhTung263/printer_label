import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

Map<String, Object?> _p(String name, String port, {bool offline = false}) => {
  'Name': name,
  'PortName': port,
  'DriverName': 'Driver',
  'WorkOffline': offline,
};

void main() {
  test(
    'Windows: chỉ máy in USB đang cắm, bỏ máy in ảo / hệ thống / mạng / đã rút',
    () {
      final list = WindowsRawPrinters.usbQueues([
        _p('Microsoft XPS Document Writer', 'XPSPort:'),
        _p('Microsoft Print to PDF', 'PORTPROMPT:'),
        _p('Fax', 'SHRFAX:'),
        _p('OneNote (Desktop)', 'nul:'),
        _p('Máy in bếp', 'IP_192.168.1.20'),
        _p('Xprinter XP-365B', 'USB001'),
        _p('EasyPOS USB002', 'USB002'),
        _p('Máy in cũ đã rút', 'USB003', offline: true),
      ]);
      expect(list.map((e) => e.name), ['Xprinter XP-365B', 'EasyPOS USB002']);
      expect(list.first.address, 'queue:Xprinter XP-365B');
      expect(list.every((e) => !e.needsSetup), isTrue);
    },
  );

  test('không có máy in USB nào → danh sách rỗng', () {
    expect(WindowsRawPrinters.usbQueues([_p('Fax', 'SHRFAX:')]), isEmpty);
    expect(WindowsRawPrinters.usbQueues(const []), isEmpty);
  });
}
