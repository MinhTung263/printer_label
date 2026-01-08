import 'dart:typed_data';
import 'dart:ui' as ui;

import '../enums/enum.src.dart';

const int _defaultPrinterDpi = 203;

/// Resize image theo kích thước mm
Future<Uint8List> resizeImage({
  required Uint8List imageBytes,
  required CupStickerSize size,
  int dpi = _defaultPrinterDpi,

  /// padding mỗi cạnh (mm)
  double? paddingMm,
}) async {
  final int targetWidthPx = mmToPx(size.widthMm, dpi: dpi);
  final int targetHeightPx = mmToPx(size.heightMm, dpi: dpi);

  final int paddingPx = mmToPx(paddingMm ?? 2, dpi: dpi);

  /// Kích thước ảnh bên trong (trừ padding)
  final int contentWidthPx =
      (targetWidthPx - paddingPx * 2).clamp(1, targetWidthPx);
  final int contentHeightPx =
      (targetHeightPx - paddingPx * 2).clamp(1, targetHeightPx);

  /// Resize ảnh gốc vào vùng content
  final codec = await ui.instantiateImageCodec(
    imageBytes,
    targetWidth: contentWidthPx,
    targetHeight: contentHeightPx,
  );

  final frame = await codec.getNextFrame();
  final ui.Image contentImage = frame.image;

  /// Tạo canvas full size tem
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  /// Nền trắng
  final paint = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
  canvas.drawRect(
    ui.Rect.fromLTWH(
      0,
      0,
      targetWidthPx.toDouble(),
      targetHeightPx.toDouble(),
    ),
    paint,
  );

  /// Vẽ ảnh đã resize vào giữa (có padding)
  canvas.drawImage(
    contentImage,
    ui.Offset(paddingPx.toDouble(), paddingPx.toDouble()),
    ui.Paint(),
  );

  /// Xuất ảnh
  final picture = recorder.endRecording();
  final image = await picture.toImage(targetWidthPx, targetHeightPx);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  return byteData!.buffer.asUint8List();
}

/// Convert millimeter → pixel theo DPI
int mmToPx(double mm, {int dpi = _defaultPrinterDpi}) {
  return (mm * dpi / 25.4).round();
}
