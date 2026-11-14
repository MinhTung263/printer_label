/// Thông số mạng đọc được từ tờ self-test của máy in (giữ nút FEED khi bật máy),
/// VD qua OCR ảnh chụp. Dùng [LanSelfTestInfo.parse].
class LanSelfTestInfo {
  const LanSelfTestInfo({
    required this.ip,
    this.mask,
    this.gateway,
    this.mac,
    this.dhcp,
  });

  final String ip;
  final String? mask;
  final String? gateway;
  final String? mac;

  /// `null` khi tờ in không ghi trạng thái DHCP.
  final bool? dhcp;

  static final RegExp _ipv4 = RegExp(
    r'(?<![\d.])(\d{1,3})\s?[.,]\s?(\d{1,3})\s?[.,]\s?(\d{1,3})\s?[.,]\s?(\d{1,3})(?![\d.])',
  );

  /// Đọc thông số từ chữ in trên tờ self-test. Chịu được lỗi OCR thường gặp: `O`
  /// thay `0`, `,` thay `.`, khoảng trắng chen giữa. Trả `null` khi không thấy IP.
  ///
  /// Nhận các dạng nhãn phổ biến của Xprinter, Epson, Star, HPRT, Gprinter...:
  /// `IP Address`, `IP Addr`, `IP`, `Gateway` / `Default Gateway`, `Subnet Mask` /
  /// `Netmask`, `MAC Address`, `DHCP: Enable / On / Disable / Off`.
  static LanSelfTestInfo? parse(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map(_normalize)
        .where((l) => l.trim().isNotEmpty)
        .toList();

    String? valueFor(RegExp label) {
      for (var i = 0; i < lines.length; i++) {
        if (!label.hasMatch(lines[i])) continue;
        // Giá trị cùng dòng (sau nhãn), hoặc dòng kế (OCR hay tách cột).
        final after = lines[i].substring(label.firstMatch(lines[i])!.end);
        final here = _firstIp(after);
        if (here != null) return here;
        if (i + 1 < lines.length) {
          final next = _firstIp(lines[i + 1]);
          if (next != null) return next;
        }
      }
      return null;
    }

    final ip =
        valueFor(
          RegExp(r'\bIP\s*(address|addr\.?)?\b', caseSensitive: false),
        ) ??
        // Không có nhãn: lấy IP đầu tiên không phải mặt nạ / 0.0.0.0.
        lines
            .map(_firstIp)
            .whereType<String>()
            .firstWhere(
              (v) => !v.startsWith('255.') && v != '0.0.0.0',
              orElse: () => '',
            );
    if (ip.isEmpty || ip.startsWith('255.')) return null;

    final mask = valueFor(
      RegExp(r'\b(subnet\s*mask|net\s*mask|mask)\b', caseSensitive: false),
    );
    final gateway = valueFor(
      RegExp(r'\b(default\s*)?gate\s*way\b|\bGW\b', caseSensitive: false),
    );

    String? mac;
    final macMatch = RegExp(
      r'([0-9A-Fa-f]{2}[:\-\s]){5}[0-9A-Fa-f]{2}',
    ).firstMatch(text.toUpperCase().replaceAll('O', '0'));
    if (macMatch != null) {
      mac = macMatch.group(0)!.replaceAll(RegExp(r'[\-\s]'), ':');
    }

    bool? dhcp;
    final dhcpLine = lines.firstWhere(
      (l) => RegExp(r'\bDHCP\b', caseSensitive: false).hasMatch(l),
      orElse: () => '',
    );
    if (dhcpLine.isNotEmpty) {
      final v = dhcpLine.toLowerCase();
      if (RegExp(r'enable|\bon\b|yes|auto').hasMatch(v)) dhcp = true;
      if (RegExp(r'disable|\boff\b|\bno\b|static|manual').hasMatch(v)) {
        dhcp = false;
      }
    }

    return LanSelfTestInfo(
      ip: ip,
      mask: mask,
      gateway: gateway,
      mac: mac,
      dhcp: dhcp,
    );
  }

  /// Sửa lỗi OCR trong cụm số: `O`/`o` → `0`, `l`/`I` → `1` khi nằm giữa chữ số.
  static String _normalize(String line) => line.replaceAllMapped(
    RegExp(r'(?<=[\d.,])[OoQD](?=[\d.,])|(?<=[\d.,])[lI|](?=[\d.,])'),
    (m) => RegExp('[OoQD]').hasMatch(m.group(0)!) ? '0' : '1',
  );

  static String? _firstIp(String line) {
    for (final m in _ipv4.allMatches(line)) {
      final parts = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
      if (parts.every((p) => p <= 255)) return parts.join('.');
    }
    return null;
  }

  @override
  String toString() =>
      'LanSelfTestInfo(ip: $ip, mask: $mask, gateway: $gateway, mac: $mac, dhcp: $dhcp)';
}
