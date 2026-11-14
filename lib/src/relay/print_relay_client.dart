import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/printer_label.dart';
import 'print_relay_job.dart';
import 'print_relay_lan.dart';
import 'print_relay_transport.dart';

/// Phía máy gửi: quyết định có cần đi qua trạm in không và gửi lệnh / chờ kết quả.
class PrintRelayClient {
  PrintRelayClient({
    this.resultTimeout = const Duration(seconds: 20),
    this.ackTimeout = const Duration(seconds: 6),
    this.onStationsChanged,
    void Function(String message)? log,
  }) : _log = log ?? debugPrint;

  /// Gọi mỗi khi danh sách trạm của kênh thay đổi (trạm bật / tắt / đổi thông
  /// tin) — để giao diện cập nhật ngay, không chờ hỏi lại.
  final VoidCallback? onStationsChanged;

  /// Thời gian chờ trạm báo kết quả.
  final Duration resultTimeout;

  /// Thời gian chờ trạm báo "đã nhận" (tính từ lúc lệnh lên hàng đợi). Quá hạn =
  /// trạm đã tắt / mất mạng mà danh sách chưa kịp gỡ (Firebase / MQTT có thể mất
  /// tới cả phút mới biết) — báo lỗi ngay thay vì chờ hết [resultTimeout].
  final Duration ackTimeout;

  /// Trạm vừa không phản hồi: ẩn khỏi danh sách tới mốc thời gian, trừ khi trạm
  /// báo lại thông tin khác (VD bật lại → mã LAN mới) — lệnh sau khỏi phải chờ.
  final Map<Object?, ({DateTime until, String signature})> _silent = {};

  static String _signature(Map<Object?, Object?> station) {
    final lan = station['lan'];
    return lan is Map ? '${lan['token']}' : station.toString();
  }

  bool _isSilent(Map<Object?, Object?> station) {
    final mark = _silent[station['id']];
    if (mark == null) return false;
    if (DateTime.now().isAfter(mark.until) ||
        mark.signature != _signature(station)) {
      _silent.remove(station['id']);
      return false;
    }
    return true;
  }

  void _markSilent(Iterable<Map<Object?, Object?>> stations) {
    for (final station in stations) {
      _silent[station['id']] = (
        until: DateTime.now().add(const Duration(seconds: 60)),
        signature: _signature(station),
      );
    }
  }

  final void Function(String message) _log;

  /// Thiết bị này in thẳng được tới [printer] không:
  /// - máy in LAN: thiết bị có IP cùng dải /24 với máy in;
  /// - máy in USB: máy in đang cắm vào thiết bị này ([PrinterLabel.isUsbAttached]).
  ///
  /// Không xác định được (địa chỉ lạ, không đọc được mạng) thì coi như in thẳng
  /// được — giữ cách in cũ.
  static Future<bool> canPrintDirectly(PrintRelayPrinter printer) async {
    if (printer.isBuiltIn) return false;
    final ip = printer.address.trim();
    if (printer.isUsb) {
      final usbId = printer.usbId.trim();
      return usbId.isEmpty || await PrinterLabel.isUsbAttached(usbId);
    }
    if (ip.split('.').length != 4) return true;
    return isOnSameSubnet(ip);
  }

  /// Thiết bị có IP cùng dải /24 với [printerIp] không.
  static Future<bool> isOnSameSubnet(String printerIp) async {
    final prefix = printerIp.split('.').take(3).join('.');
    final mine = await PrintRelayLanServer.localIpv4s();
    // Không đọc được mạng: coi như cùng mạng, in trực tiếp như cũ.
    if (mine.isEmpty) return true;
    return mine.any((ip) => ip.split('.').take(3).join('.') == prefix);
  }

  // Theo dõi liên tục trạng thái trạm của một hàng đợi (một kết nối, giữ suốt
  // phiên) để mỗi lệnh in biết ngay có trạm hay không, không phải hỏi lại qua
  // mạng (~270ms qua 4G mỗi lần).
  PrintRelayTransport? _watched;
  StreamSubscription<List<Map<Object?, Object?>>>? _stationsSub;
  List<Map<Object?, Object?>>? _stations;

  /// Các trạm còn dùng được (bỏ trạm vừa không phản hồi); `null` khi chưa biết.
  List<Map<Object?, Object?>>? get _alive =>
      _stations?.where((s) => !_isSilent(s)).toList();

  bool? get _stationOnline => _alive?.isNotEmpty;

  /// Thông tin các trạm đang trực tuyến của kênh đang theo dõi (VD `id`, `name`,
  /// `builtIn`); rỗng khi chưa biết.
  List<Map<Object?, Object?>> get stations =>
      List.unmodifiable(_alive ?? const []);

  /// Hàng đợi [transport] có trạm nào đang trực tuyến không. Lần đầu chờ tối đa
  /// [firstWait].
  Future<bool> hasOnlineStation(
    PrintRelayTransport transport, {
    Duration firstWait = const Duration(seconds: 3),
  }) async {
    if (!identical(_watched, transport)) {
      await _stationsSub?.cancel();
      _watched = transport;
      _stations = null;
      _stationsSub = transport.watchStations().listen(
        (stations) {
          _stations = stations;
          onStationsChanged?.call();
        },
        onError: (Object e) {
          _log('[PRINT-RELAY] Theo dõi trạm in lỗi: $e');
          _watched = null;
          _stations = null;
          onStationsChanged?.call();
        },
      );
    }
    final known = _stationOnline;
    if (known != null) return known;
    final deadline = DateTime.now().add(firstWait);
    while (_stationOnline == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _stationOnline ?? false;
  }

  /// Ngừng theo dõi trạm (VD khi đăng xuất).
  Future<void> dispose() async {
    await _stationsSub?.cancel();
    _stationsSub = null;
    _watched = null;
    _stations = null;
  }

  /// Gửi [job] tới trạm: trạm cùng mạng LAN thì gửi thẳng qua mạng nội bộ
  /// ([PrintRelayLanClient]); không được thì đưa lên hàng đợi rồi chờ trạm báo kết
  /// quả (lệnh luôn được xoá khỏi hàng đợi sau đó).
  Future<PrintRelayResult> send(
    PrintRelayTransport transport,
    PrintRelayJob job,
  ) async {
    // Chỉ một Agent trực tuyến: nhắm thẳng Agent đó — Agent in luôn, bỏ bước
    // giành lệnh (Firebase: 1 vòng giao dịch; MQTT: ~0,5s gom gói giành). Nhiều
    // Agent thì để các Agent giành lệnh như cũ (tránh in trùng).
    final online = _alive ?? const <Map<Object?, Object?>>[];
    if (job.printer.stationId == null && online.length == 1) {
      final only = online.first['id'];
      if (only is String && only.isNotEmpty) {
        job = job.withPrinter(job.printer.withStation(only));
      }
    }
    final target = job.printer.stationId;
    // Lệnh nhắm MỘT Agent cụ thể (VD máy in tích hợp của Agent đó) mà Agent ấy
    // không trực tuyến: Agent khác sẽ bỏ qua lệnh → báo ngay, không đẩy lên hàng
    // đợi rồi chờ hết thời gian.
    if (target != null && !online.any((s) => s['id'] == target)) {
      _log('[PRINT-RELAY] Agent $target không trực tuyến — không gửi lệnh');
      return PrintRelayResult.noResponse;
    }
    for (final station in online) {
      if (target != null && station['id'] != target) continue;
      final lan = station['lan'];
      if (lan is! Map) continue;
      final sw = Stopwatch()..start();
      final result = await PrintRelayLanClient.send(
        lan,
        job,
        resultTimeout: resultTimeout,
      );
      if (result == null) continue;
      _log(
        '[PRINT-RELAY] Lệnh ${job.kind.name} qua mạng nội bộ: ${result.name} '
        'sau ${sw.elapsedMilliseconds}ms',
      );
      return result;
    }
    final result = await _sendViaQueue(transport, job);
    if (result == PrintRelayResult.noResponse) {
      _markSilent(online.where((s) => target == null || s['id'] == target));
    }
    return result;
  }

  Future<PrintRelayResult> _sendViaQueue(
    PrintRelayTransport transport,
    PrintRelayJob job,
  ) async {
    String? id;
    try {
      final data = job.toMap()
        ..['status'] = PrintRelayStatus.pending
        ..['createdAt'] = DateTime.now().millisecondsSinceEpoch;
      final jobId = id = await transport.submitJob(data);
      final sent = DateTime.now();
      _log(
        '[PRINT-RELAY] Gửi lệnh ${job.kind.name} $jobId tới trạm in '
        '(${job.payloadBytes ~/ 1024}KB)',
      );
      final status = await _waitResult(transport, jobId);
      if (status == null) return PrintRelayResult.noResponse;
      final ok = status == PrintRelayStatus.done;
      _log(
        '[PRINT-RELAY] Lệnh $jobId: ${ok ? 'đã in' : 'lỗi'} sau '
        '${DateTime.now().difference(sent).inMilliseconds}ms kể từ lúc gửi',
      );
      return ok ? PrintRelayResult.done : PrintRelayResult.failed;
    } on TimeoutException {
      return PrintRelayResult.timeout;
    } catch (e) {
      _log('[PRINT-RELAY] Gửi lệnh in qua trạm lỗi: $e');
      return id == null
          ? PrintRelayResult.notDelivered
          : PrintRelayResult.failed;
    } finally {
      final jobId = id;
      if (jobId != null) {
        unawaited(transport.deleteJob(jobId).catchError((_) {}));
      }
    }
  }

  /// Chờ kết quả lệnh [jobId]: trước hết chờ trạm báo "đã nhận" trong
  /// [ackTimeout] (không có = trạm đã tắt → `null`), rồi chờ in xong trong
  /// [resultTimeout] (quá hạn → [TimeoutException]).
  Future<String?> _waitResult(
    PrintRelayTransport transport,
    String jobId,
  ) async {
    final acked = Completer<void>();
    final finished = Completer<String>();
    final sub = transport
        .watchJobStatus(jobId)
        .listen(
          (s) {
            final done =
                s == PrintRelayStatus.done || s == PrintRelayStatus.failed;
            if ((done || s == PrintRelayStatus.printing) &&
                !acked.isCompleted) {
              acked.complete();
            }
            if (done && !finished.isCompleted) finished.complete(s);
          },
          onError: (Object e) {
            if (!finished.isCompleted) finished.completeError(e);
          },
        );
    try {
      try {
        await acked.future.timeout(ackTimeout);
      } on TimeoutException {
        _log(
          '[PRINT-RELAY] Lệnh $jobId: máy Agent không phản hồi sau '
          '${ackTimeout.inMilliseconds}ms — coi như đã tắt',
        );
        return null;
      }
      return await finished.future.timeout(resultTimeout);
    } finally {
      unawaited(sub.cancel());
    }
  }
}
