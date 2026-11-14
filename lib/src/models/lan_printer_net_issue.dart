import 'lan_ip_change_result.dart';

/// Loại lỗi cấu hình mạng của máy in, xem [LanPrinterNetIssue].
enum LanPrinterNetIssueType {
  /// IP máy in nằm ngoài dải mạng của thiết bị: không in tới được.
  otherSubnet,

  /// Cùng dải, IP tĩnh nhưng gateway sai: thiết bị ở dải khác không tới được.
  wrongGateway,
}

/// Máy in có cấu hình mạng sai, trả về từ `PrinterLabel.findLanPrinterIssues`.
class LanPrinterNetIssue {
  /// Cấu hình mạng máy in tự khai báo qua broadcast.
  final LanPrinterNetInfo printer;

  final LanPrinterNetIssueType type;

  /// [LanPrinterNetIssueType.wrongGateway]: gateway đúng của dải (gateway router
  /// cấp cho máy in DHCP cùng dải); `null` nếu không biết — khi đó nên chuyển máy
  /// in sang DHCP.
  final String? suggestedGateway;

  const LanPrinterNetIssue({
    required this.printer,
    required this.type,
    this.suggestedGateway,
  });

  @override
  String toString() =>
      'LanPrinterNetIssue(${type.name}, ${printer.ip}, gateway ${printer.gateway}'
      '${suggestedGateway != null ? ' -> $suggestedGateway' : ''})';
}
