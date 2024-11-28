import 'dart:typed_data';

class PrintImageModel {
  final Uint8List imageData;
  final int quantity;
  final double? width;
  final double? height;
  final int? x;
  final int? y;
  final int? widthImage;

  PrintImageModel({
    required this.imageData,
    this.quantity = 1, // Default value is 1
    this.width,
    this.height,
    this.x,
    this.y,
    this.widthImage,
  });

  /// Converts the model to a map for use in method channel calls
  Map<String, dynamic> toMap() {
    return {
      'imageData': imageData,
      'quantity': quantity,
      'widthImage': widthImage,
      'x': x,
      'y': y,
      'size': {
        'width': width,
        'height': height,
      },
    };
  }
}
