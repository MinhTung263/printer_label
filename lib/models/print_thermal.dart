import 'dart:typed_data';

import '../enums/paper_size_enum.dart';

class PrintThermalModel {
  final Uint8List image;
  final PaperSize size;

  PrintThermalModel({
    required this.image,
    this.size = PaperSize.mm80,
  });

  Map<String, dynamic> toJson() {
    return {
      'image': image,
      'size': size.value,
    };
  }
}
