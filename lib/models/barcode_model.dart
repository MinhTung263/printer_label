class BarcodeModel {
  final Map<String, dynamic> printData;

  BarcodeModel({
    double? width,
    double? height,
    double? gapWidth,
    double? gapHeight,
    String? barcodeContent,
    int? barcodeX,
    int? barcodeY,
    double? barcodeHeight,
    int? quantity,
    List<TextData>? textData,
  }) : printData = {
          'size': {
            'width': width,
            'height': height,
          },
          'gap': {
            'width': gapWidth,
            'height': gapHeight,
          },
          'barcode': {
            'x': barcodeX,
            'y': barcodeY,
            'height': barcodeHeight,
            'barcodeContent': barcodeContent,
          },
          'text': textData?.map((text) => text.toMap()).toList(),
          'quantity': quantity,
        };

  // Method to convert PrintModel to a Map for further processing
  Map<String, dynamic> toMap() {
    return printData;
  }
}

class TextData {
  final int? x;
  final int? y;
  final int? sizeX;
  final int? sizeY;
  final String? data;

  TextData({
    this.x,
    this.y,
    this.sizeX,
    this.sizeY,
    this.data,
  });

  // Convert TextData instance to a map
  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'sizeX': sizeX,
      'sizeY': sizeY,
      'data': data,
    };
  }
}
