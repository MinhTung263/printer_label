import 'dart:math';
import 'dart:typed_data';

import 'package:printer_label/desktop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Chép NGUYÊN thuật toán Kotlin `PrinterThermal.getEscPosRasterBytes` (pixel ARGB
/// int, `BLANK_FEED_MIN_ROWS = Int.MAX_VALUE`) để so từng byte với bản Dart.
Uint8List kotlinReference(List<int> argb, int width, int height) {
  final widthBytes = (width + 7) ~/ 8;
  final bits = Uint8List(widthBytes * height);
  for (var y = 0; y < height; y++) {
    for (var xByte = 0; xByte < widthBytes; xByte++) {
      var byteVal = 0;
      final x0 = xByte * 8;
      final xEnd = min(x0 + 8, width);
      for (var x = x0; x < xEnd; x++) {
        final pixel = argb[y * width + x];
        if (((pixel >> 24) & 0xff) > 50) {
          final gray1000 =
              299 * ((pixel >> 16) & 0xff) +
              587 * ((pixel >> 8) & 0xff) +
              114 * (pixel & 0xff);
          if (gray1000 < 200000) byteVal |= (0x80 >> (x - x0));
        }
      }
      bits[y * widthBytes + xByte] = byteVal;
    }
  }
  final out = <int>[];
  var y = 0;
  while (y < height) {
    final rows = min(128, height - y);
    out.addAll([
      0x1D, 0x76, 0x30, 0x00, //
      widthBytes % 256, widthBytes ~/ 256, rows % 256, rows ~/ 256,
    ]);
    out.addAll(bits.sublist(y * widthBytes, (y + rows) * widthBytes));
    y += rows;
  }
  return Uint8List.fromList(out);
}

Uint8List argbToRgba(List<int> argb) {
  final out = Uint8List(argb.length * 4);
  for (var i = 0; i < argb.length; i++) {
    final p = argb[i];
    out[i * 4] = (p >> 16) & 0xff;
    out[i * 4 + 1] = (p >> 8) & 0xff;
    out[i * 4 + 2] = p & 0xff;
    out[i * 4 + 3] = (p >> 24) & 0xff;
  }
  return out;
}

void main() {
  test('khớp từng byte với bản Kotlin trên ảnh ngẫu nhiên', () {
    final rnd = Random(42);
    for (final (w, h) in [
      (576, 300),
      (384, 129),
      (13, 1),
      (8, 128),
      (577, 257),
    ]) {
      final argb = List<int>.generate(w * h, (_) => rnd.nextInt(1 << 32));
      expect(
        EscPosRaster.encodeRgba(argbToRgba(argb), width: w, height: h),
        kotlinReference(argb, w, h),
        reason: '${w}x$h',
      );
    }
  });

  test('ngưỡng xám 200 và alpha 50', () {
    int px(int a, int g) => (a << 24) | (g << 16) | (g << 8) | g;
    // 199 cháy, 200 không; alpha 50 bỏ qua, 51 tính.
    final argb = [px(255, 199), px(255, 200), px(50, 0), px(51, 0)];
    final out = EscPosRaster.encodeRgba(argbToRgba(argb), width: 4, height: 1);
    expect(out, [0x1D, 0x76, 0x30, 0x00, 1, 0, 1, 0, 0x80 | 0x10]);
  });

  test('chia dải 128 dòng, khai báo đúng kích thước', () {
    final out = EscPosRaster.encodeRgba(
      Uint8List(10 * 300 * 4),
      width: 10,
      height: 300,
    );
    // 300 dòng = 128 + 128 + 44; mỗi dòng 2 byte.
    expect(out.length, 3 * 8 + 300 * 2);
    expect(out.sublist(0, 8), [0x1D, 0x76, 0x30, 0, 2, 0, 128, 0]);
    expect(out.sublist(8 + 256, 8 + 256 + 8), [
      0x1D,
      0x76,
      0x30,
      0,
      2,
      0,
      128,
      0,
    ]);
    expect(out.sublist(2 * (8 + 256), 2 * (8 + 256) + 8), [
      0x1D,
      0x76,
      0x30,
      0,
      2,
      0,
      44,
      0,
    ]);
  });

  test('giải mã PNG rồi mã hoá', () {
    final image = img.Image(width: 16, height: 2, numChannels: 4)
      ..clear(img.ColorRgba8(255, 255, 255, 255));
    image.setPixel(0, 0, img.ColorRgba8(0, 0, 0, 255));
    image.setPixel(15, 1, img.ColorRgba8(0, 0, 0, 255));
    final out = EscPosRaster.encodeImageBytes(img.encodePng(image))!;
    expect(out, [0x1D, 0x76, 0x30, 0, 2, 0, 2, 0, 0x80, 0, 0, 0x01]);
    expect(
      EscPosRaster.encodeImageBytes(Uint8List.fromList([1, 2, 3])),
      isNull,
    );
  });

  test('khung hoá đơn và nhiều bản liền nhau', () {
    final raster = Uint8List.fromList([9, 9]);
    final one = [
      0x1B, 0x40, 0x1B, 0x61, 0x01, 9, 9, //
      0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x42, 0x01,
    ];
    expect(EscPosCommands.receipt(raster), one);
    expect(EscPosCommands.receipt(raster, copies: 3), [...one, ...one, ...one]);
  });

  test('đọc trạng thái giấy giống bản native', () {
    expect(PaperStatus.parse(), PaperStatus.unknown);
    expect(PaperStatus.parse(roll: 0x12), PaperStatus.ok);
    expect(PaperStatus.parse(roll: 0x12 | 0x0C), PaperStatus.nearEnd);
    expect(PaperStatus.parse(roll: 0x12 | 0x60), PaperStatus.paperEnd);
    expect(
      PaperStatus.parse(roll: 0x12, offline: 0x12 | 0x20),
      PaperStatus.paperEnd,
    );
    expect(
      PaperStatus.parse(roll: 0x12 | 0x60, offline: 0x12 | 0x04),
      PaperStatus.coverOpen,
    );
    expect(PaperStatus.isStatusByte(0x12), isTrue);
    expect(PaperStatus.isStatusByte(0x13), isFalse);
  });
}
