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
  ///
  /// Nếu truyền [onBatch], mỗi lô ảnh vừa render xong được gửi đi ngay thay vì dồn
  /// lại. Điều này quan trọng với dải dài: gửi hết mới in nghĩa là socket tới máy in
  /// im lặng suốt quá trình render (500 tem mất khá lâu), và máy in / router sẽ đóng
  /// kết nối vì idle timeout -> lệnh in cuối cùng thất bại. Gửi theo lô giữ đường
  /// truyền luôn có dữ liệu, đồng thời máy in bắt đầu chạy ngay sau lô đầu.
  ///
  /// Khi có [onBatch], hàm trả về list rỗng — ảnh chỉ sống trong phạm vi mỗi lần
  /// gọi [onBatch] nên không giữ toàn bộ trong RAM.
  static Future<List<Uint8List>> captureImages<T>(
    List<T> items,
    BuildContext context, {
    required Widget Function(
      T item,
    ) itemBuilder,
    required int Function(T item) quantity,
    LabelPerRow labelPerRow = LabelPerRow.doubleLabels,
    double? spacer,
    Future<void> Function(List<Uint8List> batch, bool isLast)? onBatch,
  }) async {
    final int itemsPerRow = labelPerRow.count;
    final List<Uint8List> images = [];
    final List<T> expandedItems = [];

    // Standard symmetric padding and spacer for all label rows.
    //
    // Khổ single (1 tem/ảnh) KHÔNG cộng lề ngoài: ảnh được scale để khớp đúng
    // bề rộng tem thật, nên 8px mỗi bên làm ảnh rộng 52.44mm rồi bị bóp về
    // 50mm -> nội dung co ~4.7% và lệch sang một bên. Lề an toàn của khổ single
    // đã nằm trong widget tem (xem PreviewStamp), không cần chừa thêm ở đây.
    // Double/triple vẫn giữ số cũ vì đã canh khớp gap vật lý giữa các tem.
    final double leftPadding = labelPerRow.name.startsWith('double')
        ? 10.0
        : (labelPerRow.name.startsWith('triple') ? 8.0 : 0.0);
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

    Future<List<Uint8List>> renderBatch(int start, int end) {
      final batch = groupedItems.sublist(start, end);
      return Future.wait(
        batch.map(
          (row) => screenshotController.captureFromWidget(
            buildRowWidget(row),
            pixelRatio: 3.0,
            context: context,
            targetSize: Size(totalWidgetWidth, totalWidgetHeight),
          ),
        ),
      );
    }

    // Render lô KẾ TIẾP song song với việc gửi lô HIỆN TẠI đi in, thay vì tuần tự
    // render-rồi-gửi-rồi-render. Trước đây mỗi lô phải render xong xuôi thì máy in
    // mới có việc để làm, nên giữa các lô 10 tem có một khoảng dừng bằng đúng thời
    // gian render (nặng vì `captureFromWidget` chạy trên UI thread) trong khi máy in
    // đang rảnh chờ. Bắt đầu render lô kế ngay khi lô hiện tại render xong (không đợi
    // in xong) thì máy in nhận lô hiện tại và in trong lúc UI thread bận render lô
    // sau — chỉ còn phải đợi lâu hơn ở LƯỢT ĐẦU TIÊN (chưa có gì để in sẵn).
    int start = 0;
    int end = (start + batchSize).clamp(0, groupedItems.length);
    Future<List<Uint8List>>? nextRender = renderBatch(start, end);

    while (start < groupedItems.length) {
      final captured = await nextRender!;
      final isLast = end >= groupedItems.length;

      // Khởi chạy render lô sau NGAY, không đợi onBatch (gửi in) xong.
      final nextStart = end;
      final nextEnd = (nextStart + batchSize).clamp(0, groupedItems.length);
      nextRender = nextStart < groupedItems.length
          ? renderBatch(nextStart, nextEnd)
          : null;

      if (onBatch != null) {
        // Báo lô cuối để native biết lúc nào được nhả socket LAN.
        await onBatch(captured, isLast);
      } else {
        images.addAll(captured);
      }

      start = nextStart;
      end = nextEnd;

      // Yield to the main thread so it can draw a frame between batches.
      await Future.delayed(const Duration(milliseconds: 16));
    }
    return images;
  }
}
