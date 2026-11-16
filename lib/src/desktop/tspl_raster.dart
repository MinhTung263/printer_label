import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Ảnh tem → bitmap 1 bit cho lệnh TSPL `BITMAP`, theo đúng luồng bản Android
/// (`PrinterLabelPlugin.printLabel`): thu / phóng ảnh về ĐÚNG [widthDots] x
/// [heightDots] (8 chấm = 1mm), dịch sang trái [shiftXDots] chấm (bù dải trắng
/// lề trái của widget tem) và dịch dọc [shiftYDots], nền trong suốt coi là trắng,
/// nhị phân hoá theo ngưỡng. Dịch ngay trong ảnh (thêm lề trắng / cắt bớt) nên đúng
/// trên mọi hãng máy in — không phụ thuộc lệnh `REFERENCE` (nhiều máy bỏ qua giá trị âm).
///
/// Quy ước bit của TSPL `BITMAP`: bit 0 = chấm ĐEN (in), bit 1 = trắng. Máy in
/// tem nào ngược quy ước thì truyền `invert: true`.
abstract final class TsplRaster {
  /// Chấm có độ sáng dưới ngưỡng này (0–255) thì in đen.
  static const int threshold = 128;
  static const int _alphaMin = 50;

  /// Bù lề trái của widget tem (giống bản Android: -8 chấm = -1mm).
  static const int defaultShiftX = -8;

  /// Giải mã rồi mã hoá; `null` khi không đọc được ảnh.
  static ({Uint8List bits, int widthBytes})? encodeImageBytes(
    Uint8List bytes, {
    required int widthDots,
    required int heightDots,
    int shiftXDots = defaultShiftX,
    int shiftYDots = 0,
    bool invert = false,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || widthDots <= 0 || heightDots <= 0) return null;
    return encode(
      decoded,
      widthDots: widthDots,
      heightDots: heightDots,
      shiftXDots: shiftXDots,
      shiftYDots: shiftYDots,
      invert: invert,
    );
  }

  static ({Uint8List bits, int widthBytes}) encode(
    img.Image image, {
    required int widthDots,
    required int heightDots,
    int shiftXDots = defaultShiftX,
    int shiftYDots = 0,
    bool invert = false,
  }) {
    final scaled = image.width == widthDots && image.height == heightDots
        ? image
        : img.copyResize(
            image,
            width: widthDots,
            height: heightDots,
            interpolation: img.Interpolation.average,
          );
    // Đã là RGBA 8 bit (PNG có alpha) thì dùng thẳng, không chép lại; ảnh KHÔNG có
    // kênh alpha (JPEG / BMP) thêm kênh alpha đục — không thì cả ảnh bị coi là trong
    // suốt.
    final rgbaImage =
        scaled.format == img.Format.uint8 && scaled.numChannels == 4
        ? scaled
        : (scaled.hasAlpha
              ? scaled.convert(format: img.Format.uint8, numChannels: 4)
              : scaled.convert(
                  format: img.Format.uint8,
                  numChannels: 4,
                  alpha: 255,
                ));
    final rgba = rgbaImage.getBytes(order: img.ChannelOrder.rgba);
    final widthBytes = (widthDots + 7) >> 3;
    // Mọi bit bắt đầu là 1 (trắng); điểm đen xoá bit về 0.
    final bits = Uint8List(widthBytes * heightDots)
      ..fillRange(0, widthBytes * heightDots, 0xFF);
    const grayMax = threshold * 1000;
    // Điểm đích x lấy từ điểm nguồn x - shift: chỉ duyệt đoạn x có nguồn hợp lệ.
    final xStart = shiftXDots > 0 ? shiftXDots : 0;
    final xEnd = shiftXDots < 0 ? widthDots + shiftXDots : widthDots;
    // Dịch dọc: dòng đích y lấy từ dòng nguồn y - shiftY (dương = xuống dưới).
    final yStart = shiftYDots > 0 ? shiftYDots : 0;
    final yEnd = shiftYDots < 0 ? heightDots + shiftYDots : heightDots;
    for (var y = yStart; y < yEnd; y++) {
      final srcRow = (y - shiftYDots) * widthDots * 4;
      final dstRow = y * widthBytes;
      for (var x = xStart; x < xEnd; x++) {
        final p = srcRow + (x - shiftXDots) * 4;
        if (rgba[p + 3] <= _alphaMin) continue; // trong suốt = trắng
        final gray = 299 * rgba[p] + 587 * rgba[p + 1] + 114 * rgba[p + 2];
        if (gray < grayMax) {
          bits[dstRow + (x >> 3)] &= ~(0x80 >> (x & 7)); // đen → bit 0
        }
      }
    }
    // [invert]: máy in tem ngược quy ước → đảo mọi bit (đen thành 1, trắng thành 0).
    if (invert) {
      for (var i = 0; i < bits.length; i++) {
        bits[i] = ~bits[i] & 0xFF;
      }
    }
    return (bits: bits, widthBytes: widthBytes);
  }
}
