import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Cấu hình mạng một máy in Gprinter (module Ethernet) khai báo qua UDP.
class GprinterNetInfo {
  const GprinterNetInfo({
    required this.mac,
    required this.ip,
    required this.mask,
    required this.gateway,
    required this.dhcp,
    this.name,
    this.version,
    this.serial,
  });

  /// MAC dạng `AA:BB:CC:DD:EE:FF`.
  final String mac;
  final String ip;
  final String mask;
  final String gateway;
  final bool dhcp;
  final String? name;
  final String? version;
  final String? serial;

  @override
  String toString() =>
      'GprinterNetInfo(mac: $mac, ip: $ip, mask: $mask, gateway: $gateway, dhcp: $dhcp)';
}

/// Giao thức cấu hình mạng máy in Gprinter qua UDP broadcast — lấy từ SDK Android chính
/// thức của hãng (`com.gprinter.udp.ethernet.*`, `UdpPort`): gửi tới `255.255.255.255:3000`.
///
/// - Dò máy: `B[]G`. Máy trả chuỗi dạng `KEY:VALUE;KEY:VALUE;...` (MAC, IP, SUBNETWORK,
///   GATEWAY, DHCP, DTIMEOUT, PRNPORT, DEVICENAME, VER, SN...).
/// - Đặt cấu hình (đều có phần đầu `B[` + MAC(6 byte) + `]`): `YJKE02GPRINTERGPI`+IP,
///   `...GPS`+netmask, `...GPW`+gateway, `...GPD`+`1`/`0` (DHCP bật/tắt), `EJKE02` (khởi động
///   lại mạng). Địa chỉ viết dạng chữ (`192.168.1.50`).
///
/// Chưa kiểm chứng trên máy Gprinter thật trong phiên viết — xem test và ghi chú trong app.
abstract final class GprinterUdp {
  static const int port = 3000;
  static const String _setPrefix = 'YJKE02GPRINTERGP';

  /// Gói dò máy.
  static final List<int> searchPacket = utf8.encode('B[]G');

  static List<int> _header(List<int> mac) => [0x42, 0x5B, ...mac, 0x5D];

  /// 6 byte của MAC `AA:BB:CC:DD:EE:FF` (hoặc không dấu); `null` nếu không hợp lệ.
  static List<int>? macBytes(String mac) {
    final hex = mac.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (hex.length != 12) return null;
    return [
      for (var i = 0; i < 12; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }

  static List<int> _command(List<int> mac, String suffix, String value) => [
    ..._header(mac),
    ...ascii.encode('$_setPrefix$suffix'),
    ...ascii.encode(value),
  ];

  static List<int> ipPacket(List<int> mac, String ip) => _command(mac, 'I', ip);

  static List<int> maskPacket(List<int> mac, String mask) =>
      _command(mac, 'S', mask);

  static List<int> gatewayPacket(List<int> mac, String gateway) =>
      _command(mac, 'W', gateway);

  static List<int> dhcpPacket(List<int> mac, {required bool dhcp}) =>
      _command(mac, 'D', dhcp ? '1' : '0');

  static List<int> rebootPacket(List<int> mac) => [
    ..._header(mac),
    ...ascii.encode('EJKE02'),
  ];

  /// Tách chuỗi `KEY:VALUE;KEY:VALUE` thành bản đồ (khoá viết hoa).
  static Map<String, String> parseResponse(List<int> data) {
    final text = String.fromCharCodes(data.where((b) => b != 0));
    final map = <String, String>{};
    for (final part in text.split(';')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final i = p.indexOf(':');
      if (i <= 0) continue;
      // Giữ giá trị ĐẦU TIÊN: module mạng không xoá phần thừa của gói trả lời trước nên
      // cuối gói có thể còn đuôi rác lặp khoá (đo được: `...;PRNPORT:9100;T:30;IP:1`).
      // Lấy giá trị cuối thì IP thành "1" -> máy bị bỏ qua khi dò.
      map.putIfAbsent(
        p.substring(0, i).trim().toUpperCase(),
        () => p.substring(i + 1).trim(),
      );
    }
    return map;
  }

  /// Thông tin máy từ gói trả lời dò, `null` nếu không phải gói của máy in Gprinter
  /// (thiếu MAC / IP hợp lệ — gồm cả gói dội lại của chính lệnh đã gửi).
  static GprinterNetInfo? parseDevice(List<int> data) {
    final map = parseResponse(data);
    final macRaw = map['MAC'];
    final ip = map['IP'];
    if (macRaw == null || ip == null) return null;
    final bytes = macBytes(macRaw);
    if (bytes == null || !_isIpv4(ip)) return null;
    final mac = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
    return GprinterNetInfo(
      mac: mac,
      ip: ip,
      mask: map['SUBNETWORK'] ?? '',
      gateway: map['GATEWAY'] ?? '',
      dhcp: (map['DHCP'] ?? '').toLowerCase() == 'enable',
      name: map['DEVICENAME'],
      version: map['VER'],
      serial: map['SN'],
    );
  }

  static bool _isIpv4(String s) {
    final parts = s.split('.');
    return parts.length == 4 &&
        parts.every((p) {
          final n = int.tryParse(p);
          return n != null && n >= 0 && n <= 255;
        });
  }

  /// Danh sách đích broadcast: `255.255.255.255` và `x.y.z.255` của các dải thiết bị đang có.
  static Future<List<InternetAddress>> _targets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      for (final nic in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final a in nic.addresses) {
          final ip = a.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
            targets.add('${ip.split('.').take(3).join('.')}.255');
          }
        }
      }
    } catch (_) {}
    return targets.map(InternetAddress.new).toList();
  }

  /// Dò máy in Gprinter bằng UDP broadcast, chờ [wait] rồi trả mọi máy đã trả lời.
  /// Gửi gói dò hai lần cách nhau [wait]/3 để bù gói UDP bị mất.
  static const Duration _minSearch = Duration(milliseconds: 700);
  static const Duration _quiet = Duration(milliseconds: 600);

  static Future<List<GprinterNetInfo>> search({
    Duration wait = const Duration(milliseconds: 1500),
  }) async {
    RawDatagramSocket? socket;
    final found = <String, GprinterNetInfo>{};
    final sw = Stopwatch()..start();
    var lastFoundAt = -1;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket?.receive();
        if (dg == null) return;
        final info = parseDevice(dg.data);
        if (info != null) {
          found[info.mac] = info;
          lastFoundAt = sw.elapsedMilliseconds;
        }
      }, onError: (Object _) {});
      // Hai lần gửi cách nhau (UDP có thể mất gói); máy trả lời bằng gói dữ liệu riêng chứ
      // không dội lại nên gửi lặp không gây vòng lặp gói.
      final targets = await _targets();
      for (var i = 0; i < 2; i++) {
        for (final target in targets) {
          try {
            socket.send(searchPacket, target, port);
          } catch (_) {}
        }
        if (i == 0) await Future<void>.delayed(wait ~/ 3);
      }
      // Trả sớm như quét Xprinter trên Android: đã có máy trả lời, qua lần gửi thứ hai
      // và [_quiet] không có máy mới (máy in trả lời trong vài trăm ms) — không chờ đủ
      // [wait] mỗi lần bấm in. Không có máy nào thì vẫn chờ đủ.
      while (sw.elapsed < wait) {
        final quiet =
            lastFoundAt >= 0 &&
            sw.elapsedMilliseconds >= _minSearch.inMilliseconds &&
            sw.elapsedMilliseconds - lastFoundAt >= _quiet.inMilliseconds;
        if (quiet) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await sub.cancel();
    } catch (_) {
    } finally {
      socket?.close();
    }
    return found.values.toList();
  }

  /// Gửi lần lượt các gói [packets] (broadcast) cách nhau [gap].
  static Future<bool> _sendAll(
    List<List<int>> packets, {
    Duration gap = const Duration(milliseconds: 150),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final targets = await _targets();
      for (final p in packets) {
        for (final target in targets) {
          try {
            socket.send(p, target, port);
          } catch (_) {}
        }
        await Future<void>.delayed(gap);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.close();
    }
  }

  /// Đặt IP tĩnh cho máy in [mac] (thứ tự theo SDK của hãng: tắt DHCP → IP → gateway →
  /// netmask → khởi động lại mạng). `true` khi đã gửi được; xác minh bằng [search].
  static Future<bool> setStatic({
    required String mac,
    required String ip,
    required String mask,
    required String gateway,
  }) async {
    final m = macBytes(mac);
    if (m == null || !_isIpv4(ip) || !_isIpv4(mask) || !_isIpv4(gateway)) {
      return false;
    }
    return _sendAll([
      dhcpPacket(m, dhcp: false),
      ipPacket(m, ip),
      gatewayPacket(m, gateway),
      maskPacket(m, mask),
      rebootPacket(m),
    ]);
  }

  /// Chuyển máy in [mac] sang DHCP rồi khởi động lại mạng.
  static Future<bool> setDhcp({required String mac}) async {
    final m = macBytes(mac);
    if (m == null) return false;
    return _sendAll([dhcpPacket(m, dhcp: true), rebootPacket(m)]);
  }
}
