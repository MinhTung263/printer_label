/// Một máy in USB (Linux) / hàng in (Windows) tìm thấy trên máy tính.
class UsbPrinterInfo {
  const UsbPrinterInfo({
    required this.address,
    required this.name,
    this.detail = '',
    this.setupPort,
  });

  /// Địa chỉ lưu trong cấu hình: `usb:<vid>:<pid>:<serial>` (Linux) hoặc
  /// `queue:<tên hàng in>` (Windows).
  final String address;
  final String name;

  /// VD `/dev/usb/lp0` hoặc `USB001 · Generic / Text Only`.
  final String detail;

  /// Windows: cổng USB (VD `USB001`) có máy in cắm vào nhưng CHƯA có hàng in —
  /// cần tạo hàng in RAW trước khi chọn được.
  final String? setupPort;

  bool get needsSetup => setupPort != null;
}

/// Máy in USB mà hệ điều hành thấy nhưng Agent chưa dùng được, kèm lý do và cách xử lý bằng tiếng Việt.
class UsbPrinterIssue {
  const UsbPrinterIssue(this.name, this.message);

  /// Tên dễ đọc của máy in (hoặc `USB vid:pid` khi máy không khai tên).
  final String name;

  /// Vì sao chưa dùng được + làm gì tiếp.
  final String message;

  @override
  String toString() => '$name: $message';
}

/// Không tìm thấy máy in USB / hàng in đã chọn (rút cáp, đổi máy...).
class UsbPrinterNotFound implements Exception {
  const UsbPrinterNotFound(this.address);
  final String address;
  @override
  String toString() => 'UsbPrinterNotFound($address)';
}
