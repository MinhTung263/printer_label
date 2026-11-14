import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Thu gọn ảnh in trước khi gửi qua máy Agent.
///
/// Máy in nhiệt chỉ in đen / trắng: khi in, ảnh được nhị phân hoá theo đúng quy
/// tắc "điểm đen khi alpha > 50 và xám < 200" (xám = 0.299R + 0.587G + 0.114B —
/// `getEscPosRasterBytes` Android, `binarized(threshold: 200)` iOS). Làm bước đó
/// NGAY trên máy gửi thì bản in giữ nguyên, còn ảnh PNG chỉ còn 2 màu nén rất
/// tốt (chữ khử răng cưa nhiều sắc xám làm PNG phình to: hoá đơn ~1,4MB).
abstract final class PrintRelayImage {
  /// Ảnh [png] đã đổi sang đen / trắng (PNG). Lỗi hoặc không nhỏ hơn thì trả lại
  /// ảnh gốc.
  static Future<Uint8List> compact(Uint8List png) async {
    final sw = Stopwatch()..start();
    final marks = <String>[];
    void mark(String name) => marks.add('$name ${sw.elapsedMilliseconds}');
    try {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final source = frame.image;
      final width = source.width;
      final height = source.height;
      final raw = await source.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      source.dispose();
      codec.dispose();
      mark('giải mã');
      if (raw == null) return png;
      // Ngay trên isolate chính (KHÔNG dùng compute: mỗi lần tạo isolate mới —
      // bản debug có trình gỡ lỗi gắn vào thì mỗi isolate bị dừng chờ cài điểm
      // dừng, đo được ~10s cho một lệnh tem). Chia nhỏ để UI không khựng.
      final mono = await _binarize(raw.buffer.asUint8List());
      mark('đen trắng');
      final buffer = await ui.ImmutableBuffer.fromUint8List(mono);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final monoCodec = await descriptor.instantiateCodec();
      final monoFrame = await monoCodec.getNextFrame();
      final encoded = await monoFrame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      monoFrame.image.dispose();
      monoCodec.dispose();
      descriptor.dispose();
      buffer.dispose();
      mark('mã hoá');
      debugPrint('[PRINT-RELAY][IMG] ${width}x$height: ${marks.join(', ')}ms');
      if (encoded == null) return png;
      final bytes = encoded.buffer.asUint8List();
      return bytes.length < png.length ? bytes : png;
    } catch (_) {
      return png;
    }
  }

  /// Mỗi đợt duyệt chừng ấy điểm ảnh rồi nhường một nhịp cho UI.
  static const int _chunk = 1 << 18;

  /// Đen / trắng (alpha 255) — cùng quy tắc với máy in. Đọc / ghi mỗi điểm ảnh
  /// một lần (32 bit) thay vì từng byte.
  static Future<Uint8List> _binarize(Uint8List px) async {
    if (Endian.host != Endian.little) return _binarizeBytes(px);
    final words = px.buffer.asUint32List(px.offsetInBytes, px.length >> 2);
    const black = 0xFF000000;
    const white = 0xFFFFFFFF;
    for (var start = 0; start < words.length; start += _chunk) {
      final end = start + _chunk < words.length ? start + _chunk : words.length;
      for (var i = start; i < end; i++) {
        final v = words[i];
        // Little-endian: byte 0 = R, 1 = G, 2 = B, 3 = A.
        words[i] =
            (v >>> 24) > 50 &&
                299 * (v & 0xFF) +
                        587 * ((v >> 8) & 0xFF) +
                        114 * ((v >> 16) & 0xFF) <
                    200000
            ? black
            : white;
      }
      if (end < words.length) await Future<void>.delayed(Duration.zero);
    }
    return px;
  }

  /// Bản dự phòng (máy big-endian — gần như không có).
  static Uint8List _binarizeBytes(Uint8List px) {
    for (var i = 0; i + 3 < px.length; i += 4) {
      final black =
          px[i + 3] > 50 &&
          299 * px[i] + 587 * px[i + 1] + 114 * px[i + 2] < 200000;
      final v = black ? 0 : 255;
      px[i] = v;
      px[i + 1] = v;
      px[i + 2] = v;
      px[i + 3] = 255;
    }
    return px;
  }
}
