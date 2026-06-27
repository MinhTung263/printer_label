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
          'text': textData?.map((text) => text.toJson()).toList(),
          'quantity': quantity,
        };

  /// Converts the barcode model to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return printData;
  }

  /// [Deprecated] Use [toJson] instead.
  @Deprecated('Use toJson instead')
  Map<String, dynamic> toMap() {
    return toJson();
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

  /// Converts the text data model to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'sizeX': sizeX,
      'sizeY': sizeY,
      'data': data,
    };
  }

  /// [Deprecated] Use [toJson] instead.
  @Deprecated('Use toJson instead')
  Map<String, dynamic> toMap() {
    return toJson();
  }
}
