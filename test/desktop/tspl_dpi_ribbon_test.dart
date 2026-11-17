import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:printer_label/desktop.dart';
import 'package:printer_label/printer_label.dart' show LabelCalibration;

/// Cổng ghi lại byte đã gửi (không cần máy in).
class _CapturePort implements PrinterPort {
  final sent = <Uint8List>[];
  @override
  String get id => 'capture';
  @override
  Future<void> send(Uint8List data, {bool checkStatus = true}) async =>
      sent.add(data);
  @override
  Future<PaperStatus> queryStatus() async => PaperStatus.unknown;

  String get text => String.fromCharCodes(sent.expand((e) => e));
}

Uint8List _png() {
  final image = img.Image(width: 32, height: 24);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test(
    '203dpi (mặc định): đúng như cũ — 8 chấm/mm, không lệnh ruy-băng',
    () async {
      const spec = TsplLabelSpec(widthMm: 40, heightMm: 30);
      expect(spec.dotsPerMm, 8);
      expect(spec.widthDots, 320);
      expect(spec.heightDots, 240);
      expect(spec.scaledShiftXDots, -8);
      final port = _CapturePort();
      await TsplPrinter.printImages(port, [_png()], spec: spec);
      expect(port.text, contains('BITMAP 0,0,40,240,0,'));
      expect(port.text, isNot(contains('RIBBON')));
    },
  );

  test(
    '300dpi (tem vàng bạc): ~11,81 chấm/mm, bitmap đúng cỡ, lề dịch theo tỉ lệ',
    () async {
      const spec = TsplLabelSpec(widthMm: 40, heightMm: 30, dpi: 300);
      expect(spec.widthDots, 472);
      expect(spec.heightDots, 354);
      expect(spec.scaledShiftXDots, -12); // -1mm ở 300dpi
      final port = _CapturePort();
      await TsplPrinter.printImages(port, [_png()], spec: spec);
      // 472 chấm = 59 byte mỗi dòng.
      expect(port.text, contains('BITMAP 0,0,59,354,0,'));
      expect(port.text, contains('SIZE 40 mm,30 mm'));
    },
  );

  test('ruy-băng: SET RIBBON ON / OFF, đúng lệnh TSPL2', () async {
    for (final (ribbon, line) in [
      (true, 'SET RIBBON ON'),
      (false, 'SET RIBBON OFF'),
    ]) {
      final port = _CapturePort();
      await TsplPrinter.printImages(
        port,
        [_png()],
        spec: TsplLabelSpec(
          widthMm: 50,
          heightMm: 12,
          dpi: 300,
          ribbon: ribbon,
        ),
      );
      final t = port.text;
      expect(t, contains('$line\r\n'));
      // Lệnh ruy-băng đứng trước CLS và BITMAP.
      expect(t.indexOf(line), lessThan(t.indexOf('CLS')));
      expect(t.indexOf('CLS'), lessThan(t.indexOf('BITMAP')));
      expect(
        t,
        isNot(contains('\r\nRIBBON')),
        reason: 'không dùng lệnh sai "RIBBON ON"',
      );
    }
  });

  test(
    'chỉnh lệch 1mm → dịch đúng số chấm theo đầu in: 8 chấm (203dpi) / 12 chấm (300dpi)',
    () async {
      // Ảnh có cột đen ở x = 0 (đúng cỡ bitmap nên không bị co / giãn).
      Uint8List column(int w, int h) {
        final image = img.Image(width: w, height: h, numChannels: 4)
          ..clear(img.ColorRgba8(255, 255, 255, 255));
        for (var y = 0; y < h; y++) {
          image.setPixelRgba(0, y, 0, 0, 0, 255);
        }
        return Uint8List.fromList(img.encodePng(image));
      }

      // Vị trí chấm đen đầu tiên của dòng đầu trong bitmap đã gửi.
      int firstBlackX(_CapturePort port, int widthBytes, int heightDots) {
        final bytes = port.sent.expand((e) => e).toList();
        final head = 'BITMAP 0,0,$widthBytes,$heightDots,0,';
        final start = String.fromCharCodes(bytes).indexOf(head) + head.length;
        for (var x = 0; x < widthBytes * 8; x++) {
          if ((bytes[start + (x >> 3)] & (0x80 >> (x & 7))) == 0) return x;
        }
        return -1;
      }

      for (final (dpi, w, h, widthBytes, expectX) in [
        (203, 320, 240, 40, 8),
        (300, 472, 354, 59, 12),
      ]) {
        final port = _CapturePort();
        await TsplPrinter.printImages(
          port,
          [column(w, h)],
          spec: TsplLabelSpec(
            widthMm: 40,
            heightMm: 30,
            dpi: dpi,
            shiftXDots: 0,
          ),
          calibration: const LabelCalibration(offsetXMm: 1),
        );
        expect(firstBlackX(port, widthBytes, h), expectX, reason: '$dpi dpi');
      }
    },
  );

  test(
    'copyWith giữ dpi và ruy-băng khi chỉ đổi dịch lề (tem thử căn chỉnh)',
    () {
      const spec = TsplLabelSpec(
        widthMm: 40,
        heightMm: 30,
        dpi: 300,
        ribbon: true,
      );
      final c = spec.copyWith(shiftXDots: 0);
      expect(c.dpi, 300);
      expect(c.ribbon, isTrue);
      expect(c.shiftXDots, 0);
    },
  );
}
