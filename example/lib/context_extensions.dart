import 'package:example/widgets/print_preview_widgets.dart';
import 'package:flutter/material.dart';

extension SnackBarExtension on BuildContext {
  /// Hiển thị thông báo trượt ở đỉnh màn hình sử dụng chung một base showTopNotification.
  void showSnackBar(String message, {Color? backgroundColor}) {
    // Nếu màu nền là màu đỏ/cam hoặc các tông màu lỗi, xác định đây là lỗi.
    final isError = backgroundColor != null && (
      backgroundColor == const Color(0xFFF43F5E) ||
      backgroundColor == const Color(0xFFE11D48) ||
      backgroundColor == Colors.red ||
      backgroundColor == Colors.redAccent ||
      backgroundColor == Colors.orange ||
      backgroundColor == Colors.orangeAccent
    );
    
    showTopNotification(
      this,
      message,
      isError: isError,
      customBgColor: backgroundColor ?? const Color(0xFF4F46E5),
    );
  }
}
