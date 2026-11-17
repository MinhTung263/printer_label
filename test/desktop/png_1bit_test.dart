import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:printer_label/desktop.dart';

/// PNG 1 bit/điểm (xám) dựng tay giống trang web thử in (`monoPng1Base64`): bit 1 = trắng.
Uint8List _png1bit(int w, int h, bool Function(int x, int y) black) {
  final rb = (w + 7) >> 3;
  final raw = Uint8List((rb + 1) * h);
  for (var y = 0; y < h; y++) {
    final o = y * (rb + 1);
    for (var i = 0; i < rb; i++) {
      raw[o + 1 + i] = 255;
    }
    for (var x = 0; x < w; x++) {
      if (black(x, y)) raw[o + 1 + (x >> 3)] &= ~(0x80 >> (x & 7));
    }
  }
  final out = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length);
    out.add(len.buffer.asUint8List());
    final body = [...type.codeUnits, ...data];
    out.add(body);
    final crc = ByteData(4)..setUint32(0, _crc32(body));
    out.add(crc.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 1)
    ..setUint8(9, 0);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert(raw));
  chunk('IEND', const []);
  return out.toBytes();
}

int _crc32(List<int> b) {
  var c = 0xFFFFFFFF;
  for (final v in b) {
    c ^= v;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void main() {
  bool black(int x, int y) => (x * 7 + y * 3) % 11 < 4 || (x > 50 && x < 60);

  for (final w in [384, 576, 99, 8]) {
    test('PNG 1 bit ${w}px giải mã ra đúng như PNG RGBA cùng hình', () {
      const h = 37;
      final one = _png1bit(w, h, black);
      final rgba = img.Image(width: w, height: h, numChannels: 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = black(x, y) ? 0 : 255;
          rgba.setPixelRgba(x, y, v, v, v, 255);
        }
      }
      final ref = EscPosRaster.encodeImageBytes(
        Uint8List.fromList(img.encodePng(rgba)),
      );
      final got = EscPosRaster.encodeImageBytes(one);
      expect(got, isNotNull, reason: 'Agent phải đọc được PNG 1 bit');
      expect(got, ref);
    });
  }
}
