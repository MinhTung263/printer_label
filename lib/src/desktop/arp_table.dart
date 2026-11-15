import 'dart:io';

/// Bảng ARP của máy (IP → MAC các thiết bị cùng mạng vừa liên lạc) — để nhận
/// lại máy in LAN theo MAC khi router cấp IP mới. Không cần quyền quản trị:
/// Windows `arp -a`, macOS `arp -an`, Linux đọc `/proc/net/arp`.
abstract final class ArpTable {
  static final RegExp _ip = RegExp(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b');
  static final RegExp _mac = RegExp(
    r'\b([0-9a-fA-F]{1,2}(?:[:-][0-9a-fA-F]{1,2}){5})\b',
  );

  /// `a:b:c:d:e:f` / `aa-bb-…` → `AA:BB:CC:DD:EE:FF`; `null` khi không phải MAC
  /// thật (rỗng, broadcast, toàn 0).
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final parts = raw.trim().split(RegExp('[:-]'));
    if (parts.length != 6) return null;
    final mac = parts.map((p) => p.padLeft(2, '0').toUpperCase()).join(':');
    if (mac == 'FF:FF:FF:FF:FF:FF' || mac == '00:00:00:00:00:00') return null;
    return RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(mac) ? mac : null;
  }

  /// Tách bảng ARP từ đầu ra của `arp` / `/proc/net/arp` (mỗi dòng một IP + MAC).
  static Map<String, String> parse(String output) {
    final table = <String, String>{};
    for (final line in output.split('\n')) {
      final ip = _ip.firstMatch(line)?.group(1);
      final mac = normalize(_mac.firstMatch(line)?.group(1));
      if (ip != null && mac != null) table[ip] = mac;
    }
    return table;
  }

  static Future<Map<String, String>> read() async {
    try {
      if (Platform.isLinux) {
        return parse(await File('/proc/net/arp').readAsString());
      }
      final r = await Process.run(
        'arp',
        Platform.isWindows ? ['-a'] : ['-an'],
      ).timeout(const Duration(seconds: 5));
      return parse('${r.stdout}');
    } catch (_) {
      return const {};
    }
  }

  /// MAC của [ip] (máy phải vừa liên lạc — VD vừa mở kết nối tới cổng in).
  static Future<String?> macOf(String ip) async => (await read())[ip];
}
