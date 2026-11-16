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

  int get widthDots => widthMm * 8;
  int get heightDots => heightMm * 8;
}
