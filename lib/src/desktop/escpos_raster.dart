import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Chuyển ảnh hoá đơn thành lệnh raster ESC/POS (`GS v 0`) bằng Dart thuần — KHỚP
/// từng byte với bản native Android (`PrinterThermal.getEscPosRasterBytes`), để máy
/// in nhận đúng dữ liệu như khi in từ app.
///
/// - Điểm cháy khi alpha > 50 và xám < 200, xám = 0.299R + 0.587G + 0.114B (tính
///   bằng số nguyên ×1000). Ngưỡng 200 — KHÔNG hạ về 128: chữ anti-alias sẽ in rất mờ.
/// - Chia ảnh thành nhiều dải tối đa [maxBandRows] dòng: một lệnh quá cao vượt giới
///   hạn raster của máy in (Epson chỉ nhận vài trăm dòng/lệnh) -> in ký tự rác.
abstract final class EscPosRaster {
  /// Số dòng tối đa của một lệnh `GS v 0`.
  static const int maxBandRows = 128;

  static const int _alphaMin = 50;
  static const int _gray1000Max = 200000;

  /// Giải mã PNG/JPEG rồi mã hoá; `null` khi không đọc được ảnh.
  static Uint8List? encodeImageBytes(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    return image == null ? null : encode(image);
  }

  /// Mã hoá [image] thành chuỗi lệnh `GS v 0` (chỉ phần ảnh, chưa có khởi tạo/cắt).
  static Uint8List encode(img.Image image) {
    final width = image.width;
    final height = image.height;
    final rgba = image
        .convert(format: img.Format.uint8, numChannels: 4, alpha: 255)
        .getBytes(order: img.ChannelOrder.rgba);
    return encodeRgba(rgba, width: width, height: height);
  }

  /// Mã hoá điểm ảnh RGBA 8 bit (mỗi điểm 4 byte, hết dòng này tới dòng kia).
  static Uint8List encodeRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) return Uint8List(0);
    if (rgba.length < width * height * 4) {
      throw ArgumentError('Thiếu dữ liệu điểm ảnh: ${rgba.length} byte');
    }
    final widthBytes = (width + 7) >> 3;
    final bits = Uint8List(widthBytes * height);
    for (var y = 0; y < height; y++) {
      final rowPixel = y * width * 4;
      final rowByte = y * widthBytes;
      for (var xByte = 0; xByte < widthBytes; xByte++) {
        var byteVal = 0;
        final x0 = xByte << 3;
        final xEnd = x0 + 8 < width ? x0 + 8 : width;
        for (var x = x0; x < xEnd; x++) {
          final p = rowPixel + x * 4;
          if (rgba[p + 3] > _alphaMin) {
            final gray1000 =
                299 * rgba[p] + 587 * rgba[p + 1] + 114 * rgba[p + 2];
            if (gray1000 < _gray1000Max) byteVal |= 0x80 >> (x - x0);
          }
        }
        bits[rowByte + xByte] = byteVal;
      }
    }

    final bands = (height + maxBandRows - 1) ~/ maxBandRows;
    final out = BytesBuilder(copy: false);
    for (var band = 0; band < bands; band++) {
      final y = band * maxBandRows;
      final rows = height - y < maxBandRows ? height - y : maxBandRows;
      out.add([
        0x1D, 0x76, 0x30, 0x00, //
        widthBytes & 0xFF, widthBytes >> 8,
        rows & 0xFF, rows >> 8,
      ]);
      out.add(
        Uint8List.sublistView(bits, y * widthBytes, (y + rows) * widthBytes),
      );
    }
    return out.takeBytes();
  }
}
