import 'package:flutter/material.dart';

extension SnackBarExtension on BuildContext {
  /// Displays a floating SnackBar with a default indigo background or custom background color.
  void showSnackBar(String message, {Color? backgroundColor}) {
    final scaffoldMessenger = ScaffoldMessenger.of(this);
    scaffoldMessenger.clearSnackBars();
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? const Color(0xFF4F46E5),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
