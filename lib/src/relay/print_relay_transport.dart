/// Một lệnh vừa xuất hiện trên hàng đợi: [id] và dữ liệu thô ([PrintRelayJob.toMap]).
class PrintRelayQueuedJob {
  const PrintRelayQueuedJob(this.id, this.data);

  final String id;
  final Object? data;
}

/// Kênh trao đổi lệnh in giữa máy gửi và trạm in (Firebase, server riêng,
/// MQTT...). Plugin lo phần chung — định dạng lệnh, giành lệnh, hạn lệnh, chờ kết
/// quả — còn app cài lớp này với dịch vụ mình dùng.
///
/// Một đối tượng ứng với một hàng đợi (VD một quán): đổi quán thì tạo đối tượng
/// mới.
abstract class PrintRelayTransport {
  // --- Trạm in ---

  /// Báo trạm đang trực tuyến kèm [info] (VD tên thiết bị). Nên tự gỡ khi mất
  /// kết nối và tự báo lại khi có mạng lại.
  Future<void> goOnline(Map<String, Object?> info);

  /// Gỡ trạng thái trực tuyến của trạm này.
  Future<void> goOffline();

  /// Các lệnh trên hàng đợi: lệnh có sẵn lúc bắt đầu nghe và lệnh mới thêm.
  Stream<PrintRelayQueuedJob> watchJobs();

  /// Giành lệnh [id] một cách nguyên tử: đổi `pending` → `printing`. Trả `true`
  /// khi trạm này giành được (trạm khác đã nhận thì `false`).
  Future<bool> claimJob(String id);

  /// Báo đã nhận lệnh [id] (trạng thái `printing`) — máy gửi biết trạm còn sống
  /// và đang in, không phải chờ hết thời gian mới biết trạm đã tắt.
  Future<void> ackJob(String id);

  /// Ghi kết quả lệnh [id] và xoá nội dung in khỏi hàng đợi (không giữ ảnh hoá
  /// đơn trên mây).
  Future<void> completeJob(String id, {required bool success});

  /// Xoá hẳn lệnh [id].
  Future<void> deleteJob(String id);

  // --- Máy gửi ---

  /// Các trạm đang trực tuyến kèm thông tin trạm báo khi [goOnline] (phát lại mỗi
  /// khi thay đổi; rỗng = không có trạm).
  Stream<List<Map<Object?, Object?>>> watchStations();

  /// Đưa lệnh lên hàng đợi, trả mã lệnh.
  Future<String> submitJob(Map<String, Object?> data);

  /// Trạng thái lệnh [id] ([PrintRelayStatus]), phát mỗi khi thay đổi.
  Stream<String?> watchJobStatus(String id);

  /// Đang kết nối thật tới dịch vụ (Firebase / broker) không — phát ngay giá trị
  /// hiện tại rồi phát lại mỗi khi rớt / nối lại (để app hiển thị tức thì).
  Stream<bool> watchConnection();
}
