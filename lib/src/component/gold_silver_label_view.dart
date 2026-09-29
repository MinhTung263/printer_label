import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

/// Dữ liệu cho 1 tem vàng bạc (dạng tem "cờ đuôi nheo" - nhẫn/trang sức).
///
/// Layout tham chiếu (xem ảnh mẫu):
/// ```
/// CTY TNHH TMDV        NHẪN
/// VÀNG THIÊN TẠO       TKL: 0c5p07
/// |||barcode|||        KLH: 0c1p2
/// N02951 HLV:610       KLV: 0.387
///                      TC:  315.000 VNĐ
/// ```
class GoldSilverLabelModel {
  /// Tên công ty, hiển thị tối đa 2 dòng ở góc trên-trái (VD: "CTY TNHH TMDV", "VÀNG THIÊN TẠO").
  final String companyLine1;
  final String companyLine2;

  /// Loại trang sức, hiển thị ở góc trên-phải (VD: "NHẪN", "LẮC", "DÂY CHUYỀN").
  final String productType;

  /// Dữ liệu mã vạch (in bên dưới tên công ty).
  final String barcodeData;

  /// Text hiển thị dưới mã vạch (VD: "N02951 HLV:610").
  final String barcodeCaption;

  /// TKL: Tuổi/Trọng lượng kim loại (VD: "0c5p07").
  final String tkl;

  /// KLH: Khối lượng hột (VD: "0c1p2").
  final String klh;

  /// KLV: Khối lượng vàng (VD: "0.387").
  final String klv;

  /// TC: Thành tiền (VD: "315.000 VNĐ").
  final String tc;

  const GoldSilverLabelModel({
    required this.companyLine1,
    required this.companyLine2,
    required this.productType,
    required this.barcodeData,
    required this.barcodeCaption,
    required this.tkl,
    required this.klh,
    required this.klv,
    required this.tc,
  });
}

/// Widget preview/render tem vàng bạc, khổ 42mm (rộng) x 10mm (cao phần in),
/// theo đúng layout tem thực tế: cột trái là thông tin công ty + mã vạch,
/// cột phải là loại trang sức + các chỉ số TKL/KLH/KLV/TC.
///
/// Đây CHỈ là vùng nội dung có chữ (10mm cao) — decal thật còn có đuôi nhọn
/// dài thêm 30mm (không in gì) để xỏ/buộc. Dùng [GoldSilverLabelCanvas] khi
/// cần render/gửi in đúng toàn bộ khổ giấy vật lý (bao gồm phần đuôi).
class GoldSilverLabelView extends StatelessWidget {
  const GoldSilverLabelView({
    super.key,
    required this.data,
    this.widthMm = 42.0,
    this.heightMm = 10.0,
  });

  final GoldSilverLabelModel data;
  final double widthMm;
  final double heightMm;

  static const double _pxPerMm = 12.0;

  double get widthPx => widthMm * _pxPerMm;
  double get heightPx => heightMm * _pxPerMm;

  @override
  Widget build(BuildContext context) {
    final double fontSize = heightPx * 0.16;
    final double barcodeHeight = heightPx * 0.34;

    return Container(
      color: Colors.white,
      width: widthPx,
      height: heightPx,
      padding: EdgeInsets.symmetric(horizontal: widthPx * 0.02),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Cột trái: Công ty + mã vạch ─────────────────────────
          Expanded(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _text(data.companyLine1, fontSize: fontSize, bold: false),
                  _text(data.companyLine2, fontSize: fontSize, bold: false),
                  SizedBox(height: heightPx * 0.02),
                  BarcodeWidget(
                    barcode: Barcode.code93(),
                    data: data.barcodeData,
                    width: widthPx * 0.55,
                    height: barcodeHeight,
                    drawText: false,
                    margin: EdgeInsets.zero,
                  ),
                  _text(data.barcodeCaption,
                      fontSize: fontSize * 0.9, bold: false),
                ],
              ),
            ),
          ),
          SizedBox(width: widthPx * 0.02),
          // ── Cột phải: Loại SP + chỉ số ───────────────────────────
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _text(data.productType, fontSize: fontSize, bold: true),
                  _labelRow('TKL:', data.tkl, fontSize),
                  _labelRow('KLH:', data.klh, fontSize),
                  _labelRow('KLV:', data.klv, fontSize),
                  _labelRow('TC:', data.tc, fontSize),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _text(String value, {required double fontSize, bool bold = false}) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: Colors.black,
        height: 1.1,
      ),
    );
  }

  Widget _labelRow(String label, String value, double fontSize) {
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: fontSize, color: Colors.black, height: 1.1),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Toàn bộ khổ giấy vật lý của tem vàng bạc — decal PVC in tem vàng bạc/trang
/// sức: [contentHeightMm] đầu có in nội dung ([GoldSilverLabelView]), phần
/// còn lại là đuôi nhọn để trống dài [tailMm] dùng để xỏ/buộc.
///
/// Máy in TSPL feed giấy theo đúng pitch vật lý (đầu nhọn tới đầu nhọn kế
/// tiếp) = [contentHeightMm] + [tailMm]; khai báo SIZE thiếu phần đuôi khiến
/// máy feed hụt và tem sau in đè lên phần đuôi tem trước.
class GoldSilverLabelCanvas extends StatelessWidget {
  const GoldSilverLabelCanvas({
    super.key,
    required this.data,
    this.widthMm = 42.0,
    this.contentHeightMm = 10.0,
    this.tailMm = 30.0,
  });

  final GoldSilverLabelModel data;
  final double widthMm;
  final double contentHeightMm;
  final double tailMm;

  /// Tổng chiều dài giấy phải feed cho một tem (khổ SIZE thật gửi cho TSPL).
  double get totalHeightMm => contentHeightMm + tailMm;

  static const double _pxPerMm = 12.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GoldSilverLabelView(
          data: data,
          widthMm: widthMm,
          heightMm: contentHeightMm,
        ),
        Container(
          color: Colors.white,
          width: widthMm * _pxPerMm,
          height: tailMm * _pxPerMm,
        ),
      ],
    );
  }
}
