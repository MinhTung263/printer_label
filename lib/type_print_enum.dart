enum TypePrintEnum {
  single,
  double;

  static const Map<TypePrintEnum, Map<String, int>> dimensions = {
    TypePrintEnum.single: {'width': 240, 'height': 170},
    TypePrintEnum.double: {'width': 360, 'height': 200},
  };

  int get width => dimensions[this]!['width']!;
  int get height => dimensions[this]!['height']!;
}
