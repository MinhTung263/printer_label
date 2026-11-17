import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';
import 'package:printer_label/src/desktop/usb/linux_usb_printers.dart';

void main() {
  late Directory root;
  late String oldSys, oldDev;

  setUp(() {
    root = Directory.systemTemp.createTempSync('linux_usb_');
    oldSys = LinuxUsbPrinters.sysClass;
    oldDev = LinuxUsbPrinters.devDir;
    LinuxUsbPrinters.sysClass = '${root.path}/sys/usbmisc';
    LinuxUsbPrinters.devDir = '${root.path}/dev/usb';
    Directory(LinuxUsbPrinters.devDir).createSync(recursive: true);
  });

  tearDown(() {
    LinuxUsbPrinters.sysClass = oldSys;
    LinuxUsbPrinters.devDir = oldDev;
    root.deleteSync(recursive: true);
  });

  /// Dựng một máy in giả: thư mục lớp `lp0` + file thiết bị + các thuộc tính USB.
  void plug(
    String lp, {
    String vid = '1fc9',
    String pid = '2016',
    String serial = '03365B350113',
    String manufacturer = '',
    String product = '',
    String? ieee,
  }) {
    final dir = Directory('${LinuxUsbPrinters.sysClass}/$lp')
      ..createSync(recursive: true);
    File('${LinuxUsbPrinters.devDir}/$lp').writeAsStringSync('');
    void put(String name, String value) {
      if (value.isNotEmpty) File('${dir.path}/$name').writeAsStringSync(value);
    }

    put('idVendor', vid);
    put('idProduct', pid);
    put('serial', serial);
    put('manufacturer', manufacturer);
    put('product', product);
    // Như sysfs thật: `device` là interface USB (chứa `ieee1284_id`), thư mục cha của nó là thiết bị USB.
    final iface = Directory('${dir.path}/device')..createSync();
    if (ieee != null) {
      File('${iface.path}/ieee1284_id').writeAsStringSync(ieee);
    }
  }

  test(
    'máy tem không khai tên USB (4BARCODE): lấy tên từ chuỗi IEEE 1284 của máy',
    () async {
      plug(
        'lp0',
        ieee:
            'SERN:03365B350113;MFG:4BARCODE;CMD:TSPL2;MDL:3B-300B;CLS:PRINTER;',
      );
      final list = await LinuxUsbPrinters.list();
      expect(list, hasLength(1));
      expect(list.single.name, '4BARCODE 3B-300B');
      expect(list.single.address, 'usb:1fc9:2016:03365B350113');
    },
  );

  test(
    'đọc được chuỗi IEEE 1284 → biết máy hiểu TSPL (máy tem) để bíp / in đúng lệnh',
    () async {
      plug('lp0', ieee: 'MFG:4BARCODE;CMD:TSPL2;MDL:3B-300B;CLS:PRINTER;');
      final id = await LinuxUsbPrinters.deviceId('usb:1fc9:2016:03365B350113');
      expect(id, contains('CMD:TSPL2'));
      expect(PrinterLanguageProbe.fromIeee1284(id!), PrinterLanguage.label);
    },
  );

  test(
    'máy có tên trong mô tả USB: giữ tên đó; không có IEEE: tên mặc định theo vid:pid',
    () async {
      plug('lp0', manufacturer: 'Xprinter', product: 'XP-80C', serial: 'A1');
      plug('lp1', vid: 'aaaa', pid: 'bbbb', serial: 'B2');
      final list = await LinuxUsbPrinters.list();
      expect(list.map((p) => p.name), [
        'Xprinter XP-80C',
        'Máy in USB aaaa:bbbb',
      ]);
      expect(await LinuxUsbPrinters.deviceId('usb:aaaa:bbbb:B2'), isNull);
    },
  );

  test('rút máy: không còn chuỗi IEEE', () async {
    expect(await LinuxUsbPrinters.deviceId('usb:1fc9:2016:X'), isNull);
  });
}
