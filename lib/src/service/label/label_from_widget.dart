import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

import '../../src.dart';

/// A helper utility service to convert Flutter widgets into rasterized image byte lists
/// suitable for printing as labels or stickers.
class LabelFromWidget {
  const LabelFromWidget._();

  /// Captures multiple generic [items] into a list of image byte arrays.
  /// 
  /// Group items according to the [labelPerRow] count, builds widgets using [itemBuilder],
  /// replicates each item based on its [quantity], and renders the row as a PNG.
  static Future<List<Uint8List>> captureImages<T>(
    List<T> items,
    BuildContext context, {
    required Widget Function(
      T item,
      Dimensions dimensions,
    ) itemBuilder,
    required int Function(T item) quantity,
    LabelPerRow labelPerRow = LabelPerRow.doubleLabels,
    double spacer = 60,
  }) async {
    Dimensions dimensions = labelPerRow == LabelPerRow.single
        ? Dimensions.large
        : Dimensions.defaultDimens;

    final int itemsPerRow = labelPerRow.count;
    final List<Uint8List> images = [];
    final List<T> expandedItems = [];

    // Duplicate items based on their print quantity
    for (var item in items) {
      for (int i = 0; i < quantity(item); i++) {
        expandedItems.add(item);
      }
    }

    // Group items into chunks matching the columns per row
    final List<List<T>> groupedItems = [];
    for (int i = 0; i < expandedItems.length; i++) {
      if (i % itemsPerRow == 0) {
        groupedItems.add([]);
      }
      groupedItems.last.add(expandedItems[i]);
    }

    final screenshotController = ScreenshotController();

    // Render each row group to a rasterized image
    for (var row in groupedItems) {
      final List<Widget> productWidgets = [];

      for (int i = 0; i < row.length; i++) {
        productWidgets.add(
          itemBuilder(row[i], dimensions),
        );

        if (i < row.length - 1) {
          productWidgets.add(SizedBox(width: spacer));
        }
      }

      // Pad remaining empty columns in the row if necessary
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

      final imageBytes = await screenshotController.captureFromLongWidget(
        rowWidget,
        context: context,
        constraints: const BoxConstraints.tightFor(),
      );

      images.add(imageBytes);
    }

    return images;
  }

  /// Captures a single [widget] and converts it directly into a PNG image byte array.
  /// 
  /// The [pixelRatio] parameter determines the export resolution scale (defaults to `5` for print clarity).
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
