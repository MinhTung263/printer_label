import 'dart:async';
import 'dart:io';

import 'arp_table.dart';
import 'xprinter_udp.dart';

/// Vấn đề của một máy in tìm thấy bằng lệnh dò UDP.
enum LanPrinterIssue {
  /// Bình thường.
  none,

  /// Địa chỉ IP của máy in đang bị THIẾT BỊ KHÁC dùng (bảng ARP trả về MAC khác với MAC
  /// máy in tự báo): in tới IP đó sẽ vào nhầm thiết bị — cần đổi IP máy in.
  ipConflict,

  /// Máy in có trả lời UDP nhưng không mở được cổng in từ máy này (khác dải mạng / mạng
  /// chặn).
  unreachable,
}

/// Một máy in LAN tìm thấy (mở cổng RAW 9100).
class LanPrinterFound {
  const LanPrinterFound(
    this.host,
    this.port, {
    this.mac,
    this.issue = LanPrinterIssue.none,
  });

  final String host;
  final int port;

  /// MAC máy in tự báo (lệnh dò UDP); `null` khi chỉ thấy qua cổng 9100.
  final String? mac;
  final LanPrinterIssue issue;

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

/// Quét máy in LAN: thử mở cổng [port] trên các địa chỉ của mạng máy này. Không cần
/// driver hay giao thức riêng của hãng.
///
/// [wide] (mặc định): quét RỘNG hơn — cả khối 4 dải /24 liền nhau quanh mỗi card mạng
/// (phủ mạng /23, /22 mà quán hay cấu hình: `192.168.0.x` + `192.168.1.x`...) và mọi
/// máy đã thấy trong bảng ARP (kể cả ngoài các dải đó). [wide] = `false`: chỉ dải /24
/// của máy (nhanh, dùng khi tìm lại máy in theo MAC).
abstract final class LanPrinterScanner {
  /// Số máy tối đa một lượt quét rộng (khối /22 của hai card mạng).
  static const int maxHosts = 2100;

  static Future<List<LanPrinterFound>> scan({
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 400),
    int parallel = 128,
    bool wide = true,
    void Function(LanPrinterFound found)? onFound,
  }) async {
    final nics = <String>[];
    for (final nic in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final a in nic.addresses) {
        if (a.isLoopback || a.isLinkLocal) continue;
        nics.add(a.address);
      }
    }
    final hosts = await scanTargets(
      nics,
      wide: wide,
      arp: wide ? (await ArpTable.read()).keys : const [],
    );
    // Dò UDP (máy in tự báo IP + MAC) chạy song song với quét cổng 9100.
    final udpFuture = wide
        ? XprinterUdp.find(
            extraBroadcasts: [
              for (final ip in nics) '${ip.split('.').take(3).join('.')}.255',
            ],
          )
        : Future.value(const <XprinterUdpFound>[]);
    final found = <LanPrinterFound>[];
    for (var i = 0; i < hosts.length; i += parallel) {
      final batch = hosts.skip(i).take(parallel);
      await Future.wait(
        batch.map((h) async {
          if (await probe(h, port: port, timeout: timeout)) {
            final f = LanPrinterFound(h, port);
            found.add(f);
            // Máy in thấy tới đâu báo tới đó (màn chọn máy in hiện ngay, không chờ quét hết).
            onFound?.call(f);
          }
        }),
      );
    }
    final merged = await mergeUdp(found, await udpFuture, port: port);
    merged.sort((a, b) => _ipKey(a.host).compareTo(_ipKey(b.host)));
    return merged;
  }

  /// Ghép máy in thấy qua cổng 9100 ([tcp]) với máy in tự báo qua UDP ([udp]): gắn MAC, phát
  /// hiện IP bị thiết bị khác dùng (MAC trong bảng ARP khác MAC máy in), thêm máy in chỉ
  /// thấy qua UDP (thử lại cổng in với thời gian chờ dài hơn: Wi-Fi chậm hay làm quét
  /// nhanh bỏ sót).
  static Future<List<LanPrinterFound>> mergeUdp(
    List<LanPrinterFound> tcp,
    List<XprinterUdpFound> udp, {
    int port = 9100,
    Future<bool> Function(String host)? probeSlow,
    Future<String?> Function(String host)? arpMacOf,
  }) async {
    final slow =
        probeSlow ??
        (h) => probe(h, port: port, timeout: const Duration(seconds: 2));
    final arpOf = arpMacOf ?? ArpTable.macOf;
    final out = {for (final f in tcp) f.host: f};
    for (final u in udp) {
      final open = out.containsKey(u.ip) || await slow(u.ip);
      final arp = ArpTable.normalize(await arpOf(u.ip) ?? '');
      final want = ArpTable.normalize(u.mac);
      final conflict = arp != null && want != null && arp != want;
      out[u.ip] = LanPrinterFound(
        u.ip,
        port,
        mac: u.mac,
        issue: conflict
            ? LanPrinterIssue.ipConflict
            : (open ? LanPrinterIssue.none : LanPrinterIssue.unreachable),
      );
    }
    return out.values.toList();
  }

  /// Các địa chỉ cần thử cho các IP máy này [localIps]: dải /24 của máy; [wide] thêm
  /// các dải /24 còn lại trong khối 4 dải liền nhau chứa nó (VD `192.168.1.x` → cả
  /// `192.168.0-3.x`), và các máy trong [arp] ngoài những dải đó. Bỏ IP của chính máy.
  static Future<List<String>> scanTargets(
    List<String> localIps, {
    bool wide = true,
    Iterable<String> arp = const [],
  }) async {
    final blocks = <String>{}; // "a.b.c"
    for (final ip in localIps) {
      final parts = ip.split('.');
      if (parts.length != 4) continue;
      final c = int.tryParse(parts[2]);
      if (c == null) continue;
      if (!wide) {
        blocks.add('${parts[0]}.${parts[1]}.$c');
        continue;
      }
      final start = c & ~3; // khối 4 dải /24 căn theo bội số của 4
      for (var k = 0; k < 4; k++) {
        blocks.add('${parts[0]}.${parts[1]}.${start + k}');
      }
    }
    final mine = localIps.toSet();
    final hosts = <String>[
      for (final b in blocks)
        for (var i = 1; i < 255; i++)
          if (!mine.contains('$b.$i')) '$b.$i',
    ];
    if (wide) {
      final seen = hosts.toSet();
      for (final h in arp) {
        if (!mine.contains(h) && seen.add(h)) hosts.add(h);
      }
    }
    // Thứ tự dò: máy đã trả lời ARP (đang bật thật) → cùng dải /24 với máy này → các dải còn lại.
    // Máy in thường nằm ở hai nhóm đầu nên hiện ra trong vài trăm ms thay vì cuối lượt quét.
    final own = {
      for (final ip in localIps)
        if (ip.split('.').length == 4) ip.split('.').take(3).join('.'),
    };
    final known = arp.toSet();
    int rank(String h) => known.contains(h)
        ? 0
        : own.contains(h.split('.').take(3).join('.'))
        ? 1
        : 2;
    final ordered = [
      for (var r = 0; r < 3; r++) ...hosts.where((h) => rank(h) == r),
    ];
    return ordered.length <= maxHosts ? ordered : ordered.sublist(0, maxHosts);
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

  /// Máy in ở [host] còn BẬT không: mở được cổng in, hoặc bị TỪ CHỐI (máy in
  /// đang phục vụ máy khác — vẫn đang bật, đừng báo mất kết nối nhầm).
  static Future<bool> isAlive(
    String host, {
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      return true;
    } on SocketException catch (e) {
      return isRefused(e);
    } catch (_) {
      return false;
    }
  }

  /// Như [isAlive] nhưng KHÔNG coi "từ chối kết nối" là đang bật trừ khi chắc đó đúng là
  /// máy in: một máy khác (điện thoại, máy tính) vừa nhận IP cũ của máy in cũng từ chối
  /// cổng 9100 — nếu tính là "bật" thì máy in đã đổi IP vẫn hiện xanh mà không in được.
  /// Từ chối chỉ tính là bật khi biết [mac] của máy in và bảng ARP của [host] khớp.
  static Future<bool> isPrinterAlive(
    String host, {
    int port = 9100,
    String? mac,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final want = ArpTable.normalize(mac ?? '');
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      if (want == null) return true;
      // Biết MAC máy in: ARP của IP này là MAC khác → đang nói chuyện với thiết bị khác.
      final arp = ArpTable.normalize(await ArpTable.macOf(host) ?? '');
      return arp == null || arp == want;
    } on SocketException catch (e) {
      if (!isRefused(e) || want == null) return false;
      return ArpTable.normalize(await ArpTable.macOf(host) ?? '') == want;
    } catch (_) {
      return false;
    }
  }

  /// Bị từ chối kết nối (ECONNREFUSED: Linux 111, macOS 61, Windows 10061).
  static bool isRefused(SocketException e) {
    final code = e.osError?.errorCode;
    return code == 111 || code == 61 || code == 10061;
  }

  /// Tìm lại máy in theo [mac] (máy in bật lại được router cấp IP mới): quét
  /// cổng in trên các dải mạng của máy này rồi đối chiếu bảng ARP. Trả `ip`
  /// (hoặc `ip:cổng`) mới, `null` khi không thấy.
  static Future<String?> findByMac(String mac, {int port = 9100}) async {
    final want = ArpTable.normalize(mac);
    if (want == null) return null;
    // Đã có trong bảng ARP (vừa liên lạc) và còn mở cổng in: khỏi quét.
    for (final e in (await ArpTable.read()).entries) {
      if (e.value == want && await isAlive(e.key, port: port)) {
        return LanPrinterFound(e.key, port).address;
      }
    }
    // Quét nhanh dải của máy trước, không thấy mới quét rộng.
    for (final wide in const [false, true]) {
      final found = await scan(port: port, wide: wide);
      final table = await ArpTable.read();
      for (final f in found) {
        if (table[f.host] == want) return f.address;
      }
    }
    return null;
  }

  static int _ipKey(String ip) =>
      ip.split('.').fold(0, (v, p) => v * 256 + (int.tryParse(p) ?? 0));
}
