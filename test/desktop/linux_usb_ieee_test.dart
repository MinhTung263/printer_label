import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';
import 'package:printer_label/src/desktop/usb/linux_usb_printers.dart';

void main() {
  _issueTests();
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

void _issueTests() {
  late Directory root;
  late String oldBus, oldSys, oldDev;
  setUp(() {
    root = Directory.systemTemp.createTempSync('linux_issue_');
    oldBus = LinuxUsbPrinters.usbBus;
    oldSys = LinuxUsbPrinters.sysClass;
    oldDev = LinuxUsbPrinters.devDir;
    LinuxUsbPrinters.usbBus = '${root.path}/bus';
    LinuxUsbPrinters.sysClass = '${root.path}/sys';
    LinuxUsbPrinters.devDir = '${root.path}/dev';
    Directory(LinuxUsbPrinters.usbBus).createSync(recursive: true);
    Directory(LinuxUsbPrinters.devDir).createSync(recursive: true);
  });
  tearDown(() {
    LinuxUsbPrinters.usbBus = oldBus;
    LinuxUsbPrinters.sysClass = oldSys;
    LinuxUsbPrinters.devDir = oldDev;
    root.deleteSync(recursive: true);
  });

  /// Như sysfs thật: thiết bị `real/1-1` (idVendor, product) chứa interface `1-1:1.0`; thư mục `bus` chứa
  /// LIÊN KẾT tới interface (nên `interface/..` là thiết bị USB). Trả thư mục interface.
  Directory plugIface({String cls = '07', bool lp = false}) {
    final dev = Directory('${root.path}/real/1-1')..createSync(recursive: true);
    File('${dev.path}/idVendor').writeAsStringSync('0483');
    File('${dev.path}/idProduct').writeAsStringSync('5743');
    File('${dev.path}/product').writeAsStringSync('XP-80C');
    final i = Directory('${dev.path}/1-1:1.0')..createSync();
    File('${i.path}/bInterfaceClass').writeAsStringSync(cls);
    if (lp) Directory('${i.path}/usbmisc/lp0').createSync(recursive: true);
    Link('${LinuxUsbPrinters.usbBus}/1-1:1.0').createSync(i.path);
    return i;
  }

  test('không có thiết bị kiểu máy in: không báo gì', () async {
    expect(await LinuxUsbPrinters.issues(), isEmpty);
  });

  test(
    'thiết bị không phải máy in (class khác 07): bỏ qua, không phải "USB rác" báo lỗi',
    () async {
      plugIface(cls: '08');
      expect(await LinuxUsbPrinters.issues(), isEmpty);
    },
  );

  test(
    'máy in USB chưa có /dev/usb/lpN: báo vì sao + cách xử lý (usblp)',
    () async {
      plugIface();
      final issues = await LinuxUsbPrinters.issues();
      expect(issues, hasLength(1));
      expect(issues.single.name, 'XP-80C');
      expect(issues.single.message, contains('usblp'));
      expect(issues.single.message, contains('modprobe'));
    },
  );

  test('driver khác đang giữ máy in: nêu tên driver', () async {
    final i = plugIface();
    final drv = Directory('${root.path}/drivers/usbfs')
      ..createSync(recursive: true);
    Link('${i.path}/driver').createSync(drv.path);
    final issues = await LinuxUsbPrinters.issues();
    expect(issues.single.message, contains('"usbfs"'));
  });

  test('có /dev/usb/lpN ghi được: không báo gì', () async {
    plugIface(lp: true);
    File('${LinuxUsbPrinters.devDir}/lp0').writeAsStringSync('');
    expect(await LinuxUsbPrinters.issues(), isEmpty);
  });

  test(
    'có /dev/usb/lpN nhưng không có quyền ghi: báo quyền + cách xử lý (udev / nhóm lp)',
    () async {
      plugIface(lp: true);
      final dev = File('${LinuxUsbPrinters.devDir}/lp0')..writeAsStringSync('');
      Process.runSync('chmod', ['000', dev.path]);
      // Chạy bằng root thì vẫn ghi được: không có gì để kiểm.
      final canWrite = (() {
        try {
          dev.openSync(mode: FileMode.append).closeSync();
          return true;
        } catch (_) {
          return false;
        }
      })();
      final issues = await LinuxUsbPrinters.issues();
      if (canWrite) {
        expect(issues, isEmpty);
      } else {
        expect(issues.single.message, contains('không có quyền ghi'));
        expect(issues.single.message, contains('udev'));
      }
    },
  );
}
