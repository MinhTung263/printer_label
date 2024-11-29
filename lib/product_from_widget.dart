import 'dart:typed_data';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'capture_widget.dart';

Future<List<Uint8List>> captureProductListAsImages(
  List<Product> products,
  BuildContext context,
) async {
  final List<Uint8List> images = [];

  for (var product in products) {
    final productWidget = ProductView(
      product: product,
    );
    final imageBytes = await ScreenshotController.captureFromWidget(
      productWidget,
      context: context,
      pixelRatio: 2,
      targetSize: const Size(360, 200),
    );

    final image = await resizeImage(
      imageBytes,
    );
    images.add(image);
  }

  return images;
}

Future<Uint8List> resizeImage(
  Uint8List originalBytes, {
  int width = 360,
  int height = 200,
}) async {
  // Chuyển đổi Uint8List thành đối tượng ảnh
  img.Image? image = img.decodeImage(Uint8List.fromList(originalBytes));

  if (image == null) {
    throw Exception("Failed to decode image");
  }

  // Resize ảnh
  img.Image resizedImage = img.copyResize(
    image,
    width: width,
    height: height,
  );

  // Chuyển ảnh đã resize lại thành Uint8List
  final Uint8List resizedBytes = Uint8List.fromList(
    img.encodeBmp(resizedImage),
  );

  return resizedBytes;
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
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "EasyPos",
            style: TextStyle(
              fontSize: 16,
            ),
          ),
          Text(
            product.name,
            style: const TextStyle(fontSize: 14),
          ),
          BarcodeWidget(
            barcode: Barcode.code93(), // Loại mã vạch (có thể thay đổi)
            data: product.barcode,
            width: 280,
            height: 80,
            drawText: true, // Hiển thị mã số dưới mã vạch
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            product.price,
            style: const TextStyle(
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
