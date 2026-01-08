class LabelPerRow {
  final String name;
  final _LabelConfig _config;

  const LabelPerRow._internal(this.name, this._config);

  // Các instance giống enum
  static const single = LabelPerRow._internal(
      'single', _LabelConfig(x: 20, y: 0, width: 40, height: 25));
  static const doubleLabels = LabelPerRow._internal(
      'double', _LabelConfig(x: 60, y: 0, width: 80, height: 20));
  static const triple = LabelPerRow._internal(
      'triple', _LabelConfig(x: 0, y: 0, width: 100, height: 20));

  static const values = [single, doubleLabels, triple];

  // Lấy thông tin
  int? get x => _config.x;
  int? get y => _config.y;
  int? get width => _config.width;
  int? get height => _config.height;

  int get count => values.indexOf(this) + 1;

  String get title => switch (name) {
        'single' => 'Print 1 tem / row',
        'double' => 'Print 2 tem / row',
        'triple' => 'Print 3 tem / row',
        _ => '',
      };

  // copyWith trả về LabelPerRow mới với config tùy chỉnh
  LabelPerRow copyWith({
    int? x,
    int? y,
    int? width,
    int? height,
  }) {
    return LabelPerRow._internal(
      name,
      _config.copyWith(x: x, y: y, width: width, height: height),
    );
  }
}

class _LabelConfig {
  final int? x;
  final int? y;
  final int? width;
  final int? height;

  const _LabelConfig({this.x, this.y, this.width, this.height});

  _LabelConfig copyWith({int? x, int? y, int? width, int? height}) {
    return _LabelConfig(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}
