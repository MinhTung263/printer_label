import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Một máy in POS / Xprinter trả lời lệnh dò UDP (`XP0001FIND` → `XP0001FOUND`): biết
/// luôn IP, MAC, mặt nạ, cổng ra và DHCP bật hay tắt — kể cả khi máy in ở KHÁC dải mạng
/// hoặc IP của nó bị thiết bị khác chiếm (quét cổng 9100 sẽ không thấy / thấy nhầm).
class XprinterUdpFound {
  const XprinterUdpFound({
    required this.mac,
    required this.ip,
    this.mask = '',
    this.gateway = '',
    this.dhcp = false,
  });

  /// `AA:BB:CC:DD:EE:FF` (chữ hoa).
  final String mac;
  final String ip;
  final String mask;
  final String gateway;
  final bool dhcp;
}

/// Dò / cấu hình mạng máy in Xprinter qua UDP broadcast cổng 9000 — cùng giao thức
/// bản Android / iOS dùng (`XP0001FIND`, `XP0001SAVE`).
abstract final class XprinterUdp {
  static const int port = 9000;

  static List<int> findPacket() => ascii.encode('XP0001FIND');

  /// Đọc gói trả lời `XP0001FOUND` (>= 33 byte): MAC ở 11..17, IP 19..23, mặt nạ 23..27,
  /// cổng ra 27..31, DHCP ở byte 33. `null` nếu không phải gói trả lời của máy in.
  static XprinterUdpFound? parseReply(List<int> b) {
    if (b.length < 33) return null;
    if (String.fromCharCodes(b.take(11)) != 'XP0001FOUND') return null;
    String ip(int from) => b.sublist(from, from + 4).join('.');
    final mac = b
        .sublist(11, 17)
        .map((v) => v.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
    final found = XprinterUdpFound(
      mac: mac,
      ip: ip(19),
      mask: b.length >= 27 ? ip(23) : '',
      gateway: b.length >= 31 ? ip(27) : '',
      dhcp: b.length >= 34 && b[33] == 1,
    );
    return found.ip == '0.0.0.0' ? null : found;
  }

  /// Gói cấu hình mạng `XP0001SAVE` (34 byte): đặt IP / mặt nạ / cổng ra / DHCP cho máy in
  /// có địa chỉ MAC [mac].
  static Uint8List savePacket({
    required String mac,
    required String ip,
    String mask = '255.255.255.0',
    String gateway = '0.0.0.0',
    bool dhcp = false,
  }) {
    List<int> ipBytes(String s) {
      final p = s.split('.');
      return p.length == 4
          ? [for (final x in p) (int.tryParse(x.trim()) ?? 0).clamp(0, 255)]
          : [0, 0, 0, 0];
    }

    final macBytes = [
      for (final x in mac.split(RegExp('[:\\- ]')).where((e) => e.isNotEmpty))
        int.tryParse(x, radix: 16) ?? 0,
    ];
    if (macBytes.length != 6) {
      throw ArgumentError.value(mac, 'mac', 'MAC phải đủ 6 byte');
    }
    return Uint8List.fromList([
      ...ascii.encode('XP0001SAVE'),
      ...macBytes,
      0x22, 0x00, // độ dài 34
      ...ipBytes(ip),
      ...ipBytes(mask.isEmpty ? '255.255.255.0' : mask),
      ...ipBytes(gateway),
      0x8C, 0x23, // cổng 9100 (little-endian)
      dhcp ? 1 : 0,
      0,
    ]);
  }

  /// Gửi `XP0001FIND` tới địa chỉ broadcast rồi gom các máy in trả lời trong [timeout].
  /// Lỗi socket (cổng 9000 bận, mạng chặn broadcast) → danh sách rỗng.
  static Future<List<XprinterUdpFound>> find({
    Duration timeout = const Duration(milliseconds: 1500),
    Iterable<String> extraBroadcasts = const [],
  }) async {
    RawDatagramSocket sock;
    try {
      sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
    } catch (_) {
      try {
        sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      } catch (_) {
        return const [];
      }
    }
    final found = <String, XprinterUdpFound>{};
    final sub = sock.listen((e) {
      if (e != RawSocketEvent.read) return;
      final dg = sock.receive();
      final f = dg == null ? null : parseReply(dg.data);
      if (f != null) found[f.mac] = f;
    });
    try {
      sock.broadcastEnabled = true;
      final dests = {'255.255.255.255', ...extraBroadcasts};
      for (final d in dests) {
        try {
          sock.send(findPacket(), InternetAddress(d), port);
        } catch (_) {}
      }
      await Future<void>.delayed(timeout);
    } finally {
      await sub.cancel();
      sock.close();
    }
    return found.values.toList();
  }
}
