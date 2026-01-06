import 'dart:typed_data';

import '../enums/label_per_row_enum.dart';

class BarcodeImageModel {
  final List<Uint8List> images;
  int quantity;
  final LabelPerRow? labelPerRow;

  BarcodeImageModel({
    required this.images,
    this.quantity = 1,
    this.labelPerRow,
  });

  /// Converts the model to a map for use in method channel calls
  Map<String, dynamic> toMap() {
    final label = labelPerRow ?? LabelPerRow.one;
    final map = <String, dynamic>{
      'images': images,
      'quantity': quantity,
      'x': label.x,
      'y': label.y,
      'size': {
        'width': label.width,
        'height': label.height,
      },
    };
    return map;
  }
}
