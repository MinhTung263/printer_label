import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import '../src.dart';

Future<List<Uint8List>> captureProductListAsImages(
  List<ProductBarcodeModel> products,
  BuildContext context, {
  TypePrintEnum? typePrintEnum,
}) async {
  final List<Uint8List> images = [];
  final screenshotController = ScreenshotController();
  final constraints = BoxConstraints.tightFor();
  if (typePrintEnum == TypePrintEnum.singleLabel) {
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
  } else {
    for (var product in products) {
      int remainingQuantity = product.quantity;
      int maxPerRow = 2;

      while (remainingQuantity > 0) {
        int currentBatch =
            remainingQuantity >= maxPerRow ? maxPerRow : remainingQuantity;

        final productWidgets = <Widget>[];
        for (int i = 0; i < currentBatch; i++) {
          productWidgets.add(
            BarcodeView(
              product: product,
              typePrintEnum: typePrintEnum,
            ),
          );

          if (i < currentBatch - 1) {
            productWidgets.add(SizedBox(width: 50));
          }
        }

        final productWidget = Row(
          children: productWidgets,
        );

        final imageBytes = await screenshotController.captureFromLongWidget(
          productWidget,
          context: context,
          constraints: constraints,
        );

        images.add(imageBytes);

        remainingQuantity -= currentBatch;
      }
    }
  }

  return images;
}
