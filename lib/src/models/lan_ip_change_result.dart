/// Cấu hình mạng máy in tự khai báo qua gói `XP0001FOUND` (trả lời cho `XP0001FIND`,
/// UDP cổng 9000). Xprinter, PDIT và các máy cùng firmware trả lời gói này.
class LanPrinterNetInfo {
  /// MAC dạng `AA:BB:CC:DD:EE:FF`.
  final String mac;
  final String ip;
  final String mask;
  final String gateway;

  /// `true` nếu máy in đang nhận IP qua DHCP.
  final bool dhcp;

  const LanPrinterNetInfo({
    required this.mac,
    required this.ip,
    required this.mask,
    required this.gateway,
    required this.dhcp,
  });

  @override
  String toString() =>
      'LanPrinterNetInfo(mac: $mac, ip: $ip, mask: $mask, gateway: $gateway, dhcp: $dhcp)';
}

enum LanIpChangeStatus {
  /// Đã xác minh: máy in (đúng MAC) đang trả lời ở IP mới.
  success,

  /// Đã gửi lệnh nhưng không xác minh được máy in ở IP mới trong thời gian chờ.
  /// Máy in có thể vẫn đang khởi động lại mạng, hoặc không nhận lệnh.
  unverified,

  /// IP mới đang có thiết bị khác dùng — KHÔNG gửi lệnh.
  conflict,

  /// IP mới sai định dạng, không cùng subnet với thiết bị, hoặc là địa chỉ đặc biệt.
  invalidIp,

  /// Không có cách nào gửi lệnh đổi IP tới máy in này.
  notSupported,

  /// Lỗi khác (gửi lệnh thất bại...).
  failed,
}

/// Kết quả của `PrinterLabel.changeLanPrinterIp`.
class LanIpChangeResult {
  final LanIpChangeStatus status;

  /// IP của máy in sau khi đổi (đã xác minh khi [status] là `success`). Khi đổi sang
  /// DHCP đây là IP router mới cấp; `null` nếu chưa biết.
  final String? ip;

  /// MAC của máy in (nếu lấy được).
  final String? mac;

  /// Cách đã dùng để gửi lệnh: `udp`, `tspl`, `zpl`, `native` (SDK nền tảng).
  final String? method;

  /// Mô tả cho người dùng / log (tiếng Việt).
  final String message;

  const LanIpChangeResult({
    required this.status,
    required this.message,
    this.ip,
    this.mac,
    this.method,
  });

  bool get isSuccess => status == LanIpChangeStatus.success;

  @override
  String toString() =>
      'LanIpChangeResult(status: ${status.name}, ip: $ip, mac: $mac, method: $method, message: $message)';
}
