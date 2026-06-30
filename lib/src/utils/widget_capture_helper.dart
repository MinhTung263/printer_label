import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

/// A utility helper to capture Flutter widgets as images (PNG bytes).
class WidgetCaptureHelper {
  const WidgetCaptureHelper._();

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

  /// Captures a potentially long [widget] (like a receipt) using ScreenshotController's
  /// built-in captureFromLongWidget method which automatically measures the widget's natural size
  /// and captures the full content without height constraints.
  static Future<Uint8List> captureFromLongWidget(
    Widget widget, {
    BuildContext? context,
    double? pixelRatio,
    BoxConstraints? constraints,
  }) async {
    final imageBytes = await ScreenshotController().captureFromLongWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.noScaling,
          ),
          child: Material(
            color: Colors.blue,
            child: widget,
          ),
        ),
      ),
      context: context,
      pixelRatio: pixelRatio ?? 3.0,
      constraints: constraints,
      delay: const Duration(
          milliseconds: 200), // Short delay to ensure widget is fully rendered
    );
    return imageBytes;
  }
}
