class LabelPerRow {
  final String name;
  final _LabelConfig _config;

  const LabelPerRow._internal(this.name, this._config);

  // Các instance giống enum
  static const single = LabelPerRow._internal(
      'single', _LabelConfig(width: 50, height: 30, gap: 2));
  static const single35x22 = LabelPerRow._internal(
      'single_35_22', _LabelConfig(width: 35, height: 22, gap: 2));
  static const single40x30 = LabelPerRow._internal(
      'single_40_30', _LabelConfig(width: 40, height: 30, gap: 2));
  static const single58x40 = LabelPerRow._internal(
      'single_58_40', _LabelConfig(width: 58, height: 40, gap: 2));
  static const single60x80 = LabelPerRow._internal(
      'single_60_80', _LabelConfig(width: 60, height: 80, gap: 2));
  static const single70x30 = LabelPerRow._internal(
      'single_70_30', _LabelConfig(width: 70, height: 30, gap: 2));
  static const single100x100 = LabelPerRow._internal(
      'single_100_100', _LabelConfig(width: 100, height: 100, gap: 2));
  static const single100x150 = LabelPerRow._internal(
      'single_100_150', _LabelConfig(width: 100, height: 150, gap: 2));
  static const single102x152 = LabelPerRow._internal(
      'single_102_152', _LabelConfig(width: 102, height: 152, gap: 2));

  static const doubleLabels = LabelPerRow._internal(
      'double', _LabelConfig(width: 72, height: 22, gap: 1));
  static const double38x25 = LabelPerRow._internal(
      'double_38_25', _LabelConfig(width: 81, height: 25, gap: 1));
  static const double40x30 = LabelPerRow._internal(
      'double_40_30', _LabelConfig(width: 85, height: 30, gap: 1));
  static const double46x34 = LabelPerRow._internal(
      'double_46_34', _LabelConfig(width: 97, height: 34, gap: 1));
  static const double50x30 = LabelPerRow._internal(
      'double_50_30', _LabelConfig(width: 105, height: 30, gap: 1));
  static const double50x50 = LabelPerRow._internal(
      'double_50_50', _LabelConfig(width: 105, height: 50, gap: 1));
  static const triple = LabelPerRow._internal(
      'triple', _LabelConfig(width: 110, height: 22, gap: 0));
  static const triple30x30 = LabelPerRow._internal(
      'triple_30_30', _LabelConfig(width: 101, height: 30, gap: 0));
  static const triple35x25 = LabelPerRow._internal(
      'triple_35_25', _LabelConfig(width: 112, height: 25, gap: 0));
  static const triple26x26 = LabelPerRow._internal(
      'triple_26_26', _LabelConfig(width: 85, height: 26, gap: 0));
  static const values = [
    single,
    single35x22,
    single40x30,
    single58x40,
    single60x80,
    single70x30,
    single100x100,
    single100x150,
    single102x152,
    doubleLabels,
    double38x25,
    double40x30,
    double46x34,
    double50x30,
    double50x50,
    triple,
    triple30x30,
    triple35x25,
    triple26x26,
  ];

  /// Tìm khổ tem theo [name] đã lưu (VD 'single_40_30'); trả null nếu không khớp.
  static LabelPerRow? fromName(String? name) {
    if (name == null) return null;
    for (final e in values) {
      if (e.name == name) return e;
    }
    return null;
  }

  // Lấy thông tin
  int? get width => _config.width;
  int? get height => _config.height;
  int? get gap => _config.gap;

  int get count =>
      name.startsWith('double') ? 2 : (name.startsWith('triple') ? 3 : 1);

  String get title => switch (name) {
        'single' => '50x30mm (Mặc định)',
        'single_35_22' => '35x22mm',
        'single_40_30' => '40x30mm',
        'single_58_40' => '58x40mm',
        'single_60_80' => '60x80mm',
        'single_70_30' => '70x30mm',
        'single_100_100' => '100x100mm',
        'single_100_150' => '100x150mm',
        'single_102_152' => '102x152mm',
        'double' => '35x22mm (Mặc định)',
        'double_38_25' => '38x25mm',
        'double_40_30' => '40x30mm',
        'double_46_34' => '46x34mm',
        'double_50_30' => '50x30mm',
        'double_50_50' => '50x50mm',
        'triple' => '35x22mm (Mặc định)',
        'triple_30_30' => '30x30mm',
        'triple_35_25' => '35x25mm',
        'triple_26_26' => '26x26mm',
        _ => '',
      };

  double get stampWidth => switch (name) {
        'single' => 50.0,
        'single_35_22' => 35.0,
        'single_40_30' => 40.0,
        'single_58_40' => 58.0,
        'single_60_80' => 60.0,
        'single_70_30' => 70.0,
        'single_100_100' => 100.0,
        'single_100_150' => 100.0,
        'single_102_152' => 102.0,
        'double' => 35.0,
        'double_38_25' => 38.0,
        'double_40_30' => 40.0,
        'double_46_34' => 46.0,
        'double_50_30' => 50.0,
        'double_50_50' => 50.0,
        'triple' => 35.0,
        'triple_30_30' => 30.0,
        'triple_35_25' => 35.0,
        'triple_26_26' => 26.0,
        _ => 35.0,
      };

  double get stampHeight => height?.toDouble() ?? 22.0;

  // copyWith trả về LabelPerRow mới với config tùy chỉnh
  LabelPerRow copyWith({
    int? width,
    int? height,
    int? gap,
  }) {
    return LabelPerRow._internal(
      name,
      _config.copyWith(width: width, height: height, gap: gap),
    );
  }
}

class _LabelConfig {
  final int? width;
  final int? height;
  final int? gap;

  const _LabelConfig({this.width, this.height, this.gap});

  _LabelConfig copyWith({int? width, int? height, int? gap}) {
    return _LabelConfig(
      width: width ?? this.width,
      height: height ?? this.height,
      gap: gap ?? this.gap,
    );
  }
}
