import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

import '../src.dart';

class LabelFromWidget {
  const LabelFromWidget._();
  static Future<List<Uint8List>> captureImages<T>(
    List<T> products,
    BuildContext context, {
    required Widget Function(
      T product,
      Dimensions dimensions,
    ) itemBuilder,
    required int Function(T product) quantity,
    LabelPerRow labelPerRow = LabelPerRow.doubleLabels,
    double spacer = 60,
  }) async {
    Dimensions dimensions = labelPerRow == LabelPerRow.single
        ? Dimensions.large
        : Dimensions.defaultDimens;

    final int itemsPerRow = labelPerRow.count;
    final List<Uint8List> images = [];
    final List<T> expandedProducts = [];

    for (var product in products) {
      for (int i = 0; i < quantity(product); i++) {
        expandedProducts.add(product);
      }
    }

    final List<List<T>> groupedProducts = [];
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
          itemBuilder(row[i], dimensions),
        );

        if (i < row.length - 1) {
          productWidgets.add(SizedBox(width: spacer));
        }
      }

      final itemsToAdd = itemsPerRow - row.length;
      for (int i = 0; i < itemsToAdd; i++) {
        productWidgets.add(
          SizedBox(
            width: dimensions.width + spacer,
            height: dimensions.height,
          ),
        );
      }

      final rowWidget = Row(children: productWidgets);

      final imageBytes = await ScreenshotController().captureFromLongWidget(
        rowWidget,
        context: context,
        constraints: const BoxConstraints.tightFor(),
      );

      images.add(imageBytes);
    }

    return images;
  }

  static Future<Uint8List> captureFromWidget(
    Widget widget, {
    BuildContext? context,
    double? pixelRatio,
  }) async {
    final imageBytes = await ScreenshotController().captureFromWidget(
      widget,
      context: context,
      pixelRatio: pixelRatio ?? 5,
    );
    return imageBytes;
  }
}
