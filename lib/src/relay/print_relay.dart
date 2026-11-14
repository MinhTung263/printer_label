import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/printer_label.dart';
import 'print_relay_client.dart';
import 'print_relay_job.dart';
import 'print_relay_lan.dart';
import 'print_relay_station.dart';
import 'print_relay_transport.dart';

/// Nội dung thông báo chạy nền của trạm in (Android).
class PrintRelayNotification {
  const PrintRelayNotification({
    required this.title,
    required this.waiting,
    required this.printed,
    required this.channelName,
    this.stopLabel,
  });

  /// VD "Trạm in đang chạy".
  final String title;

  /// Dòng phụ khi chưa in hộ lệnh nào, VD "Đang chờ lệnh in từ máy khác".
  final String waiting;

  /// Dòng phụ sau khi đã in hộ [count] lệnh.
  final String Function(int count) printed;

  /// Tên nhóm thông báo trong cài đặt hệ thống.
  final String channelName;

  /// Nhãn nút dừng trên thông báo; `null` thì không có nút.
  final String? stopLabel;
}

/// In qua trạm in, gói sẵn cho app: một thiết bị bật làm trạm (nghe hàng đợi, in
/// hộ, chạy nền khi tắt màn hình), các thiết bị khác không tới thẳng được máy in
/// (khác wifi, dùng 4G, máy in USB cắm ở máy khác) thì gửi lệnh qua trạm.
///
/// App chỉ cần cung cấp:
/// - [queues]: các kênh ([PrintRelayTransport]) của quán đang đăng nhập — VD
///   Firebase, MQTT. Trạm nghe MỌI kênh cùng lúc; máy gửi dùng kênh đầu tiên có
///   trạm trực tuyến (thứ tự trong danh sách = thứ tự ưu tiên);
/// - [onJob]: in một lệnh trạm nhận được bằng máy in của app;
/// - [notification]: chữ trên thông báo chạy nền;
/// - lưu trạng thái bật trạm ([onStationChanged]) và khôi phục bằng [restore].
class PrintRelay {
  PrintRelay({
    required this.queues,
    required this.onJob,
    this.canHandle,
    this.stationInfo,
    this.notification,
    this.onStationChanged,
    bool relayEnabled = true,
    this.onRelayEnabledChanged,
    this.lanFastPath = true,
    this.stationId,
    this.resultTimeout = const Duration(seconds: 20),
    void Function(String message)? log,
  }) : _log = log ?? debugPrint,
       relayEnabled = ValueNotifier(relayEnabled);

  /// Các kênh của quán hiện tại (bỏ qua kênh chưa sẵn sàng). Nên trả cùng đối
  /// tượng cho cùng một quán để dùng lại kết nối theo dõi trạm.
  final Future<List<PrintRelayTransport>> Function() queues;

  /// In lệnh trạm nhận được, trả `true` khi in thành công.
  final Future<bool> Function(PrintRelayJob job) onJob;

  /// Xem [PrintRelayStation.canHandle].
  final Future<bool> Function(PrintRelayJob job)? canHandle;

  /// Thông tin trạm báo lên khi trực tuyến (VD tên thiết bị).
  final Map<String, Object?> Function()? stationInfo;

  /// Có thì Android chạy nền với thông báo cố định khi đang là trạm.
  final PrintRelayNotification Function()? notification;

  /// Gọi khi bật / tắt trạm (kể cả khi người dùng bấm "Dừng" trên thông báo) để
  /// app lưu lại.
  final FutureOr<void> Function(bool enabled)? onStationChanged;

  /// Trạm nhận thêm lệnh thẳng qua mạng nội bộ khi máy gửi cùng mạng LAN (nhanh
  /// hơn, vẫn chạy khi mất internet) — xem [PrintRelayLanServer].
  final bool lanFastPath;

  /// Mã cố định của thiết bị khi làm trạm — để máy khác nhắm đúng trạm này (VD in
  /// qua máy in tích hợp của nó). App nên lưu một mã ngẫu nhiên cho mỗi thiết bị.
  final String? stationId;

  /// Thời gian máy gửi chờ trạm báo kết quả.
  final Duration resultTimeout;

  final void Function(String message) _log;

  /// Mỗi kênh một bộ theo dõi trạm riêng.
  final Map<PrintRelayTransport, PrintRelayClient> _clients = {};

  PrintRelayClient _clientFor(PrintRelayTransport t) => _clients.putIfAbsent(
    t,
    () => PrintRelayClient(
      resultTimeout: resultTimeout,
      log: _log,
      onStationsChanged: _publishStations,
    ),
  );

  /// Các trạm (Agent) đang trực tuyến, cập nhật NGAY khi một Agent bật / tắt /
  /// đổi thông tin (theo dõi liên tục trên mọi kênh) — giao diện lắng nghe để
  /// hiện trạng thái tức thì. Bỏ chính máy này.
  final ValueNotifier<List<Map<Object?, Object?>>> stations = ValueNotifier(
    const [],
  );

  void _publishStations() {
    final now = knownStations;
    final prev = stations.value;
    // Chỉ phát khi thật sự đổi (Firebase phát lại cả danh sách mỗi lần ghi).
    try {
      if (now.length == prev.length &&
          jsonEncode(now.map(_plain).toList()) ==
              jsonEncode(prev.map(_plain).toList())) {
        return;
      }
    } catch (_) {}
    stations.value = now;
  }

  static Object? _plain(Object? v) => switch (v) {
    final Map m => {for (final e in m.entries) '${e.key}': _plain(e.value)},
    final List l => [for (final e in l) _plain(e)],
    _ => v,
  };

  /// Thiết bị này đang là trạm in.
  final ValueNotifier<bool> isStation = ValueNotifier(false);

  /// KHÔNG còn dùng để quyết định gửi qua trạm: máy gửi luôn in thẳng trước,
  /// trạm chỉ là dự phòng tự động khi in thẳng không được (xem [_mayRelay]).
  /// Giữ lại để không vỡ app đang gọi.
  @Deprecated('Không còn tác dụng — trạm là dự phòng tự động')
  final ValueNotifier<bool> relayEnabled;

  /// Gọi khi bật / tắt [relayEnabled] để app lưu lại.
  final FutureOr<void> Function(bool enabled)? onRelayEnabledChanged;

  Future<void> setRelayEnabled(bool enabled) async {
    relayEnabled.value = enabled;
    await onRelayEnabledChanged?.call(enabled);
  }

  /// Các trạm đang trực tuyến (gộp mọi kênh, bỏ trùng theo `id`) kèm thông tin
  /// trạm báo — VD `{id, name, builtIn: {...}}`. Không gồm chính máy này.
  Future<List<Map<Object?, Object?>>> onlineStations() async {
    final byId = <Object?, Map<Object?, Object?>>{};
    for (final transport in await queues()) {
      final client = _clientFor(transport);
      if (!await client.hasOnlineStation(transport)) continue;
      for (final station in client.stations) {
        final id = station['id'];
        if (id != null && id == stationId) continue;
        byId.putIfAbsent(id ?? Object(), () => station);
      }
    }
    return byId.values.toList();
  }

  /// Quán có trạm in nào đang trực tuyến (trên kênh bất kỳ) không — để app chỉ
  /// hiện nút "In qua máy trạm" khi có trạm.
  Future<bool> hasOnlineStation() async {
    for (final transport in await queues()) {
      if (await _clientFor(transport).hasOnlineStation(transport)) return true;
    }
    return false;
  }

  final List<PrintRelayStation> _stations = [];
  PrintRelayLanServer? _lanServer;
  StreamSubscription<void>? _stopSub;

  /// Số lệnh đã in hộ (mọi kênh) từ lúc bật trạm.
  int printedCount = 0;

  /// Các kênh trạm này đang nghe (VD `[FirebasePrintRelayTransport,
  /// MqttPrintRelayTransport]`) — để app hiển thị.
  List<PrintRelayTransport> get stationTransports => [
    for (final s in _stations) s.transport,
  ];

  /// Khôi phục trạng thái đã lưu (gọi lúc vào app / đổi quán).
  Future<void> restore({required bool enabled}) async {
    await _stop();
    isStation.value = enabled && await _start();
  }

  /// Bật / tắt chế độ trạm in. Trả `false` khi không bật được (không kênh nào
  /// sẵn sàng).
  Future<bool> setStation(bool enabled) async {
    if (enabled) {
      await _stop();
      if (!await _start(requestPermission: true)) return false;
    } else {
      await _stop();
    }
    isStation.value = enabled;
    await onStationChanged?.call(enabled);
    return true;
  }

  Future<bool?> _handleLan(PrintRelayJob job) async {
    final target = job.printer.stationId;
    if (target != null && target != stationId) return null;
    if (!await (canHandle ?? PrintRelayStation.defaultCanHandle)(job)) {
      return null;
    }
    var ok = false;
    try {
      ok = await onJob(job);
    } catch (e) {
      _log('[PRINT-RELAY] In lệnh nội bộ lỗi: $e');
    }
    _onPrinted(ok);
    return ok;
  }

  void _onPrinted(bool ok) {
    if (!ok) return;
    printedCount++;
    unawaited(_updateNotification());
  }

  Future<bool> _start({bool requestPermission = false}) async {
    final transports = await queues();
    if (transports.isEmpty) return false;
    printedCount = 0;
    Map<String, Object?>? lan;
    if (lanFastPath) {
      final server = _lanServer = PrintRelayLanServer(log: _log);
      lan = await server.start(_handleLan);
    }
    _lan = lan;
    final info = _info();
    for (final transport in transports) {
      final station = PrintRelayStation(
        transport: transport,
        onJob: onJob,
        canHandle: canHandle,
        info: info,
        onPrinted: (job, ok, count) => _onPrinted(ok),
        stationId: stationId,
        log: _log,
      );
      if (await station.start()) _stations.add(station);
    }
    if (_stations.isEmpty) {
      await _stop();
      return false;
    }
    _watchOwnNetwork(lan);
    _stopSub ??= PrinterLabel.keepAliveStoppedByUser.listen((_) {
      _log('[PRINT-RELAY] Người dùng dừng trạm in từ thông báo');
      unawaited(setStation(false));
    });
    await _updateNotification(requestPermission: requestPermission);
    return true;
  }

  Timer? _networkTimer;

  /// Máy Agent mất mạng rồi có lại / đổi Wi-Fi: IP nội bộ có thể đổi — báo lại
  /// để máy gửi vẫn đi được đường nội bộ. Kiểm tra mỗi 20s (chỉ đọc IP máy, nhẹ).
  void _watchOwnNetwork(Map<String, Object?>? lan) {
    _networkTimer?.cancel();
    if (lan == null) return;
    var lastIps = (lan['ips'] as List?)?.join(',') ?? '';
    _networkTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      final ips = await PrintRelayLanServer.localIpv4s();
      final joined = ips.join(',');
      if (ips.isEmpty || joined == lastIps) return;
      lastIps = joined;
      _log(
        '[PRINT-RELAY] IP máy Agent đổi thành $joined — báo lại cho máy gửi',
      );
      _lan = {...lan, 'ips': ips};
      await refreshStationInfo();
    });
  }

  /// Thông tin LAN hiện tại của trạm (IP có thể đổi khi đổi mạng).
  Map<String, Object?>? _lan;

  Map<String, Object?> _info() => {
    ...?stationInfo?.call(),
    if (stationId != null) 'id': stationId,
    if (_lan != null) 'lan': _lan,
  };

  /// Báo lại thông tin trạm cho máy gửi (gọi lại [stationInfo]) — VD máy in tích
  /// hợp vừa được nhận ra sau khi trạm đã bật (khởi động máy), hoặc đổi trạng
  /// thái kết nối. Không làm gì khi trạm chưa bật.
  Future<void> refreshStationInfo() async {
    if (_stations.isEmpty) return;
    final info = _info();
    for (final station in List.of(_stations)) {
      await station.refreshInfo(info);
    }
  }

  Future<void> _stop() async {
    _lan = null;
    _networkTimer?.cancel();
    _networkTimer = null;
    final stations = List.of(_stations);
    _stations.clear();
    for (final station in stations) {
      await station.stop();
    }
    await _lanServer?.stop();
    _lanServer = null;
    if (Platform.isAndroid) await PrinterLabel.stopKeepAlive();
  }

  Future<void> _updateNotification({bool requestPermission = false}) async {
    final texts = notification?.call();
    if (texts == null || !Platform.isAndroid || _stations.isEmpty) return;
    final ok = await PrinterLabel.startKeepAlive(
      title: texts.title,
      text: printedCount == 0 ? texts.waiting : texts.printed(printedCount),
      channelName: texts.channelName,
      stopLabel: texts.stopLabel,
      requestPermission: requestPermission,
    );
    if (!ok) _log('[PRINT-RELAY] Không bật được chạy nền');
  }

  // ---------------------------------------------------------------------------
  // Máy gửi
  // ---------------------------------------------------------------------------

  /// Có nên thử gửi qua trạm không (chưa hỏi kênh nào): không phải trạm, đang bật
  /// "In qua máy trạm" và thiết bị không in thẳng được tới [printer].
  Future<bool> _mayRelay(
    PrintRelayPrinter printer, {
    bool force = false,
  }) async {
    if (isStation.value) return false;
    // [force] = đường dự phòng cuối, sau khi in thẳng (và tự chuyển Wi-Fi) đã
    // không được: đi Agent nếu công ty có Agent trực tuyến.
    if (force) return true;
    // Máy in tích hợp của một Agent cụ thể: chỉ in được qua Agent đó.
    if (printer.isBuiltIn && printer.stationId != null) return true;
    // In thẳng được (cùng mạng / USB đang cắm) → luồng bình thường, KHÔNG đi
    // Agent. Chắc chắn không in thẳng được (khác mạng / 4G / USB cắm ở máy khác)
    // → đi Agent luôn, khỏi chờ thử kết nối vô ích. Không có Agent trực tuyến
    // thì [relay] trả `null`, nơi gọi in như cũ.
    return !await PrintRelayClient.canPrintDirectly(printer);
  }

  /// Lệnh in tới [printer] sẽ đi qua trạm (để nơi gọi bỏ bước kiểm tra kết nối
  /// thẳng tới máy in — trên 4G bước đó luôn thất bại). Dừng ngay ở kênh đầu tiên
  /// có trạm, không chờ các kênh sau.
  Future<bool> willRelay(PrintRelayPrinter printer) async {
    if (!await _mayRelay(printer)) return false;
    for (final transport in await queues()) {
      if (await _clientFor(transport).hasOnlineStation(transport)) return true;
    }
    return false;
  }

  /// Gửi lệnh qua trạm nếu cần. [build] chỉ chạy khi thật sự gửi (VD thu nhỏ
  /// ảnh). Trả `null` khi không áp dụng — nơi gọi in trực tiếp như thường.
  ///
  /// Hỏi kênh theo thứ tự ưu tiên: kênh nào có trạm thì gửi ngay (không chờ kiểm
  /// tra kênh sau); gửi không được thì sang kênh kế.
  ///
  /// [force]: gửi qua trạm kể cả khi thiết bị này tưởng in thẳng được (cùng dải
  /// IP) — dùng sau khi in thẳng đã thất bại (VD Wi-Fi chặn các máy nói chuyện
  /// với nhau, máy in chỉ nối được từ mạng dây của trạm).
  Future<PrintRelayResult?> relay(
    PrintRelayPrinter printer,
    FutureOr<PrintRelayJob> Function() build, {
    bool force = false,
  }) async {
    final sw = Stopwatch()..start();
    if (!await _mayRelay(printer, force: force)) return null;
    final tMay = sw.elapsedMilliseconds;
    // Dựng lệnh (thu nhỏ + đổi ảnh đen trắng) SONG SONG với việc mở kênh / tìm
    // trạm — không bắt lệnh in chờ lần lượt từng bước.
    final jobFuture = Future<PrintRelayJob>(build);
    unawaited(jobFuture.then<void>((_) {}, onError: (Object _) {}));
    final transports = _fastestFirst(await queues());
    final tQueues = sw.elapsedMilliseconds;
    PrintRelayResult? last;
    for (final transport in transports) {
      final client = _clientFor(transport);
      final tFind = sw.elapsedMilliseconds;
      if (!await client.hasOnlineStation(transport)) continue;
      final tFound = sw.elapsedMilliseconds;
      final job = await jobFuture;
      _log(
        '[PRINT-RELAY] Gửi lệnh tới ${printer.address} qua trạm '
        '(${transport.runtimeType}) — kiểm tra ${tMay}ms, mở kênh '
        '${tQueues - tMay}ms, tìm trạm ${tFound - tFind}ms, chờ dựng lệnh '
        '${sw.elapsedMilliseconds - tFound}ms',
      );
      final tSend = sw.elapsedMilliseconds;
      final result = await client.send(transport, job);
      _recordLatency(transport, result, sw.elapsedMilliseconds - tSend);
      // Không gửi lên được / trạm không phản hồi trên kênh này (VD kênh này của
      // trạm đang rớt mà kênh kia còn): thử kênh kế trước khi báo lỗi.
      if (result != PrintRelayResult.notDelivered &&
          result != PrintRelayResult.noResponse) {
        return result;
      }
      last = result;
      _log(
        '[PRINT-RELAY] Kênh ${transport.runtimeType}: ${result.name} — '
        'thử kênh kế',
      );
    }
    if (last == null) {
      _log('[PRINT-RELAY] Không có trạm trực tuyến: in trực tiếp');
      return null;
    }
    // Trạm không phản hồi trên mọi kênh: báo lỗi (lệnh đã gỡ khỏi hàng đợi).
    return last == PrintRelayResult.noResponse ? last : null;
  }

  /// Thời gian trung bình (ms) từ lúc gửi tới lúc trạm in xong, theo từng loại
  /// kênh — để tự ưu tiên kênh nhanh hơn ([_fastestFirst]).
  final Map<String, double> _latencyMs = {};

  void _recordLatency(
    PrintRelayTransport transport,
    PrintRelayResult result,
    int ms,
  ) {
    final key = transport.runtimeType.toString();
    // Không phản hồi / không gửi được: phạt nặng để lần sau thử kênh kia trước.
    final sample = switch (result) {
      PrintRelayResult.done || PrintRelayResult.failed => ms.toDouble(),
      _ => 20000.0,
    };
    final prev = _latencyMs[key];
    // Trung bình động: lệnh mới nặng 30% — đổi kênh khi kênh này chậm đi hẳn,
    // không đổi qua lại vì một lệnh chậm lẻ tẻ.
    _latencyMs[key] = prev == null ? sample : prev * 0.7 + sample * 0.3;
  }

  /// Kênh nhanh hơn lên trước. Kênh chưa đo giữ thứ tự app đưa (thứ tự mặc
  /// định); kênh đã đo được xếp theo thời gian trung bình.
  List<PrintRelayTransport> _fastestFirst(List<PrintRelayTransport> list) {
    if (list.length < 2 || _latencyMs.isEmpty) return list;
    final indexed = list.asMap().entries.toList()
      ..sort((a, b) {
        final la = _latencyMs[a.value.runtimeType.toString()];
        final lb = _latencyMs[b.value.runtimeType.toString()];
        if (la == null || lb == null) return a.key.compareTo(b.key);
        return la.compareTo(lb);
      });
    return [for (final e in indexed) e.value];
  }

  /// Bắt đầu theo dõi trạm ở nền trên mọi kênh (gọi lúc vào app) — lần in đầu
  /// tiên qua trạm không phải chờ nối kênh / hỏi danh sách trạm.
  Future<void> warmUp() async {
    // Máy gửi: biết sẵn có Agent hay không (máy in lỗi thì chuyển ngầm sang
    // Agent). Máy Agent: thấy các Agent KHÁC trong công ty ([stations], không
    // ảnh hưởng việc nhận lệnh).
    try {
      final transports = await queues();
      if (transports.isEmpty) return;
      // Theo dõi MỌI kênh (giữ sẵn kết nối): lệnh in đầu tiên không phải chờ
      // nối broker / hỏi danh sách trạm, và chuyển kênh dự phòng được ngay.
      for (final transport in transports) {
        unawaited(_clientFor(transport).hasOnlineStation(transport));
      }
    } catch (_) {}
  }

  /// Các trạm đang trực tuyến — lần đầu (chưa theo dõi kênh nào) chờ tối đa
  /// [firstWait] cho danh sách về, các lần sau trả ngay ([knownStations]).
  Future<List<Map<Object?, Object?>>> currentStations({
    Duration firstWait = const Duration(milliseconds: 1500),
  }) async {
    try {
      for (final transport in await queues()) {
        await _clientFor(
          transport,
        ).hasOnlineStation(transport, firstWait: firstWait);
      }
    } catch (_) {}
    return knownStations;
  }

  /// Danh sách trạm đã biết (không chờ mạng) — dùng ở luồng in để không bị chậm;
  /// rỗng khi chưa theo dõi kênh nào ([warmUp]).
  List<Map<Object?, Object?>> get knownStations {
    final byId = <Object?, Map<Object?, Object?>>{};
    for (final client in _clients.values) {
      for (final station in client.stations) {
        final id = station['id'];
        if (id != null && id == stationId) continue;
        byId.putIfAbsent(id ?? Object(), () => station);
      }
    }
    return byId.values.toList();
  }
}
