import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  _extraTests();
  _postscriptTests();
  _variantTests();
  test('IEEE 1284: CMD:TSPL2 → máy tem; ESC/POS → hoá đơn; cả hai → both', () {
    expect(
      PrinterLanguageProbe.fromIeee1284(
        'SERN:03365B350113;MFG:4BARCODE;CMD:TSPL2;MDL:3B-300B;CLS:PRINTER;',
      ),
      PrinterLanguage.label,
    );
    expect(
      PrinterLanguageProbe.fromIeee1284(
        'MFG:Xprinter;CMD:ESC/POS;MDL:XP-80C;CLS:PRINTER;',
      ),
      PrinterLanguage.receipt,
    );
    expect(
      PrinterLanguageProbe.fromIeee1284('MFG:X;CMD:ESCPOS,TSPL;CLS:PRINTER;'),
      PrinterLanguage.both,
    );
    expect(
      PrinterLanguageProbe.fromIeee1284('MFG:X;MDL:Y;CLS:PRINTER;'),
      isNull,
    );
    expect(
      PrinterLanguageProbe.fromIeee1284('MFG:X;CMD:UNKNOWNLANG;'),
      PrinterLanguage.unknown,
    );
  });

  test('đọc device-id từ `lpinfo -l -v`', () {
    const out = '''
Device: uri = usb://4BARCODE/3B-300B?serial=03365B350113
        class = direct
        info = 4BARCODE 3B-300B
        device-id = SERN:03365B350113;MFG:4BARCODE;CMD:TSPL2;MDL:3B-300B;CLS:PRINTER;
        location = 
Device: uri = usb://Gprinter/USB%20Printer?serial=1
        class = direct
        device-id = MFG:Gprinter;CMD:ESC/POS;CLS:PRINTER;
''';
    final m = MacCupsPrinters.parseLpinfoDeviceIds(out);
    expect(m['usb://4BARCODE/3B-300B?serial=03365B350113'], contains('TSPL2'));
    expect(m['usb://Gprinter/USB%20Printer?serial=1'], contains('ESC/POS'));
    expect(m.length, 2);
  });
}

void _extraTests() {
  group('IEEE 1284 + bíp', () {
    test('tên hãng model từ chuỗi định danh', () {
      expect(
        Ieee1284.name('MFG:4BARCODE;CMD:TSPL2;MDL:3B-300B;CLS:PRINTER;'),
        '4BARCODE 3B-300B',
      );
      expect(
        Ieee1284.name(
          'MANUFACTURER:Xprinter;MODEL:Xprinter XP-80C;COMMAND SET:ESC/POS;',
        ),
        'Xprinter XP-80C',
      );
      expect(Ieee1284.isPrinter('MFG:A;CLS:PRINTER;'), isTrue);
      expect(Ieee1284.isPrinter('MFG:A;MDL:B;'), isFalse);
    });

    test('lệnh bíp: máy tem SOUND, máy hoá đơn ESC B', () {
      expect(
        String.fromCharCodes(PrinterBeep.bytes(label: true)),
        startsWith('SOUND'),
      );
      expect(PrinterBeep.bytes(label: false), [0x1B, 0x42, 0x03, 0x02]);
    });

    test('tên ngắn máy USB Windows từ đường dẫn thiết bị', () {
      expect(
        WindowsUsbPrint.shortName(
          r'usbp:\\?\usb#vid_0483&pid_5740#0001#{28d78fad-5a12-11d1-ae5b-0000f803a8c2}',
        ),
        'USB 0483:5740',
      );
      expect(WindowsUsbPrint.shortName(r'usbp:\\?\other'), 'Máy in USB');
      expect(UsbPrinters.isLocal(r'usbp:\\?\usb#vid_0483&pid_5740'), isTrue);
    });
  });
}

void _postscriptTests() {
  test(
    'IEEE 1284: máy văn phòng (PCL / PostScript) KHÔNG bị nhận nhầm là máy tem',
    () {
      // "POSTSCRIPT" chứa chuỗi con "TSC" — chỉ khớp theo đầu từng lệnh.
      expect(
        PrinterLanguageProbe.fromIeee1284(
          'MFG:HP;MDL:DesignJet T920;CMD:PCL,PJL,POSTSCRIPT;CLS:PRINTER;',
        ),
        PrinterLanguage.unknown,
      );
      expect(
        PrinterLanguageProbe.fromIeee1284(
          'MFG:ACME;CMD:ESCPOS,PCL,POSTSCRIPT;CLS:PRINTER;',
        ),
        PrinterLanguage.receipt,
      );
      expect(
        PrinterLanguageProbe.fromIeee1284(
          'MFG:TSC;CMD:TSPL2,POSTSCRIPT;CLS:PRINTER;',
        ),
        PrinterLanguage.label,
      );
    },
  );
}

void _variantTests() {
  test('IEEE 1284: các cách viết lệnh của từng hãng đều nhận đúng', () {
    PrinterLanguage? of(String cmd) =>
        PrinterLanguageProbe.fromIeee1284('MFG:X;MDL:Y;CMD:$cmd;CLS:PRINTER;');
    // Máy hoá đơn.
    for (final c in [
      'ESC/POS',
      'ESCPOS',
      'ESC POS',
      'ESC_POS',
      'EPSON',
      'esc/pos',
      'STAR',
      'ESC/POS,PCL',
    ]) {
      expect(of(c), PrinterLanguage.receipt, reason: c);
    }
    // Máy tem.
    for (final c in [
      'TSPL',
      'TSPL2',
      'tspl2',
      'ZPL',
      'ZPL II',
      'EPL2',
      'EZPL',
      'CPCL',
      'DPL',
      'TSC',
      'BPLA',
    ]) {
      expect(of(c), PrinterLanguage.label, reason: c);
    }
    // Cả hai.
    expect(of('ESC/POS,TSPL2'), PrinterLanguage.both);
    expect(of('ESC POS, TSPL'), PrinterLanguage.both);
    // Máy văn phòng / không rõ: không phải phiếu cũng không phải tem.
    for (final c in [
      'PCL',
      'PCL,PJL,POSTSCRIPT',
      'ESCPR',
      'ESC/P',
      'GDI',
      'URF',
    ]) {
      expect(of(c), PrinterLanguage.unknown, reason: c);
    }
  });

  test('COMMAND SET: tên đầy đủ cũng được đọc', () {
    expect(
      PrinterLanguageProbe.fromIeee1284(
        'MANUFACTURER:X;COMMAND SET:ESC/POS;MODEL:Y;',
      ),
      PrinterLanguage.receipt,
    );
    expect(PrinterLanguageProbe.fromIeee1284('MFG:X;MDL:Y;'), isNull);
  });
}
