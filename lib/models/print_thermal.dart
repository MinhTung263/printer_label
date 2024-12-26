import 'dart:typed_data';

class PrintThermalModel {
  final Uint8List image;
  final int? size;

  PrintThermalModel({
    required this.image,
    this.size,
  });

  Map<String, dynamic> toJson() {
    return {
      'image': image,
      'size': size,
    };
  }
}
