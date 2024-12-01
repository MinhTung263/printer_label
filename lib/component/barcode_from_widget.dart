import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../src.dart';

Future<List<Uint8List>> captureProductListAsImages(
  List<ProductBarcodeModel> products,
  BuildContext context, {
  TypePrintEnum? typePrintEnum,
}) async {
  final List<Uint8List> images = [];

  for (var product in products) {
    final productWidget = BarcodeView(
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
