import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/printer_label.dart';
import 'print_relay_client.dart';
import 'print_relay_job.dart';
import 'print_relay_lan.dart';
import 'print_relay_transport.dart';

/// Trạm in: nghe hàng đợi trên [transport], giành lệnh rồi giao cho [onJob] in.
///
/// Nhiều trạm cùng nghe một hàng đợi: mỗi lệnh chỉ một trạm in (qua
/// [PrintRelayTransport.claimJob]). Lệnh quá [jobTtl] bị dọn, không in — tránh in
/// dồn bill cũ khi trạm vừa mở lại app.
///
/// Muốn trạm chạy khi tắt màn hình (Android) thì bật thêm
/// [PrinterLabel.startKeepAlive].
class PrintRelayStation {
  PrintRelayStation({
    required this.transport,
    required this.onJob,
    this.canHandle,
    this.info = const {},
    this.jobTtl = const Duration(minutes: 2),
    this.onPrinted,
    this.lanServer,
    this.stationId,
    void Function(String message)? log,
  }) : _log = log ?? debugPrint;

  /// Mã trạm (báo kèm [info] dưới khoá `id`): lệnh nhắm tới trạm khác thì bỏ qua.
  final String? stationId;

  /// Lệnh nhắm tới trạm cụ thể (máy in tích hợp) mà không phải trạm này.
  bool isForOtherStation(PrintRelayJob job) {
    final target = job.printer.stationId;
    return target != null && target != stationId;
  }

  /// Có thì trạm nhận thêm lệnh thẳng qua mạng nội bộ (xem [PrintRelayLanServer]).
  final PrintRelayLanServer? lanServer;

  final PrintRelayTransport transport;

  /// In lệnh [job], trả `true` khi in thành công.
  final Future<bool> Function(PrintRelayJob job) onJob;

  /// Trạm này có in được lệnh không, kiểm tra trước khi giành lệnh — VD lệnh tới
  /// máy in USB chỉ trạm đang cắm đúng máy in đó mới nhận, để quán nhiều trạm
  /// thì lệnh không rơi vào trạm không in được. Mặc định [defaultCanHandle].
  final Future<bool> Function(PrintRelayJob job)? canHandle;

  /// Thông tin trạm báo lên khi trực tuyến (VD `{'name': 'Máy thu ngân'}`).
  final Map<String, Object?> info;
  final Duration jobTtl;

  /// Gọi sau mỗi lệnh in xong, kèm tổng số lệnh đã in hộ.
  final void Function(PrintRelayJob job, bool success, int printedCount)?
  onPrinted;

  final void Function(String message) _log;

  /// Nhận mọi lệnh tới máy in LAN; lệnh tới máy in USB chỉ nhận khi máy in đó
  /// đang cắm vào thiết bị này.
  static Future<bool> defaultCanHandle(PrintRelayJob job) async {
    // Máy in tích hợp: plugin không biết thiết bị có máy in sẵn không — app tự
    // quyết qua `canHandle`.
    if (job.printer.isBuiltIn) return false;
    if (job.printer.isUsb) {
      return PrinterLabel.isUsbAttached(job.printer.usbId);
    }
    // Máy in LAN: chỉ nhận khi trạm này CÙNG dải mạng với máy in — công ty có
    // nhiều Agent ở các mạng khác nhau thì Agent sai mạng không giành mất lệnh
    // (giành rồi in lỗi trong khi Agent đúng mạng in được).
    final ip = job.printer.address.trim();
    if (ip.split('.').length != 4) return true;
    return PrintRelayClient.isOnSameSubnet(ip);
  }

  StreamSubscription<PrintRelayQueuedJob>? _jobsSub;

  /// Số lệnh đã in hộ thành công từ lúc bật.
  int printedCount = 0;

  bool get isRunning => _jobsSub != null;

  Future<bool> start() async {
    if (isRunning) return true;
    try {
      final lan = lanServer == null ? null : await lanServer!.start(_handleLan);
      await transport.goOnline({
        ...info,
        if (stationId != null) 'id': stationId,
        if (lan != null) 'lan': lan,
      });
      _jobsSub = transport.watchJobs().listen(
        (queued) => unawaited(_handle(queued)),
        onError: (Object e) => _log('[PRINT-RELAY] Nghe hàng đợi lỗi: $e'),
      );
      return true;
    } catch (e) {
      _log('[PRINT-RELAY] Bật trạm in lỗi: $e');
      await stop();
      return false;
    }
  }

  /// Báo lại thông tin trạm (VD IP nội bộ của trạm vừa đổi sau khi nối lại mạng).
  Future<void> refreshInfo(Map<String, Object?> newInfo) async {
    if (!isRunning) return;
    try {
      await transport.goOnline({
        ...newInfo,
        if (stationId != null) 'id': stationId,
      });
    } catch (e) {
      _log('[PRINT-RELAY] Báo lại thông tin trạm lỗi: $e');
    }
  }

  Future<void> stop() async {
    await _jobsSub?.cancel();
    _jobsSub = null;
    await lanServer?.stop();
    try {
      await transport.goOffline();
    } catch (_) {}
  }

  Future<void> _handle(PrintRelayQueuedJob queued) async {
    final id = queued.id;
    try {
      final job = PrintRelayJob.fromMap(id, queued.data);
      final createdAt = job?.createdAt;
      if (job == null ||
          createdAt == null ||
          DateTime.now().millisecondsSinceEpoch - createdAt >
              jobTtl.inMilliseconds) {
        // Lệnh hỏng / quá hạn (kể cả lệnh đã xong mà máy gửi chưa kịp xoá): dọn.
        if (queued.data is Map) await transport.deleteJob(id);
        return;
      }
      if (job.status != PrintRelayStatus.pending) return;
      if (isForOtherStation(job)) return;
      if (!await (canHandle ?? defaultCanHandle)(job)) {
        _log('[PRINT-RELAY] Lệnh $id: trạm này không in được, bỏ qua');
        // Lệnh nhắm thẳng trạm này (không trạm nào khác nhận): báo lỗi ngay để
        // máy gửi khỏi chờ hết thời gian rồi báo nhầm "Agent không phản hồi".
        if (stationId != null && job.printer.stationId == stationId) {
          await transport.ackJob(id).catchError((Object _) {});
          await transport.completeJob(id, success: false);
        }
        return;
      }
      // Lệnh nhắm thẳng trạm này (máy gửi chỉ thấy một Agent): không trạm nào
      // khác nhận nên bỏ bước giành lệnh — in nhanh hơn một vòng mạng.
      final targeted = stationId != null && job.printer.stationId == stationId;
      if (!targeted && !await transport.claimJob(id)) {
        _log('[PRINT-RELAY] Lệnh $id đã có trạm khác nhận');
        return;
      }

      // Báo máy gửi "đã nhận" ngay (không chờ): máy gửi thôi lo trạm đã tắt.
      unawaited(transport.ackJob(id).catchError((Object _) {}));
      _log(
        '[PRINT-RELAY] Lệnh $id: nhận sau '
        '${DateTime.now().millisecondsSinceEpoch - createdAt}ms',
      );
      final ok = await _print(job);
      await transport.completeJob(id, success: ok);
    } catch (e, s) {
      _log('[PRINT-RELAY] Xử lý lệnh $id lỗi: $e\n$s');
    }
  }

  /// Lệnh tới thẳng qua mạng nội bộ: không cần giành lệnh (chỉ một trạm nhận).
  /// `null` khi trạm này không in được — máy gửi chuyển sang hàng đợi.
  Future<bool?> _handleLan(PrintRelayJob job) async {
    if (isForOtherStation(job)) return null;
    if (!await (canHandle ?? defaultCanHandle)(job)) return null;
    return _print(job);
  }

  Future<bool> _print(PrintRelayJob job) async {
    final sw = Stopwatch()..start();
    var ok = false;
    try {
      ok = await onJob(job);
    } catch (e, s) {
      _log('[PRINT-RELAY] In lệnh ${job.id} lỗi: $e\n$s');
    }
    _log(
      '[PRINT-RELAY] Lệnh ${job.id} (${job.kind.name}, '
      '${job.payloadBytes ~/ 1024}KB): in ${sw.elapsedMilliseconds}ms, '
      '${ok ? 'thành công' : 'lỗi'}',
    );
    if (ok) printedCount++;
    onPrinted?.call(job, ok, printedCount);
    return ok;
  }
}
