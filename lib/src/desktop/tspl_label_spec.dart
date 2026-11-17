import '../enums/label_per_row_enum.dart';
import 'tspl_raster.dart';

/// Khổ một hàng tem để in TSPL: kích thước thật (mm), khe, có dò khe `HOME` không,
/// dịch ảnh sang trái bao nhiêu chấm.
class TsplLabelSpec {
  const TsplLabelSpec({
    required this.widthMm,
    required this.heightMm,
    this.gapMm = 2,
    this.home = false,
    this.shiftXDots = TsplRaster.defaultShiftX,
    this.dpi = 203,
    this.ribbon,
  });

  /// Từ khổ tem của app ([LabelPerRow]); `null` khi khổ thiếu kích thước.
  static TsplLabelSpec? fromLabelPerRow(LabelPerRow size) {
    final w = size.width;
    final h = size.height;
    if (w == null || h == null) return null;
    return TsplLabelSpec(
      widthMm: w,
      heightMm: h,
      gapMm: size.gap ?? 2,
      home: size.useHome,
    );
  }

  final int widthMm;
  final int heightMm;
  final num gapMm;
  final bool home;

  /// Dịch ảnh theo chiều ngang (chấm); mặc định -8 như bản Android (bù lề widget).
  final int shiftXDots;

  /// Độ phân giải đầu in: 203 (tem trà sữa / F&B) hoặc 300 (tem vàng bạc, trang sức).
  final int dpi;

  /// Máy in truyền nhiệt dùng ruy-băng mực: `true` → gửi `SET RIBBON ON`, `false` → `SET RIBBON
  /// OFF`; `null` = không gửi gì (giữ cách cũ — máy in nhiệt trực tiếp không cần).
  final bool? ribbon;

  /// Máy tem vàng bạc, trang sức: đầu in 300dpi hoặc dùng ruy-băng mực (tem trà sữa / F&B là
  /// 203dpi, in nhiệt trực tiếp). Hình tem mẫu và tem thử vẽ theo kiểu này.
  bool get isJewelry => dpi >= 300 || ribbon == true;

  /// Số chấm trên 1mm: 8 ở 203dpi, ~11,81 ở 300dpi.
  double get dotsPerMm => dpi >= 300 ? 300 / 25.4 : 8;

  int get widthDots => (widthMm * dotsPerMm).round();
  int get heightDots => (heightMm * dotsPerMm).round();

  /// Dịch ngang theo chấm của đầu in này ([shiftXDots] tính ở 203dpi: 8 chấm = 1mm).
  int get scaledShiftXDots => (shiftXDots * dotsPerMm / 8).round();

  TsplLabelSpec copyWith({
    int? widthMm,
    int? heightMm,
    num? gapMm,
    bool? home,
    int? shiftXDots,
    int? dpi,
    bool? ribbon,
  }) => TsplLabelSpec(
    widthMm: widthMm ?? this.widthMm,
    heightMm: heightMm ?? this.heightMm,
    gapMm: gapMm ?? this.gapMm,
    home: home ?? this.home,
    shiftXDots: shiftXDots ?? this.shiftXDots,
    dpi: dpi ?? this.dpi,
    ribbon: ribbon ?? this.ribbon,
  );
}
