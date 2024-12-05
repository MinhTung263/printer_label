import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import '../src.dart';

Future<List<Uint8List>> captureProductListAsImages(
  List<ProductBarcodeModel> products,
  BuildContext context, {
  TypePrintEnum? typePrintEnum,
  int itemsPerRow = 2,
}) async {
  final screenshotController = ScreenshotController();
  final constraints = BoxConstraints.tightFor();
  if (typePrintEnum == TypePrintEnum.singleLabel) {
    final List<Uint8List> images = [];
    for (var product in products) {
      final productWidget = BarcodeView(
        product: product,
        typePrintEnum: typePrintEnum,
      );
      final imageBytes = await screenshotController.captureFromWidget(
        productWidget,
        context: context,
        targetSize: const Size(360, 200),
      );
      images.add(imageBytes);
    }
    return images;
  } else {
    final List<Uint8List> images = [];
    final List<ProductBarcodeModel> expandedProducts = [];
    for (var product in products) {
      for (int i = 0; i < product.quantity; i++) {
        expandedProducts.add(product);
      }
    }
    final List<List<ProductBarcodeModel>> groupedProducts = [];

    for (int i = 0; i < expandedProducts.length; i++) {
      if (i % itemsPerRow == 0) {
        groupedProducts.add([]);
      }
      groupedProducts.last.add(expandedProducts[i]);
    }

    for (var row in groupedProducts) {
      final List<Widget> productWidgets = [];
      for (int i = 0; i < row.length; i++) {
        productWidgets.add(
          BarcodeView(
            product: row[i],
            typePrintEnum: typePrintEnum,
          ),
        );

        if (i < row.length - 1) {
          productWidgets.add(SizedBox(width: 60));
        }
      }
      final itemsToAdd = itemsPerRow - row.length;
      for (int i = 0; i < itemsToAdd; i++) {
        productWidgets.add(SizedBox(
          width: (typePrintEnum?.width ?? 0) + 60,
          height: typePrintEnum?.height,
        ));
      }
      final rowWidget = Row(
        children: productWidgets,
      );

      final imageBytes = await screenshotController.captureFromLongWidget(
        rowWidget,
        context: context,
        constraints: constraints,
      );

      images.add(imageBytes);
    }
    return images;
  }
}
