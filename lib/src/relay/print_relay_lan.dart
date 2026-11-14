import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'print_relay_job.dart';

/// Đường nội bộ nhanh giữa máy gửi và trạm in khi hai máy cùng mạng LAN: gửi thẳng
/// lệnh qua TCP thay vì đi vòng qua hàng đợi trên mạng (nhanh hơn vài trăm ms, vẫn
/// in được khi quán mất internet nhưng còn Wi-Fi nội bộ).
///
/// Giao thức: mỗi kết nối một lệnh. Máy gửi viết một dòng JSON
/// `{"token": ..., "job": PrintRelayJob.toMap()}` rồi chờ một dòng
/// `{"status": "done" | "failed" | "skip"}`. Sai [token] thì trạm đóng kết nối —
/// token ngẫu nhiên mỗi lần bật trạm, chỉ báo cho máy cùng quán qua hàng đợi
/// (đã xác thực), nên máy lạ trong cùng Wi-Fi không gửi lệnh in được.
class PrintRelayLanServer {
  PrintRelayLanServer({
    this.port = defaultPort,
    void Function(String message)? log,
  }) : _log = log ?? debugPrint;

  static const int defaultPort = 9101;

  /// Lệnh lớn nhất nhận qua mạng nội bộ (ảnh hoá đơn / tem đã thu nhỏ chỉ vài trăm KB).
  static const int maxRequestBytes = 16 * 1024 * 1024;

  final int port;
  final void Function(String message) _log;

  ServerSocket? _server;
  String? _token;

  /// Bật máy chủ, trả thông tin để báo cho máy gửi (`{ips, port, token}`) hoặc
  /// `null` khi không mở được cổng. [handle] in lệnh: `true` / `false` là in được
  /// hay không, `null` khi trạm này không in được lệnh đó (máy gửi đi đường khác).
  Future<Map<String, Object?>?> start(
    Future<bool?> Function(PrintRelayJob job) handle,
  ) async {
    await stop();
    ServerSocket server;
    try {
      server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
      ).catchError((_) => ServerSocket.bind(InternetAddress.anyIPv4, 0));
    } catch (e) {
      _log('[PRINT-RELAY] Không mở được cổng nội bộ: $e');
      return null;
    }
    _server = server;
    final random = Random.secure();
    final token = _token = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    server.listen((client) => unawaited(_serve(client, token, handle)));
    final ips = await localIpv4s();
    _log(
      '[PRINT-RELAY] Trạm nhận lệnh nội bộ ở ${ips.join(', ')}:${server.port}',
    );
    return {'ips': ips, 'port': server.port, 'token': token};
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    await server?.close();
  }

  Future<void> _serve(
    Socket client,
    String token,
    Future<bool?> Function(PrintRelayJob job) handle,
  ) async {
    try {
      final line = await _readLine(client).timeout(const Duration(seconds: 15));
      final request = line == null ? null : jsonDecode(line);
      if (request is! Map || request['token'] != token || _token != token) {
        return;
      }
      final job = PrintRelayJob.fromMap('lan', request['job']);
      final ok = job == null ? false : await handle(job);
      client.write(
        '${jsonEncode({'status': ok == null ? 'skip' : (ok ? PrintRelayStatus.done : PrintRelayStatus.failed)})}\n',
      );
      await client.flush();
    } catch (e) {
      _log('[PRINT-RELAY] Lệnh nội bộ lỗi: $e');
    } finally {
      client.destroy();
    }
  }

  static Future<String?> _readLine(Socket socket) async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in socket) {
      final newline = chunk.indexOf(0x0A);
      if (newline >= 0) {
        buffer.add(chunk.sublist(0, newline));
        return utf8.decode(buffer.takeBytes());
      }
      buffer.add(chunk);
      if (buffer.length > maxRequestBytes) return null;
    }
    return null;
  }

  static List<String>? _ipsCache;
  static DateTime _ipsAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// IPv4 nội bộ của thiết bị (bỏ VPN), để máy gửi biết đường tới trạm. Dùng lại
  /// kết quả trong 2s — luồng in gọi nhiều lần liên tiếp.
  static Future<List<String>> localIpv4s() async {
    final cached = _ipsCache;
    if (cached != null &&
        DateTime.now().difference(_ipsAt) < const Duration(seconds: 2)) {
      return cached;
    }
    final fresh = await _readLocalIpv4s();
    _ipsCache = fresh;
    _ipsAt = DateTime.now();
    return fresh;
  }

  static Future<List<String>> _readLocalIpv4s() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      return [
        for (final n in interfaces)
          if (!RegExp(r'^(tun|utun|ppp|ipsec|wg|tap)').hasMatch(n.name))
            for (final a in n.addresses)
              if (!a.isLoopback) a.address,
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// Phía máy gửi của [PrintRelayLanServer].
abstract final class PrintRelayLanClient {
  /// Trạm không tới được qua mạng nội bộ gần đây (`ip:port` → bỏ qua tới mốc).
  static final Map<String, DateTime> _unreachableUntil = {};

  /// Gửi [job] thẳng tới trạm [lan] (thông tin trạm báo: `{ips, port, token}`).
  /// Thử các IP cùng dải với thiết bị này trước. Trả `null` khi không tới được trạm
  /// qua mạng nội bộ hoặc trạm bảo không in được (nơi gọi đi đường hàng đợi).
  static Future<PrintRelayResult?> send(
    Map<Object?, Object?> lan,
    PrintRelayJob job, {
    Duration connectTimeout = const Duration(milliseconds: 800),
    Duration resultTimeout = const Duration(seconds: 20),
  }) async {
    final token = lan['token'];
    final port = lan['port'];
    final ips = lan['ips'];
    if (token is! String || port is! int || ips is! List) return null;

    final myPrefixes = (await PrintRelayLanServer.localIpv4s())
        .map((ip) => ip.split('.').take(3).join('.'))
        .toSet();
    // Chỉ thử IP cùng dải /24 — IP khác dải gần như chắc chắn không tới được và
    // làm chậm lệnh in thêm thời gian chờ kết nối.
    final candidates = [
      for (final ip in ips)
        if (ip is String &&
            myPrefixes.contains(ip.split('.').take(3).join('.')))
          ip,
    ];
    for (final ip in candidates) {
      // Vừa thử không tới được (VD Wi-Fi chặn các máy nói chuyện với nhau): bỏ
      // qua 60s, không bắt mỗi lệnh in chờ thêm [connectTimeout].
      final blockedUntil = _unreachableUntil['$ip:$port'];
      if (blockedUntil != null && DateTime.now().isBefore(blockedUntil)) {
        continue;
      }
      Socket socket;
      try {
        socket = await Socket.connect(ip, port, timeout: connectTimeout);
        _unreachableUntil.remove('$ip:$port');
      } catch (_) {
        _unreachableUntil['$ip:$port'] = DateTime.now().add(
          const Duration(seconds: 60),
        );
        continue;
      }
      try {
        socket.write('${jsonEncode({'token': token, 'job': job.toMap()})}\n');
        await socket.flush();
      } catch (_) {
        // Chưa gửi được lệnh: an toàn để thử đường khác.
        socket.destroy();
        continue;
      }
      // Lệnh ĐÃ tới trạm: từ đây lỗi nào cũng không được trả `null` (nơi gọi sẽ
      // gửi lại qua hàng đợi → in trùng). Không rõ kết quả thì báo quá thời gian.
      try {
        final line = await PrintRelayLanServer._readLine(
          socket,
        ).timeout(resultTimeout);
        // Trạm đóng kết nối không trả lời = từ chối (sai mã, VD trạm vừa bật lại)
        // trước khi in → thử đường khác.
        if (line == null) return null;
        final reply = jsonDecode(line);
        final status = reply is Map ? reply['status'] : null;
        if (status == PrintRelayStatus.done) return PrintRelayResult.done;
        if (status == PrintRelayStatus.failed) return PrintRelayResult.failed;
        // `skip`: trạm chưa in (không in được lệnh này) → thử đường khác.
        if (status == 'skip') return null;
        return PrintRelayResult.timeout;
      } catch (_) {
        return PrintRelayResult.timeout;
      } finally {
        socket.destroy();
      }
    }
    return null;
  }
}

/// Kết quả gửi lệnh qua trạm in.
enum PrintRelayResult {
  /// Trạm đã in xong.
  done,

  /// Trạm nhận lệnh nhưng in lỗi.
  failed,

  /// Quá thời gian chờ trạm báo kết quả (lệnh có thể vẫn đang in).
  timeout,

  /// Không gửi được lệnh lên hàng đợi — chưa chắc tới trạm, nơi gọi có thể thử
  /// in trực tiếp.
  notDelivered,

  /// Trạm không báo "đã nhận" trong thời gian ngắn — trạm đã tắt / mất mạng.
  /// Lệnh đã bị gỡ khỏi hàng đợi.
  noResponse,
}
