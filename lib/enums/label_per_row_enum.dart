enum LabelPerRow {
  one,
  two,
  three,
}

class _LabelConfig {
  final int? x;
  final int? y;
  final int? width;
  final int? height;

  const _LabelConfig({
    this.x,
    this.y,
    this.width,
    this.height,
  });
}

extension LabelPerRowExt on LabelPerRow {
  static const _configs = {
    LabelPerRow.one: _LabelConfig(x: 20, y: 0, width: 40, height: 25),
    LabelPerRow.two: _LabelConfig(x: 60, y: 0, width: 80, height: 20),
    LabelPerRow.three: _LabelConfig(x: 0, y: 0, width: 100, height: 20),
  };

  _LabelConfig get _config => _configs[this]!;

  int get count => index + 1;

  String get title => switch (this) {
        LabelPerRow.one => 'In 1 tem / hàng',
        LabelPerRow.two => 'In 2 tem / hàng',
        LabelPerRow.three => 'In 3 tem / hàng',
      };

  int? get x => _config.x;
  int? get y => _config.y;
  int? get width => _config.width;
  int? get height => _config.height;
}
