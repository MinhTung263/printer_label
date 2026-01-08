import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

import '../src.dart';

Future<List<Uint8List>> captureImages(
  List<ProductBarcodeModel> products,
  BuildContext context, {
  LabelPerRow labelPerRow = LabelPerRow.doubleLabels,
  double spacer = 60,
  Dimensions? dimensions,
  Size? targetSize,
}) async {
  dimensions = labelPerRow == LabelPerRow.single
      ? Dimensions.large
      : Dimensions.defaultDimens;

  final int itemsPerRow = labelPerRow.count;
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
          dimensions: dimensions,
        ),
      );

      if (i < row.length - 1) {
        productWidgets.add(SizedBox(width: spacer));
      }
    }
    final itemsToAdd = itemsPerRow - row.length;
    for (int i = 0; i < itemsToAdd; i++) {
      productWidgets.add(
        SizedBox(
          width: dimensions.width + (spacer),
          height: dimensions.height,
        ),
      );
    }
    final rowWidget = Row(
      children: productWidgets,
    );

    final imageBytes = await ScreenshotController().captureFromLongWidget(
        rowWidget,
        context: context,
        constraints: BoxConstraints.tightFor());

    images.add(imageBytes);
  }
  return images;
}

Future<Uint8List> captureFromWidget(
  Widget widget, {
  BuildContext? context,
}) async {
  final imageBytes = await ScreenshotController().captureFromWidget(
    widget,
    context: context,
    pixelRatio: 5,
  );
  return imageBytes;
}
