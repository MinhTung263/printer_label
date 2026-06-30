import 'dart:typed_data';
import 'dart:ui' as ui;

import '../enums/enum.src.dart';

const int _defaultPrinterDpi = 203;

/// Resizes an image based on specified millimeter dimensions.
Future<Uint8List> resizeImage({
  required Uint8List imageBytes,
  required CupStickerSize size,
  int dpi = _defaultPrinterDpi,

  /// Padding on each edge (in millimeters)
  double? paddingMm,
}) async {
  final int targetWidthPx = mmToPx(size.widthMm, dpi: dpi);
  final int targetHeightPx = mmToPx(size.heightMm, dpi: dpi);

  final int paddingPx = mmToPx(paddingMm ?? 2, dpi: dpi);

  /// Dimensions of the inner content area (excluding padding)
  final int contentWidthPx =
      (targetWidthPx - paddingPx * 2).clamp(1, targetWidthPx);
  final int contentHeightPx =
      (targetHeightPx - paddingPx * 2).clamp(1, targetHeightPx);

  /// Resizes the original image to fit within the content area
  final codec = await ui.instantiateImageCodec(
    imageBytes,
    targetWidth: contentWidthPx,
    targetHeight: contentHeightPx,
  );

  final frame = await codec.getNextFrame();
  final ui.Image contentImage = frame.image;

  /// Creates a canvas representing the full sticker size
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  /// Draws a white background
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

  /// Draws the resized image centered with padding
  canvas.drawImage(
    contentImage,
    ui.Offset(paddingPx.toDouble(), paddingPx.toDouble()),
    ui.Paint(),
  );

  /// Exports the final rasterized image bytes
  final picture = recorder.endRecording();
  final image = await picture.toImage(targetWidthPx, targetHeightPx);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  return byteData!.buffer.asUint8List();
}

/// Converts millimeters to pixels based on the specified DPI
int mmToPx(double mm, {int dpi = _defaultPrinterDpi}) {
  return (mm * dpi / 25.4).round();
}

/// Resizes a thermal receipt image to the exact pixel width of the target paper size.
/// - mm58 (K57/K58) -> 384 px width
/// - mm80 (K80) -> 576 px width
Future<Uint8List> resizeThermalImage({
  required Uint8List imageBytes,
  required TicketSize size,
}) async {
  final int targetWidth = size.value;

  // Sử dụng ui.instantiateImageCodec để giải mã và scale ảnh ở tầng C++ (rất nhanh và mượt)
  final codec = await ui.instantiateImageCodec(
    imageBytes,
    targetWidth: targetWidth,
  );

  final frame = await codec.getNextFrame();
  final ui.Image contentImage = frame.image;

  // Vẽ ảnh lên canvas với nền trắng để loại bỏ các kênh trong suốt (transparent) dễ gây lỗi in
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
  
  canvas.drawRect(
    ui.Rect.fromLTWH(
      0,
      0,
      targetWidth.toDouble(),
      contentImage.height.toDouble(),
    ),
    paint,
  );

  canvas.drawImage(contentImage, ui.Offset.zero, ui.Paint());

  final picture = recorder.endRecording();
  final finalImage = await picture.toImage(targetWidth, contentImage.height);
  final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);

  return byteData!.buffer.asUint8List();
}
