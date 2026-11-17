/// Bố cục của tem mẫu (khung + hai thanh chữ + mã vạch) tính theo tỉ lệ — MỘT nguồn dùng
/// chung cho hình xem trước trên màn hình và ảnh in ra, để hai hình luôn giống nhau.
class SchematicTemLayout {
  const SchematicTemLayout._({
    required this.frame,
    required this.bar1,
    required this.bar2,
    required this.code,
    required this.barcodeUnit,
    required this.strokeWidth,
    this.price,
    this.jewelry = false,
  });

  /// Khung viền thụt vào khỏi mép tem: tỉ lệ so với cạnh ngắn của tem.
  static const double frameInset = 0.14;

  /// Khoảng cách từ khung tới nội dung: tỉ lệ so với cạnh ngắn của khung.
  static const double contentPad = 0.12;

  /// Độ dày nét khung: tỉ lệ so với chiều cao tem.
  static const double strokeRatio = 0.023;

  /// Mã vạch: vạch đậm / mảnh / khe theo đơn vị `bề rộng mã vạch / 110`.
  static const double barcodeUnits = 110;
  static const double thickBar = 3;
  static const double thinBar = 1.6;
  static const double barGap = 1.4;

  /// Tính cho tem rộng [width] × cao [height] (đơn vị tuỳ ý — chấm hoặc điểm ảnh); toạ độ
  /// theo gốc ở góc trái trên của tem.
  ///
  /// [jewelry]: tem vàng bạc, trang sức (nhỏ, dài) — nửa trái là ba thanh chữ (tên, tuổi + trọng
  /// lượng, giá), nửa phải là mã QR vuông thay cho dãy vạch mã vạch.
  factory SchematicTemLayout.of(
    double width,
    double height, {
    bool jewelry = false,
  }) {
    final shortest = width < height ? width : height;
    final inset = shortest * frameInset;
    final frame = Box(inset, inset, width - inset, height - inset);
    final pad =
        (frame.width < frame.height ? frame.width : frame.height) * contentPad;
    final inner = Box(
      frame.left + pad,
      frame.top + pad,
      frame.right - pad,
      frame.bottom - pad,
    );
    if (jewelry) {
      final qrSide = inner.height < inner.width * 0.42
          ? inner.height
          : inner.width * 0.42;
      final textW = inner.width - qrSide - inner.width * 0.06;
      final qr = Box(
        inner.right - qrSide,
        inner.top + (inner.height - qrSide) / 2,
        inner.right,
        inner.top + (inner.height + qrSide) / 2,
      );
      return SchematicTemLayout._(
        frame: frame,
        bar1: Box(
          inner.left,
          inner.top,
          inner.left + textW * 0.9,
          inner.top + inner.height * 0.2,
        ),
        bar2: Box(
          inner.left,
          inner.top + inner.height * 0.34,
          inner.left + textW * 0.6,
          inner.top + inner.height * 0.34 + inner.height * 0.14,
        ),
        price: Box(
          inner.left,
          inner.bottom - inner.height * 0.24,
          inner.left + textW * 0.75,
          inner.bottom,
        ),
        code: qr,
        barcodeUnit: qr.width / 9,
        strokeWidth: height * strokeRatio,
        jewelry: true,
      );
    }
    return SchematicTemLayout._(
      frame: frame,
      bar1: Box(
        inner.left,
        inner.top,
        inner.left + inner.width * 0.7,
        inner.top + inner.height * 0.14,
      ),
      bar2: Box(
        inner.left,
        inner.top + inner.height * 0.24,
        inner.left + inner.width * 0.4,
        inner.top + inner.height * 0.24 + inner.height * 0.12,
      ),
      code: Box(
        inner.left,
        inner.top + inner.height * 0.48,
        inner.right,
        inner.bottom,
      ),
      barcodeUnit: inner.width / barcodeUnits,
      strokeWidth: height * strokeRatio,
    );
  }

  final Box frame;
  final Box bar1;

  /// Thanh giá (chỉ tem vàng bạc); `null` ở tem thường.
  final Box? price;

  /// Tem vàng bạc: [code] là ô mã QR vuông (vẽ bằng [qrCells]) thay cho dãy vạch.
  final bool jewelry;
  final Box bar2;

  /// Vùng mã vạch.
  final Box code;

  /// Một đơn vị bề rộng vạch mã vạch.
  final double barcodeUnit;

  /// Độ dày nét khung.
  final double strokeWidth;

  /// Các ô đen của mã QR mẫu (lưới 9×9: ba góc định vị + vài ô rải đều) — chỉ tem vàng bạc.
  List<Box> get qrCells {
    if (!jewelry) return const [];
    const n = 9;
    final u = code.width / n;
    bool finder(int r, int c) =>
        (r < 3 && c < 3) || (r < 3 && c >= n - 3) || (r >= n - 3 && c < 3);
    final out = <Box>[];
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (finder(r, c) || (r * 7 + c * 3) % 5 < 2) {
          out.add(
            Box(
              code.left + c * u,
              code.top + r * u,
              code.left + (c + 1) * u,
              code.top + (r + 1) * u,
            ),
          );
        }
      }
    }
    return out;
  }

  /// Các vạch đen của mã vạch: danh sách `(x, bề rộng)` trong [code].
  List<(double, double)> get bars {
    if (jewelry) return const [];
    final out = <(double, double)>[];
    var x = code.left;
    var k = 0;
    while (x < code.right) {
      final w = (k % 3 == 0 ? thickBar : thinBar) * barcodeUnit;
      if (k.isEven) {
        final end = x + w > code.right ? code.right : x + w;
        out.add((x, end - x));
      }
      x += w + barGap * barcodeUnit;
      k++;
    }
    return out;
  }
}

/// Hình chữ nhật đơn giản (trái, trên, phải, dưới).
class Box {
  const Box(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
}
