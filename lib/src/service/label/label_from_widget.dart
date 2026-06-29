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
    ) itemBuilder,
    required int Function(T item) quantity,
    LabelPerRow labelPerRow = LabelPerRow.doubleLabels,
    double? spacer,
  }) async {
    final int itemsPerRow = labelPerRow.count;
    final List<Uint8List> images = [];
    final List<T> expandedItems = [];

    // Standard symmetric padding and spacer for all label rows
    final double leftPadding = labelPerRow.name.startsWith('double')
        ? 10.0
        : (labelPerRow.name.startsWith('triple') ? 8.0 : 8.0);
    final double rightPadding = leftPadding;
    final double effectiveSpacer = spacer ??
        (labelPerRow.name.startsWith('double')
            ? 10.0 // 10.0 logical pixels scales exactly to the physical 1.5mm gap
            : (labelPerRow.name.startsWith('triple') ? 12.0 : 0.0));

    final double stampWidthPx = labelPerRow.stampWidth * 6.57;
    final double stampHeightPx = labelPerRow.stampHeight * 6.57;

    final double totalWidgetWidth = leftPadding +
        (stampWidthPx * itemsPerRow) +
        (effectiveSpacer * (itemsPerRow - 1)) +
        rightPadding;

    final double totalWidgetHeight = stampHeightPx;

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

    Widget buildRowWidget(List<T> row) {
      final List<Widget> productWidgets = [];
      if (leftPadding > 0) {
        productWidgets.add(SizedBox(width: leftPadding));
      }
      for (int i = 0; i < row.length; i++) {
        productWidgets.add(itemBuilder(row[i]));
        if (i < row.length - 1) {
          productWidgets.add(SizedBox(width: effectiveSpacer));
        }
      }
      final itemsToAdd = itemsPerRow - row.length;
      for (int i = 0; i < itemsToAdd; i++) {
        productWidgets.add(SizedBox(
          width: stampWidthPx + effectiveSpacer,
        ));
      }
      if (rightPadding > 0) {
        productWidgets.add(SizedBox(width: rightPadding));
      }

      return MediaQuery(
        data: MediaQueryData(
          size: Size(totalWidgetWidth, totalWidgetHeight),
          devicePixelRatio: 3.0, // Use high-DPI for sharp text rendering
          textScaler: TextScaler.noScaling,
          padding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            visualDensity: VisualDensity.standard,
          ),
          child: Material(
            color: Colors.white,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: productWidgets,
            ),
          ),
        ),
      );
    }

    // Capture in small sequential batches instead of all at once.
    // Rendering every row widget to an image on the main (UI) thread
    // simultaneously causes dropped frames / ANR and holds every Uint8List
    // in memory at the same time (OOM -> lost device connection).
    const int batchSize = 10;
    final screenshotController = ScreenshotController();
    for (int start = 0; start < groupedItems.length; start += batchSize) {
      final int end = (start + batchSize).clamp(0, groupedItems.length);
      final batch = groupedItems.sublist(start, end);

      final captured = await Future.wait(
        batch.map(
          (row) => screenshotController.captureFromWidget(
            buildRowWidget(row),
            pixelRatio: 3.0,
            context: context,
            targetSize: Size(totalWidgetWidth, totalWidgetHeight),
          ),
        ),
      );
      images.addAll(captured);

      // Yield to the main thread so it can draw a frame between batches.
      await Future.delayed(const Duration(milliseconds: 16));
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
