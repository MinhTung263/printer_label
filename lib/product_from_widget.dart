import 'dart:typed_data';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'capture_widget.dart';
import 'src.dart';

Future<List<Uint8List>> captureProductListAsImages(
  List<Product> products,
  BuildContext context, {
  TypePrintEnum? typePrintEnum,
}) async {
  final List<Uint8List> images = [];

  for (var product in products) {
    final productWidget = ProductView(
      product: product,
      typePrintEnum: typePrintEnum,
    );
    final imageBytes = await ScreenshotController.captureFromWidget(
      productWidget,
      // ignore: use_build_context_synchronously
      context: context,
      targetSize: const Size(360, 200),
    );
    images.add(imageBytes);
  }

  return images;
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
    this.typePrintEnum,
  });
  final Product product;
  final TypePrintEnum? typePrintEnum;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      width: typePrintEnum?.width,
      height: typePrintEnum?.height,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildText(
            "EasyPos",
          ),
          _buildText(
            product.name,
            fontWeight: FontWeight.bold,
          ),
          BarcodeWidget(
            barcode: Barcode.code93(), // Loại mã vạch (có thể thay đổi)
            data: product.barcode,
            width: typePrintEnum?.width,
            height: typePrintEnum?.barcodeHeight,
            drawText: true, // Hiển thị mã số dưới mã vạch
            style: const TextStyle(fontSize: 18),
          ),
          _buildText(
            product.price,
            fontWeight: FontWeight.bold,
            addFontSize: 5,
          ),
        ],
      ),
    );
  }

  Widget _buildText(
    String text, {
    FontWeight? fontWeight,
    double? addFontSize,
  }) {
    return Text(
      text,
      style: TextStyle(
        fontSize: (typePrintEnum?.fontSize ?? 20) + (addFontSize ?? 0),
        fontWeight: fontWeight,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
