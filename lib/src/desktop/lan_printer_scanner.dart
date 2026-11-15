import 'dart:async';
import 'dart:io';

/// Một máy in LAN tìm thấy (mở cổng RAW 9100).
class LanPrinterFound {
  const LanPrinterFound(this.host, this.port);

  final String host;
  final int port;

  /// `ip` (cổng mặc định) hoặc `ip:cổng` — dạng lưu trong cấu hình / lệnh in.
  String get address => port == 9100 ? host : '$host:$port';
}

/// Tách `ip` / `ip:cổng` (cổng mặc định 9100). `null` khi rỗng.
(String, int)? parsePrinterAddress(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final i = s.lastIndexOf(':');
  if (i > 0 && !s.contains(']') && s.indexOf(':') == i) {
    final port = int.tryParse(s.substring(i + 1));
    if (port != null && port > 0 && port < 65536) {
      return (s.substring(0, i), port);
    }
  }
  return (s, 9100);
}

/// Quét máy in LAN: thử mở cổng [port] trên mọi địa chỉ /24 của các card mạng
/// IPv4 đang dùng. Không cần driver hay giao thức riêng của hãng.
abstract final class LanPrinterScanner {
  static Future<List<LanPrinterFound>> scan({
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 400),
    int parallel = 64,
  }) async {
    final prefixes = <String>{};
    for (final nic in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final a in nic.addresses) {
        if (a.isLoopback || a.isLinkLocal) continue;
        final parts = a.address.split('.');
        if (parts.length == 4) prefixes.add(parts.take(3).join('.'));
      }
    }
    final hosts = [
      for (final p in prefixes)
        for (var i = 1; i < 255; i++) '$p.$i',
    ];
    final found = <LanPrinterFound>[];
    for (var i = 0; i < hosts.length; i += parallel) {
      final batch = hosts.skip(i).take(parallel);
      await Future.wait(
        batch.map((h) async {
          if (await probe(h, port: port, timeout: timeout)) {
            found.add(LanPrinterFound(h, port));
          }
        }),
      );
    }
    found.sort((a, b) => _ipKey(a.host).compareTo(_ipKey(b.host)));
    return found;
  }

  /// Máy [host] có mở cổng [port] không.
  static Future<bool> probe(
    String host, {
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 400),
  }) async {
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static int _ipKey(String ip) =>
      ip.split('.').fold(0, (v, p) => v * 256 + (int.tryParse(p) ?? 0));
}
