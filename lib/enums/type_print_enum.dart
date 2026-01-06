class Dimensions {
  final double width;
  final double height;
  final double barcodeHeight;
  final double fontSize;

  const Dimensions({
    required this.width,
    required this.height,
    required this.barcodeHeight,
    required this.fontSize,
  });

  /// Preset mặc định
  static const defaultDimens = Dimensions(
    width: 230,
    height: 180,
    barcodeHeight: 70,
    fontSize: 16,
  );

  /// Sau này thêm preset mới rất dễ
  static const small = Dimensions(
    width: 180,
    height: 140,
    barcodeHeight: 55,
    fontSize: 14,
  );

  static const large = Dimensions(
    width: 230,
    height: 220,
    barcodeHeight: 100,
    fontSize: 20,
  );
}
