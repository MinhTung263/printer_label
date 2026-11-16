/// Độ chỉnh tem in lệch (mm) — dùng chung cho mọi nền tảng: mỗi máy in tem, mỗi
/// hệ điều hành hay mỗi cuộn tem lệch một ít, nên người dùng chỉnh MỘT lần (dựa
/// vào tem thử [LabelCalibrationImage]) rồi mọi tem sau in đúng chỗ.
///
/// Dương = dời nội dung sang PHẢI / xuống DƯỚI.
class LabelCalibration {
  const LabelCalibration({this.offsetXMm = 0, this.offsetYMm = 0});

  /// Giới hạn chỉnh (mm) — quá xa là nhập nhầm.
  static const double maxMm = 20;

  /// Một nấc chỉnh (mm).
  static const double stepMm = 0.5;

  static const LabelCalibration none = LabelCalibration();

  final double offsetXMm;
  final double offsetYMm;

  bool get isZero => offsetXMm == 0 && offsetYMm == 0;

  /// Dời gốc toạ độ theo chấm (8 chấm = 1mm, máy in tem 203dpi).
  int get offsetXDots => (offsetXMm * 8).round();
  int get offsetYDots => (offsetYMm * 8).round();

  LabelCalibration copyWith({double? offsetXMm, double? offsetYMm}) =>
      LabelCalibration(
        offsetXMm: _clamp(offsetXMm ?? this.offsetXMm),
        offsetYMm: _clamp(offsetYMm ?? this.offsetYMm),
      );

  /// Chỉnh thêm [dx] / [dy] mm (làm tròn theo [stepMm]).
  LabelCalibration nudge({double dx = 0, double dy = 0}) => copyWith(
    offsetXMm: _snap(offsetXMm + dx),
    offsetYMm: _snap(offsetYMm + dy),
  );

  static double _clamp(double v) => v.clamp(-maxMm, maxMm).toDouble();

  static double _snap(double v) => (v / stepMm).round() * stepMm;

  Map<String, Object?> toMap() => {'x': offsetXMm, 'y': offsetYMm};

  /// Đọc từ bộ nhớ; sai / thiếu = không chỉnh.
  static LabelCalibration fromMap(Object? raw) {
    if (raw is! Map) return none;
    double n(Object? v) => v is num ? _clamp(v.toDouble()) : 0;
    return LabelCalibration(offsetXMm: n(raw['x']), offsetYMm: n(raw['y']));
  }

  /// "+1.5" / "-0.5" / "0" — hiện cho người dùng.
  static String format(double mm) => mm == 0
      ? '0'
      : '${mm > 0 ? '+' : ''}${mm.toStringAsFixed(mm % 1 == 0 ? 0 : 1)}';

  @override
  bool operator ==(Object other) =>
      other is LabelCalibration &&
      other.offsetXMm == offsetXMm &&
      other.offsetYMm == offsetYMm;

  @override
  int get hashCode => Object.hash(offsetXMm, offsetYMm);

  @override
  String toString() =>
      'LabelCalibration(x: ${format(offsetXMm)}mm, y: ${format(offsetYMm)}mm)';
}
