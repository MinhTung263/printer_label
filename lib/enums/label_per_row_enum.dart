import 'dart:io';

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
  static final bool _isIOS = Platform.isIOS;

  static const _androidConfig = {
    LabelPerRow.one: _LabelConfig(x: 40, y: 0, width: 40, height: 25),
    LabelPerRow.two: _LabelConfig(x: 60, y: 0, width: 80, height: 20),
    LabelPerRow.three: _LabelConfig(x: 10, y: 0, width: 110, height: 20),
  };
  static const _defaultIosConfig = _LabelConfig(x: null, y: null);
  static const _iosConfig = {
    LabelPerRow.one: _defaultIosConfig,
    LabelPerRow.two: _LabelConfig(x: 170, y: null),
    LabelPerRow.three: _defaultIosConfig,
  };

  _LabelConfig get _config =>
      _isIOS ? _iosConfig[this]! : _androidConfig[this]!;

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
