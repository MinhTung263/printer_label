import 'dart:typed_data';

class ImageModel {
  final Uint8List image;
  final int x;
  final int y;
  final int width;
  final int height;

  ImageModel({
    required this.image,
    this.x = 0,
    this.y = 0,
    this.width = 600,
    this.height = 200,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'image': image,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }
}
