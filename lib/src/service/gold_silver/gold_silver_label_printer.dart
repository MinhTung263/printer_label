import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../component/gold_silver_label_view.dart';
import '../../enums/enum.src.dart';
import '../../models/src.dart';
import '../../platform/printer_label.dart';
import '../../utils/image_resize.dart';
import '../../utils/widget_capture_helper.dart';

/// In tem vàng bạc (nhẫn / trang sức) — decal PVC thực tế: khổ 42x10mm phần
/// nội dung, cộng đuôi nhọn dài thêm 30mm không in (dùng để xỏ/buộc).
class GoldSilverLabelPrinter {
  const GoldSilverLabelPrinter._();

  /// In danh sách tem vàng bạc [items].
  ///
  /// Máy in TSPL cần biết đúng PITCH vật lý (đầu nhọn tới đầu nhọn kế tiếp)
  /// để feed giấy chính xác, tức [contentHeightMm] + [tailMm] — không phải
  /// chỉ phần có chữ. Khai báo thiếu phần đuôi khiến tem sau in đè lên đuôi
  /// tem trước, nội dung dồn cụm vào một góc như quan sát thực tế.
  ///
  /// Dùng `LabelPerRow.triple.copyWith(...)` (thay vì `.single`) để giữ
  /// `useHome = true`: bắt máy dò lại cảm biến khe decal trước mỗi lần in,
  /// bù sai số dò-gap của cảm biến trên đầu tem dạng nhọn bất thường (khác
  /// die-cut chữ nhật chuẩn). `label_count` không được native đọc trong
  /// đường in TSPL này nên việc mượn `triple` không ảnh hưởng số ảnh gửi.
  static Future<void> printLabels({
    required List<GoldSilverLabelModel> items,
    double widthMm = 42.0,
    double contentHeightMm = 10.0,
    double tailMm = 30.0,
    BuildContext? context,
    String? deviceId,
    PrinterConnectionType? connectionType,
  }) async {
    final size = CupStickerSize(
      key: 'gold_silver_${widthMm}x${contentHeightMm + tailMm}',
      widthMm: widthMm,
      heightMm: contentHeightMm + tailMm,
    );

    final images = <Uint8List>[];
    for (final item in items) {
      if (context != null && !context.mounted) return;
      final bytes = await WidgetCaptureHelper.captureFromWidget(
        GoldSilverLabelCanvas(
          data: item,
          widthMm: widthMm,
          contentHeightMm: contentHeightMm,
          tailMm: tailMm,
        ),
        context: context,
      );
      // Nội dung + đuôi trắng đã render đúng full khổ giấy vật lý, không cần
      // lề thêm (mặc định 2mm/cạnh của resizeImage sẽ bóp méo tỉ lệ tem hẹp).
      final resized = await resizeImage(
        imageBytes: bytes,
        size: size,
        paddingMm: 0,
      );
      images.add(resized);
    }

    final model = LabelModel(
      images: images,
      labelPerRow: LabelPerRow.triple.copyWith(
        width: widthMm.toInt(),
        height: (contentHeightMm + tailMm).toInt(),
        gap: 2,
      ),
    );

    await PrinterLabel.printLabel(
      deviceId: deviceId,
      connectionType: connectionType,
      labelModel: model,
    );
  }
}
