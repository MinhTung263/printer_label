import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'label_calibration.dart';
import 'schematic_tem_layout.dart';

/// Tem thử căn chỉnh: khung viền sát mép tem + dấu thập chính giữa + thước mm
/// (vạch mỗi 1mm, dài mỗi 5mm, số mỗi 10mm) dọc cạnh trên và cạnh trái + dòng ghi
/// khổ và độ chỉnh đang áp. In ra rồi nhìn: khung bị cắt mép nào / thừa lề nào thì
/// chỉnh [LabelCalibration] ngược lại tới khi khung nằm đúng mép tem.
abstract final class LabelCalibrationImage {
  static const int dotsPerMm = 8;

  /// Ảnh PNG đen trắng cho tem rộng [widthMm] x cao [heightMm].
  ///
  /// [labelsPerRow] khác `null`: vẽ tem MẪU giống hình xem trước trên màn Agent (khung,
  /// hai thanh chữ, mã vạch) thay cho thước và dấu thập; [temWidthMm] là bề rộng MỘT tem (không có thì chia đều cả hàng).
  static Uint8List png({
    required int widthMm,
    required int heightMm,
    LabelCalibration calibration = LabelCalibration.none,
    int? labelsPerRow,
    int? temWidthMm,
  }) {
    final w = widthMm * dotsPerMm;
    final h = heightMm * dotsPerMm;
    final image = img.Image(width: w, height: h, numChannels: 3)
      ..clear(img.ColorRgb8(255, 255, 255));
    final black = img.ColorRgb8(0, 0, 0);

    if (labelsPerRow != null) {
      _drawSchematicLabels(
        image,
        count: labelsPerRow.clamp(1, 4),
        temWidthMm: temWidthMm,
        widthMm: widthMm,
        black: black,
      );
      return Uint8List.fromList(img.encodePng(image));
    }

    // Khung sát mép (dày 3 chấm): mép nào bị cắt là nhìn thấy ngay.
    for (var t = 0; t < 3; t++) {
      img.drawRect(
        image,
        x1: t,
        y1: t,
        x2: w - 1 - t,
        y2: h - 1 - t,
        color: black,
      );
    }

    // Thước: vạch mỗi 1mm (ngắn), 5mm (vừa), 10mm (dài + số).
    for (var mm = 1; mm < widthMm; mm++) {
      final x = mm * dotsPerMm;
      final len = mm % 10 == 0 ? 20 : (mm % 5 == 0 ? 14 : 7);
      img.drawLine(image, x1: x, y1: 3, x2: x, y2: 3 + len, color: black);
      if (mm % 10 == 0 && x + 16 < w) {
        img.drawString(
          image,
          '$mm',
          font: img.arial14,
          x: x + 2,
          y: 3 + len + 1,
          color: black,
        );
      }
    }
    for (var mm = 1; mm < heightMm; mm++) {
      final y = mm * dotsPerMm;
      final len = mm % 10 == 0 ? 20 : (mm % 5 == 0 ? 14 : 7);
      img.drawLine(image, x1: 3, y1: y, x2: 3 + len, y2: y, color: black);
      if (mm % 10 == 0 && y + 14 < h) {
        img.drawString(
          image,
          '$mm',
          font: img.arial14,
          x: 3 + len + 2,
          y: y - 7,
          color: black,
        );
      }
    }

    // Dấu thập chính giữa.
    final cx = w ~/ 2;
    final cy = h ~/ 2;
    img.drawLine(image, x1: cx - 24, y1: cy, x2: cx + 24, y2: cy, color: black);
    img.drawLine(image, x1: cx, y1: cy - 24, x2: cx, y2: cy + 24, color: black);

    // Dòng ghi khổ + độ chỉnh (đủ chỗ mới ghi).
    final label =
        '${widthMm}x${heightMm}mm  X${LabelCalibration.format(calibration.offsetXMm)} '
        'Y${LabelCalibration.format(calibration.offsetYMm)}';
    if (h >= 100 && w >= 200) {
      img.drawString(
        image,
        label,
        font: img.arial14,
        x: cx - (label.length * 4),
        y: cy + 30,
        color: black,
      );
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Tem mẫu GIỐNG HÌNH XEM TRƯỚC trên màn hình Agent: khung đen thụt vào khỏi mép tem,
  /// hai thanh chữ (dài + ngắn) và dãy vạch mã vạch — khách đặt tờ in cạnh hình trên màn
  /// hình là thấy ngay tem có lệch không (khung sát / bị cắt một mép = lệch về phía đó).
  /// Bố cục lấy từ [SchematicTemLayout] — cùng nguồn với hình xem trước.
  static void _drawSchematicLabels(
    img.Image image, {
    required int count,
    required int? temWidthMm,
    required int widthMm,
    required img.Color black,
  }) {
    final w = image.width;
    final h = image.height;
    final temW = (temWidthMm ?? (widthMm / count).floor()) * dotsPerMm;
    final gap = count > 1 ? (w - temW * count) ~/ (count - 1) : 0;
    final layout = SchematicTemLayout.of(temW.toDouble(), h.toDouble());
    final stroke = layout.strokeWidth.round().clamp(2, 8);

    void fill(int left, Box b) => img.fillRect(
      image,
      x1: (left + b.left).round(),
      y1: b.top.round(),
      x2: (left + b.right).round() - 1,
      y2: b.bottom.round() - 1,
      color: black,
    );

    for (var i = 0; i < count; i++) {
      final left = i * (temW + gap);
      final f = layout.frame;
      for (var t = 0; t < stroke; t++) {
        img.drawRect(
          image,
          x1: (left + f.left).round() + t,
          y1: f.top.round() + t,
          x2: (left + f.right).round() - 1 - t,
          y2: f.bottom.round() - 1 - t,
          color: black,
        );
      }
      fill(left, layout.bar1);
      fill(left, layout.bar2);
      for (final (x, bw) in layout.bars) {
        fill(
          left,
          Box(x, layout.code.top, x + (bw < 1 ? 1 : bw), layout.code.bottom),
        );
      }
    }
  }
}
