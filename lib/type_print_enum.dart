enum TypePrintEnum {
  singleLabel,
  doubleLabel;

  Dimensions get dimensions {
    switch (this) {
      case TypePrintEnum.singleLabel:
        return const Dimensions(
          width: 360,
          height: 200,
          barcodeHeight: 100,
          fontSize: 20,
        );
      case TypePrintEnum.doubleLabel:
        return const Dimensions(
          width: 230,
          height: 180,
          barcodeHeight: 70,
          fontSize: 16,
        );
    }
  }

  double get width => dimensions.width;
  double get height => dimensions.height;
  double get barcodeHeight => dimensions.barcodeHeight;
  double get fontSize => dimensions.fontSize;
}

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
}
