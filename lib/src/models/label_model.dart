import 'dart:typed_data';

import '../enums/label_per_row_enum.dart';

class LabelModel {
  final List<Uint8List> images;
  int quantity;
  final LabelPerRow? labelPerRow;

  /// Lô này có phải lô CUỐI của lượt in hay không.
  ///
  /// Một lượt in dài được chia thành nhiều lô ảnh, mỗi lô là một lời gọi native
  /// riêng. Native chỉ được nhả socket LAN khi lô cuối in xong; nhả ở giữa sẽ
  /// buộc lô sau mở lại socket và đụng đúng socket chưa giải phóng hẳn
  /// ("Máy in đang bận, thử lại sau ...") -> tem in ra lệch hoặc lỗi.
  ///
  /// Mặc định `true` để mọi lời gọi in một lô lẻ vẫn nhả socket như trước.
  final bool isLastBatch;

  LabelModel({
    required this.images,
    this.quantity = 1,
    this.labelPerRow,
    this.isLastBatch = true,
  });

  /// Converts the model to a map for use in method channel calls
  Map<String, dynamic> toJson() {
    final label = labelPerRow ?? LabelPerRow.single;
    final map = <String, dynamic>{
      'images': images,
      'type': 'TSPL',
      'quantity': quantity,
      'label_count': label.count,
      'size': {
        'width': label.width,
        'height': label.height,
      },
      'gap': {
        'width': label.gap,
        'height': 0,
      },
      'use_home': label.useHome,
      'is_last_batch': isLastBatch,
    };
    return map;
  }
}
