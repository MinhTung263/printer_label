import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

Future<Uint8List?> captureWidgetAsImage(
  Widget widget,
  BuildContext context, {
  double pixelRatio = 3.0,
}) async {
  try {
    // Wrap the widget in a RepaintBoundary with a GlobalKey
    final key = GlobalKey();
    final widgetWithBoundary = MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: widget,
        ),
      ),
    );

    // Render the widget off-screen
    final RenderRepaintBoundary boundary =
        await _renderWidget(widgetWithBoundary, key, context);

    // Convert the boundary to an image
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    // Chuyển ảnh Uint8List thành ảnh có kích thước mới
    if (byteData != null) {
      Uint8List originalBytes = byteData.buffer.asUint8List();
      return await resizeImage(
        originalBytes,
        width: 360,
        height: 200,
      ); // Resize ở đây
    }
    return null;
  } catch (e) {
    debugPrint("Error capturing widget: $e");
    return null;
  }
}

Future<RenderRepaintBoundary> _renderWidget(
  Widget widget,
  GlobalKey key,
  BuildContext context,
) async {
  // Use the global navigator key for overlay rendering
  final container = OverlayEntry(
    builder: (context) => Material(
      child: widget,
    ),
  );

  final overlay = Overlay.of(context);
  overlay.insert(container);

  // Wait for a frame to render the widget
  await Future.delayed(const Duration(milliseconds: 5));
  container.remove();

  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw Exception("Failed to capture widget");
  return boundary;
}

Future<List<Uint8List>> captureProductListAsImages(
  List<Product> products,
  BuildContext context,
) async {
  List<Uint8List> images = [];

  for (var product in products) {
    final productWidget = ProductView(
      product: product,
    );

    final imageBytes = await captureWidgetAsImage(productWidget, context);
    if (imageBytes != null) {
      images.add(imageBytes);
    }
  }

  return images;
}

Future<Uint8List?> resizeImage(Uint8List originalBytes,
    {int width = 100, int height = 100}) async {
  try {
    // Chuyển đổi Uint8List thành đối tượng ảnh
    img.Image? image = img.decodeImage(Uint8List.fromList(originalBytes));

    if (image == null) {
      throw Exception("Failed to decode image");
    }

    // Resize ảnh
    img.Image resizedImage =
        img.copyResize(image, width: width, height: height);

    // Chuyển ảnh đã resize lại thành Uint8List
    Uint8List resizedBytes = Uint8List.fromList(img.encodePng(resizedImage));

    return resizedBytes;
  } catch (e) {
    print("Error resizing image: $e");
    return null;
  }
}

class Product {
  final String barcode;
  final String name;
  final String price;
  final int quantity;

  Product({
    required this.barcode,
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  // Convert a Product object into a Map for easy JSON encoding or database storage
  Map<String, dynamic> toMap() {
    return {
      'barcode': barcode,
      'name': name,
      'description': price,
      'quantity': quantity,
    };
  }

  // Create a Product object from a Map
  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      barcode: map['barcode'] ?? '',
      name: map['name'] ?? '',
      price: map['description'] ?? '',
      quantity: map['quantity'] ?? 1,
    );
  }
}

class ProductView extends StatelessWidget {
  const ProductView({
    super.key,
    required this.product,
  });
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "EasyPos",
          style: TextStyle(
            fontSize: 14,
          ),
        ),
        Text(
          product.name,
          style: const TextStyle(fontSize: 12),
        ),
        BarcodeWidget(
          barcode: Barcode.code93(), // Loại mã vạch (có thể thay đổi)
          data: product.barcode,
          width: 290,
          height: 80,
          drawText: true, // Hiển thị mã số dưới mã vạch
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          product.price,
          style: const TextStyle(
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
