class LabelPerRow {
  final String name;
  final _LabelConfig _config;

  const LabelPerRow._internal(this.name, this._config);

  // Các instance giống enum
  static const one = LabelPerRow._internal(
      'one', _LabelConfig(x: 20, y: 0, width: 40, height: 25));
  static const two = LabelPerRow._internal(
      'two', _LabelConfig(x: 60, y: 0, width: 80, height: 20));
  static const three = LabelPerRow._internal(
      'three', _LabelConfig(x: 0, y: 0, width: 100, height: 20));

  static const values = [one, two, three];

  // Lấy thông tin
  int? get x => _config.x;
  int? get y => _config.y;
  int? get width => _config.width;
  int? get height => _config.height;

  int get count => values.indexOf(this) + 1;

  String get title => switch (name) {
        'one' => 'Print 1 tem / row',
        'two' => 'Print 2 tem / row',
        'three' => 'Print 3 tem / row',
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
