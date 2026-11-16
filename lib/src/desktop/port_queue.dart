import 'dart:async';

/// Xếp hàng tuần tự các việc gửi tới CÙNG một máy in (theo khoá) trong tiến
/// trình này — byte của hai phiếu không chèn vào nhau; máy in khác chạy song song.
///
/// Giữa hai lần gửi tới cùng máy in nghỉ [cooldown]: card mạng của máy in nhiệt
/// giá rẻ cần chút thời gian giải phóng kết nối TCP 9100 cũ — mở lại ngay hay
/// bị từ chối (máy in "bận").
abstract final class PortQueue {
  static final Map<String, Future<void>> _queues = {};

  static Duration cooldown = const Duration(milliseconds: 100);

  /// Một việc treo quá lâu thì thôi chặn các việc sau: không có giới hạn này, MỘT lệnh gửi
  /// bị kẹt (máy in / hệ điều hành không trả lời) làm mọi phiếu sau tới máy in đó chờ mãi
  /// tới hết thời gian chờ (đã gặp: máy USB macOS báo "không phản hồi" sau 60s dù máy
  /// bình thường). Việc treo vẫn chạy tiếp nền, chỉ không giữ hàng đợi nữa.
  static Duration maxHold = const Duration(seconds: 25);

  static Future<T> run<T>(String key, Future<T> Function() task) {
    final prev = _queues[key] ?? Future<void>.value();
    final result = prev.then((_) => task());
    final tail = result
        .then<void>((_) {}, onError: (_) {})
        .timeout(maxHold, onTimeout: () {})
        .then((_) => Future<void>.delayed(cooldown));
    _queues[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_queues[key], tail)) _queues.remove(key);
      }),
    );
    return result;
  }
}
