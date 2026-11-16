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
  factory SchematicTemLayout.of(double width, double height) {
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
  final Box bar2;

  /// Vùng mã vạch.
  final Box code;

  /// Một đơn vị bề rộng vạch mã vạch.
  final double barcodeUnit;

  /// Độ dày nét khung.
  final double strokeWidth;

  /// Các vạch đen của mã vạch: danh sách `(x, bề rộng)` trong [code].
  List<(double, double)> get bars {
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
