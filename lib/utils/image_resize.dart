import 'dart:typed_data';
import 'dart:ui' as ui;

/// DPI phổ biến của máy in nhiệt
/// 203 DPI = 8 dot / mm
/// 300 DPI = 12 dot / mm
const int _defaultPrinterDpi = 203;

/// Resize image theo kích thước mm (CHUẨN IN NHIỆT)
Future<Uint8List> resizeImage({
  required Uint8List imageBytes,
  required double widthMm,
  required double heightMm,
  int dpi = _defaultPrinterDpi,
}) async {
  final codec = await ui.instantiateImageCodec(
    imageBytes,
    targetWidth: _mmToPx(widthMm, dpi),
    targetHeight: _mmToPx(heightMm, dpi),
  );

  final frame = await codec.getNextFrame();
  final ui.Image image = frame.image;

  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  return byteData!.buffer.asUint8List();
}

/// Convert millimeter → pixel theo DPI
int _mmToPx(double mm, int dpi) {
  return ((mm / 25.4) * dpi).round();
}
