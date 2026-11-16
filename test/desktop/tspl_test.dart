import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:printer_label/desktop.dart';
import 'package:printer_label/printer_label.dart'
    show LabelCalibration, LabelCalibrationImage, LabelPerRow;

img.Image _solid(int w, int h, img.Color c) {
  final i = img.Image(width: w, height: h, numChannels: 4);
  img.fill(i, color: c);
  return i;
}

class _FakePort implements PrinterPort {
  final sent = <Uint8List>[];
  final checks = <bool>[];

  @override
  String get id => 'fake';

  @override
  Future<void> send(Uint8List data, {bool checkStatus = true}) async {
    sent.add(data);
    checks.add(checkStatus);
  }

  @override
  Future<PaperStatus> queryStatus() async => PaperStatus.unknown;
}

String _ascii(Uint8List b) => latin1.decode(b);

void main() {
  group('TsplRaster', () {
    test('ảnh đen: mọi bit 0 (in hết); ảnh trắng: mọi bit 1', () {
      final black = TsplRaster.encode(
        _solid(16, 2, img.ColorRgba8(0, 0, 0, 255)),
        widthDots: 16,
        heightDots: 2,
        shiftXDots: 0,
      );
      expect(black.widthBytes, 2);
      expect(black.bits, everyElement(0x00));
      final white = TsplRaster.encode(
        _solid(16, 2, img.ColorRgba8(255, 255, 255, 255)),
        widthDots: 16,
        heightDots: 2,
        shiftXDots: 0,
      );
      expect(white.bits, everyElement(0xFF));
    });

    test('nền trong suốt coi là trắng', () {
      final r = TsplRaster.encode(
        _solid(8, 1, img.ColorRgba8(0, 0, 0, 0)),
        widthDots: 8,
        heightDots: 1,
        shiftXDots: 0,
      );
      expect(r.bits, [0xFF]);
    });

    test(
      'ảnh không có kênh alpha (JPEG/BMP) vẫn in đúng, không bị coi trong suốt',
      () {
        final rgb = img.Image(width: 8, height: 1, numChannels: 3);
        img.fill(rgb, color: img.ColorRgb8(0, 0, 0));
        final r = TsplRaster.encode(
          rgb,
          widthDots: 8,
          heightDots: 1,
          shiftXDots: 0,
        );
        expect(r.bits, [0x00]);
      },
    );

    test('invert đảo quy ước bit', () {
      final r = TsplRaster.encode(
        _solid(8, 1, img.ColorRgba8(0, 0, 0, 255)),
        widthDots: 8,
        heightDots: 1,
        shiftXDots: 0,
        invert: true,
      );
      expect(r.bits, [0xFF]);
    });

    test(
      'dịch sang trái 8 chấm: điểm nguồn x=8 về x=0, phần mới lộ ra trắng',
      () {
        // Hàng 16 chấm: nửa trái trắng, nửa phải đen.
        final i = _solid(16, 1, img.ColorRgba8(255, 255, 255, 255));
        for (var x = 8; x < 16; x++) {
          i.setPixelRgba(x, 0, 0, 0, 0, 255);
        }
        final r = TsplRaster.encode(i, widthDots: 16, heightDots: 1);
        // Sau dịch -8: byte đầu lấy nửa phải (đen → 0x00), byte sau trắng (0xFF).
        expect(r.bits, [0x00, 0xFF]);
      },
    );

    test('co ảnh về đúng số chấm khổ tem', () {
      final r = TsplRaster.encode(
        _solid(1000, 600, img.ColorRgba8(255, 255, 255, 255)),
        widthDots: 400,
        heightDots: 240,
      );
      expect(r.widthBytes, 50);
      expect(r.bits.length, 50 * 240);
    });

    test('không đọc được ảnh → null', () {
      expect(
        TsplRaster.encodeImageBytes(
          Uint8List.fromList([1, 2, 3]),
          widthDots: 8,
          heightDots: 8,
        ),
        isNull,
      );
    });
  });

  group('TsplCommands', () {
    test(
      'một tem: SIZE / GAP / REFERENCE / DIRECTION / CLS / BITMAP / PRINT',
      () {
        final data = TsplCommands.label(
          bitmap: Uint8List.fromList([0xAA, 0xBB]),
          widthBytes: 2,
          heightDots: 1,
          widthMm: 50,
          heightMm: 30,
          gapMm: 2,
          copies: 3,
        );
        final text = _ascii(data);
        expect(
          text.startsWith(
            'SIZE 50 mm,30 mm\r\nGAP 2 mm,0 mm\r\nREFERENCE 0,0\r\n'
            'DIRECTION 0\r\nCLS\r\nBITMAP 0,0,2,1,0,',
          ),
          isTrue,
          reason: text,
        );
        const tail = '\r\nPRINT 1,3\r\n';
        expect(
          data.sublist(
            data.length - tail.length - 2,
            data.length - tail.length,
          ),
          [0xAA, 0xBB],
        );
        expect(text.endsWith('\r\nPRINT 1,3\r\n'), isTrue);
        expect(text.contains('HOME'), isFalse);
      },
    );

    test('khổ 3 tem có HOME trước CLS; số lẻ giữ phần thập phân', () {
      final text = _ascii(
        TsplCommands.label(
          bitmap: Uint8List(1),
          widthBytes: 1,
          heightDots: 1,
          widthMm: 72.5,
          heightMm: 22,
          home: true,
        ),
      );
      expect(text.contains('SIZE 72.5 mm,22 mm'), isTrue);
      expect(text.indexOf('HOME') < text.indexOf('CLS'), isTrue);
    });
  });

  group('TsplLabelSpec / chỉnh lệch', () {
    test('từ khổ tem của app: kích thước, khe, HOME khổ 3 tem', () {
      final one = TsplLabelSpec.fromLabelPerRow(LabelPerRow.single)!;
      expect(
        [one.widthMm, one.heightMm, one.gapMm, one.home],
        [50, 30, 2, false],
      );
      expect(one.widthDots, 400);
      final triple = TsplLabelSpec.fromLabelPerRow(LabelPerRow.triple)!;
      expect(triple.home, isTrue);
      expect(triple.widthMm, 106);
    });

    test(
      'chỉnh lệch dịch ngay trong ảnh (8 chấm = 1mm), không dùng REFERENCE',
      () async {
        final port = _FakePort();
        final png = Uint8List.fromList(
          img.encodePng(_solid(80, 40, img.ColorRgba8(255, 255, 255, 255))),
        );
        await TsplPrinter.printImages(
          port,
          [png],
          spec: const TsplLabelSpec(widthMm: 10, heightMm: 5, shiftXDots: 0),
          calibration: const LabelCalibration(offsetXMm: 1.5, offsetYMm: -2),
        );
        final text = _ascii(port.sent.single);
        expect(text, contains('REFERENCE 0,0'));
        expect(text, isNot(contains('REFERENCE 12')));
        expect(text, contains('SIZE 10 mm,5 mm'));
        expect(text, contains('BITMAP 0,0,10,40,0,'));
      },
    );

    test(
      'dịch dọc: dương = nội dung xuống dưới, âm = lên trên; phần lộ ra trắng',
      () {
        // Ảnh 8x4: hàng 0 đen, còn lại trắng.
        final i = _solid(8, 4, img.ColorRgba8(255, 255, 255, 255));
        for (var x = 0; x < 8; x++) {
          i.setPixelRgba(x, 0, 0, 0, 0, 255);
        }
        List<int> shifted(int dy) => TsplRaster.encode(
          i,
          widthDots: 8,
          heightDots: 4,
          shiftXDots: 0,
          shiftYDots: dy,
        ).bits.toList();
        expect(shifted(0), [0x00, 0xFF, 0xFF, 0xFF]);
        expect(shifted(1), [0xFF, 0x00, 0xFF, 0xFF]); // xuống 1 dòng
        expect(shifted(-1), [
          0xFF,
          0xFF,
          0xFF,
          0xFF,
        ]); // dòng đen bị đẩy ra ngoài
        expect(shifted(10), [0xFF, 0xFF, 0xFF, 0xFF]);
      },
    );

    test(
      'chỉnh lệch ngang/dọc trong job: nội dung dịch đúng số chấm',
      () async {
        final port = _FakePort();
        // Ảnh 16x8: một chấm đen ở (4,2).
        final i = _solid(16, 8, img.ColorRgba8(255, 255, 255, 255));
        i.setPixelRgba(4, 2, 0, 0, 0, 255);
        final png = Uint8List.fromList(img.encodePng(i));
        await TsplPrinter.printImages(
          port,
          [png],
          // 2mm x 1mm = 16 x 8 chấm.
          spec: const TsplLabelSpec(widthMm: 2, heightMm: 1, shiftXDots: 0),
          calibration: const LabelCalibration(offsetXMm: 0.5, offsetYMm: 0.125),
        );
        final data = port.sent.single;
        final head = _ascii(data);
        final at =
            head.indexOf('BITMAP 0,0,2,8,0,') + 'BITMAP 0,0,2,8,0,'.length;
        final bits = data.sublist(at, at + 16);
        bool black(int x, int y) =>
            (bits[y * 2 + (x >> 3)] & (0x80 >> (x & 7))) == 0;
        // 0,5mm = 4 chấm sang phải; 0,125mm = 1 chấm xuống: (4,2) → (8,3).
        expect(black(8, 3), isTrue);
        expect(black(4, 2), isFalse);
      },
    );

    test('khổ tuỳ chỉnh 4 tem/hàng 106x15: đúng số chấm', () async {
      final port = _FakePort();
      final png = Uint8List.fromList(
        img.encodePng(_solid(848, 120, img.ColorRgba8(255, 255, 255, 255))),
      );
      await TsplPrinter.printImages(
        port,
        [png],
        spec: const TsplLabelSpec(
          widthMm: 106,
          heightMm: 15,
          gapMm: 2,
          shiftXDots: 0,
        ),
      );
      expect(_ascii(port.sent.single), contains('BITMAP 0,0,106,120,0,'));
    });
  });

  group('Tem thử căn chỉnh', () {
    test(
      'printCalibration: ảnh đúng khổ, độ chỉnh áp trong ảnh, REFERENCE giữ 0,0',
      () async {
        final port = _FakePort();
        await TsplPrinter.printCalibration(
          port,
          spec: TsplLabelSpec.fromLabelPerRow(LabelPerRow.single40x30)!,
          calibration: const LabelCalibration(offsetXMm: -1, offsetYMm: 0.5),
        );
        final text = _ascii(port.sent.single);
        expect(text, contains('SIZE 40 mm,30 mm'));
        expect(text, contains('REFERENCE 0,0'));
        expect(text, contains('BITMAP 0,0,40,240,0,'));
      },
    );

    test('khung sát mép: bit 0 (đen) ở mọi mép của bitmap', () {
      final png = LabelCalibrationImage.png(widthMm: 40, heightMm: 30);
      final r = TsplRaster.encodeImageBytes(
        png,
        widthDots: 320,
        heightDots: 240,
        shiftXDots: 0,
      )!;
      bool black(int x, int y) =>
          (r.bits[y * r.widthBytes + (x >> 3)] & (0x80 >> (x & 7))) == 0;
      for (var x = 0; x < 320; x++) {
        expect(black(x, 0), isTrue, reason: 'mép trên x=$x');
        expect(black(x, 239), isTrue, reason: 'mép dưới x=$x');
      }
      for (var y = 0; y < 240; y++) {
        expect(black(0, y), isTrue, reason: 'mép trái y=$y');
        expect(black(319, y), isTrue, reason: 'mép phải y=$y');
      }
      // Dấu thập giữa tem.
      expect(black(160, 120), isTrue);
      // Ruột tem không kín đen (còn trắng).
      expect(black(100, 100), isFalse);
    });

    test('tem nhỏ 25x15 vẫn vẽ được (không ném lỗi, đúng kích thước)', () {
      final png = LabelCalibrationImage.png(widthMm: 25, heightMm: 15);
      final d = img.decodePng(png)!;
      expect([d.width, d.height], [200, 120]);
    });
  });

  _sampleSlipTests();
  _driftFixTests();

  group('Dò khe tem', () {
    test('GAPDETECT kèm khổ và khe đã khai báo', () async {
      final port = _FakePort();
      await TsplPrinter.detectGap(
        port,
        spec: const TsplLabelSpec(widthMm: 72, heightMm: 22, gapMm: 3),
      );
      expect(
        _ascii(port.sent.single),
        'SIZE 72 mm,22 mm\r\nGAP 3 mm,0 mm\r\nGAPDETECT\r\n',
      );
      expect(port.checks.single, isFalse);
    });
  });

  group('LabelCalibration', () {
    test('chỉnh theo nấc 0,5mm và giới hạn ±20mm', () {
      var c = LabelCalibration.none;
      expect(c.isZero, isTrue);
      c = c.nudge(dx: 0.5).nudge(dx: 0.5).nudge(dy: -0.5);
      expect([c.offsetXMm, c.offsetYMm], [1.0, -0.5]);
      expect([c.offsetXDots, c.offsetYDots], [8, -4]);
      expect(c.nudge(dx: 100).offsetXMm, 20);
      expect(c.nudge(dy: -100).offsetYMm, -20);
    });

    test('lưu / đọc và hiển thị', () {
      const c = LabelCalibration(offsetXMm: 1.5, offsetYMm: -2);
      expect(LabelCalibration.fromMap(c.toMap()), c);
      expect(LabelCalibration.fromMap('rác'), LabelCalibration.none);
      expect(LabelCalibration.fromMap({'x': 999, 'y': 'a'}).offsetXMm, 20);
      expect(LabelCalibration.format(1.5), '+1.5');
      expect(LabelCalibration.format(-2), '-2');
      expect(LabelCalibration.format(0), '0');
    });
  });

  group('TsplPrinter', () {
    test(
      'nhiều hàng tem gửi trong MỘT lần (một kết nối), đúng khổ 50x30, không hỏi giấy',
      () async {
        final port = _FakePort();
        final png = Uint8List.fromList(
          img.encodePng(_solid(560, 336, img.ColorRgba8(255, 255, 255, 255))),
        );
        await TsplPrinter.printImages(
          port,
          [png, png],
          spec: TsplLabelSpec.fromLabelPerRow(LabelPerRow.single)!,
          copies: 2,
        );
        expect(port.sent, hasLength(1));
        expect(port.checks, everyElement(isFalse));
        final text = _ascii(port.sent.single);
        // Hai hàng tem liền nhau trong cùng một gói.
        expect('SIZE 50 mm,30 mm'.allMatches(text), hasLength(2));
        expect('BITMAP 0,0,50,240,0,'.allMatches(text), hasLength(2));
        expect('PRINT 1,2\r\n'.allMatches(text), hasLength(2));
        expect(text.endsWith('PRINT 1,2\r\n'), isTrue);
      },
    );

    test('ảnh hỏng → FormatException, không gửi gì', () async {
      final port = _FakePort();
      await expectLater(
        TsplPrinter.printImages(port, [
          Uint8List.fromList([1, 2, 3]),
        ], spec: TsplLabelSpec.fromLabelPerRow(LabelPerRow.single)!),
        throwsFormatException,
      );
      expect(port.sent, isEmpty);
    });
  });
}

void _sampleSlipTests() {
  group('Tem mẫu giống hình xem trước', () {
    test(
      'tem 2 hàng 35x22: khung thụt vào khỏi mép, thanh chữ + mã vạch trong từng tem',
      () {
        final png = LabelCalibrationImage.png(
          widthMm: 72,
          heightMm: 22,
          labelsPerRow: 2,
          temWidthMm: 35,
        );
        final d = img.decodePng(png)!;
        expect([d.width, d.height], [576, 176]);
        bool dark(int x, int y) => d.getPixel(x, y).r < 128;
        int darkIn(int x1, int x2, int y1, int y2) {
          var n = 0;
          for (var y = y1; y < y2; y++) {
            for (var x = x1; x < x2; x++) {
              if (dark(x, y)) n++;
            }
          }
          return n;
        }

        // Mép ngoài của ảnh trắng (khung thụt vào ~25 chấm): lệch thì khung chạm / bị cắt mép.
        expect(darkIn(0, d.width, 0, 3), 0);
        expect(darkIn(0, d.width, d.height - 3, d.height), 0);
        expect(darkIn(0, 3, 0, d.height), 0);
        // Có khung ở cả hai tem (cạnh trái khung tem 1 và tem 2).
        expect(dark(26, 88), isTrue);
        expect(dark(322, 88), isTrue);
        // Mỗi tem có thanh chữ ở nửa trên và vạch mã vạch ở nửa dưới.
        expect(darkIn(40, 200, 38, 58), greaterThan(500));
        expect(darkIn(40, 260, 100, 150), greaterThan(500));
        expect(darkIn(320, 540, 100, 150), greaterThan(500));
        // Khe giữa hai tem để trống.
        expect(darkIn(284, 292, 0, d.height), 0);
      },
    );

    test('tem nhỏ 25x15 x4 vẫn vẽ được, không ném lỗi', () {
      final png = LabelCalibrationImage.png(
        widthMm: 106,
        heightMm: 15,
        labelsPerRow: 4,
        temWidthMm: 25,
      );
      final d = img.decodePng(png)!;
      expect([d.width, d.height], [848, 120]);
    });
  });
}

void _driftFixTests() {
  group('Chống tem lệch dần', () {
    test('repeat: nhiều hàng tem thử trong MỘT lần gửi', () async {
      final port = _FakePort();
      await TsplPrinter.printCalibration(
        port,
        spec: const TsplLabelSpec(widthMm: 72, heightMm: 22),
        repeat: 4,
      );
      expect(port.sent, hasLength(1));
      expect('BITMAP'.allMatches(_ascii(port.sent.single)).length, 4);
    });

    test('khe lẻ 2,5mm và HOME đi vào lệnh in', () {
      final data = TsplCommands.label(
        bitmap: Uint8List(8),
        widthBytes: 1,
        heightDots: 8,
        widthMm: 72,
        heightMm: 22,
        gapMm: 2.5,
        home: true,
      );
      final text = String.fromCharCodes(data.where((b) => b < 128));
      expect(text, contains('GAP 2.5 mm,0 mm'));
      expect(text, contains('HOME'));
    });

    test('không bật HOME thì không gửi HOME', () {
      final data = TsplCommands.label(
        bitmap: Uint8List(8),
        widthBytes: 1,
        heightDots: 8,
        widthMm: 72,
        heightMm: 22,
      );
      expect(
        String.fromCharCodes(data.where((b) => b < 128)),
        isNot(contains('HOME')),
      );
    });
  });
}
