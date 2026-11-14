import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'print_relay_job.dart';
import 'print_relay_transport.dart';

/// Cấu hình broker MQTT cho [MqttPrintRelayTransport].
class MqttRelayConfig {
  const MqttRelayConfig({
    this.host = 'broker.emqx.io',
    this.port = 1883,
    this.useWebSocket = false,
    this.secure = false,
    this.username,
    this.password,
    this.topicPrefix = 'easypos/print_relay',
  });

  /// Tên máy chủ; với WebSocket có thể kèm scheme (`wss://...`).
  final String host;
  final int port;
  final bool useWebSocket;

  /// TLS (MQTT thường qua 8883). WebSocket bảo mật thì dùng `wss://` ở [host].
  final bool secure;
  final String? username;
  final String? password;
  final String topicPrefix;
}

/// Kênh trạm in qua MQTT — "cầu nối in không cần backend": máy gửi publish lệnh,
/// trạm subscribe rồi in hộ. Dùng được với broker công khai (mặc định
/// `broker.emqx.io`) hoặc broker riêng ([MqttRelayConfig]).
///
/// Broker công khai ai cũng kết nối được nên:
/// - topic là mã băm của [secret] (`{prefix}/{sha256}`), không phải mã quán dễ đoán;
/// - mọi nội dung (lệnh in, trạng thái, thông tin trạm) mã hoá AES-256-GCM bằng
///   khoá suy ra từ [secret]: không có khoá thì không đọc được hoá đơn, gói giả /
///   sửa bị loại khi giải mã.
///
/// Topic dưới `{prefix}/{băm}`:
/// - `stations/{id}` (retained): trạm trực tuyến; Last Will xoá khi trạm rớt mạng.
/// - `jobs/{id}`: lệnh in.
/// - `claims/{id}`: trạm giành lệnh — trạm có gói giành tới broker trước thắng.
/// - `status/{id}`: printing / done / failed.
class MqttPrintRelayTransport implements PrintRelayTransport {
  MqttPrintRelayTransport({
    required String secret,
    this.config = const MqttRelayConfig(),
    void Function(String message)? log,
  }) : _log = log ?? debugPrint,
       _topic =
           '${config.topicPrefix}/'
           '${sha256.convert(utf8.encode('topic|$secret')).toString().substring(0, 32)}',
       _key = enc.Key(
         Uint8List.fromList(sha256.convert(utf8.encode('key|$secret')).bytes),
       );

  final MqttRelayConfig config;
  final void Function(String message) _log;
  final String _topic;
  final enc.Key _key;

  /// Mã trạm này (một thiết bị một mã mỗi lần mở app).
  final String _stationId = _randomId();

  MqttServerClient? _client;

  /// Trạng thái kết nối broker (cho [watchConnection]).
  bool _connected = false;
  final _connection = StreamController<bool>.broadcast();

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    _connection.add(value);
  }

  Future<MqttServerClient?>? _connecting;
  final _messages =
      StreamController<MqttReceivedMessage<MqttMessage>>.broadcast();
  final Set<String> _subscribed = {};

  String get topicRoot => _topic;

  // ---------------------------------------------------------------------------
  // Kết nối
  // ---------------------------------------------------------------------------

  Future<MqttServerClient?> _connect() {
    final client = _client;
    if (client != null &&
        client.connectionStatus?.state == MqttConnectionState.connected) {
      return Future.value(client);
    }
    return _connecting ??= _open().whenComplete(() => _connecting = null);
  }

  Future<MqttServerClient?> _open() async {
    final client =
        MqttServerClient.withPort(
            config.host,
            'easypos_relay_${_randomId()}',
            config.port,
          )
          ..useWebSocket = config.useWebSocket
          ..secure = config.secure
          ..keepAlivePeriod = 30
          ..autoReconnect = true
          ..resubscribeOnAutoReconnect = true
          ..logging(on: false);
    // Rớt mạng thì broker chạy Last Will xoá trạng thái trực tuyến của trạm —
    // nối lại được phải tự báo lại, không thì máy gửi tưởng không có trạm.
    client.onConnected = () => _setConnected(true);
    client.onDisconnected = () => _setConnected(false);
    client.onAutoReconnect = () => _setConnected(false);
    client.onAutoReconnected = () {
      _setConnected(true);
      final info = _onlineInfo;
      _log('[PRINT-RELAY][MQTT] Đã nối lại broker');
      if (info != null) {
        unawaited(goOnline(info).catchError((Object _) {}));
      }
    };
    if (config.useWebSocket) {
      client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
    }
    // Trạm rớt mạng: broker tự xoá trạng thái trực tuyến (retained rỗng).
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(client.clientIdentifier)
        .withWillTopic('$_topic/stations/$_stationId')
        .withWillMessage('')
        .withWillRetain()
        .withWillQos(MqttQos.atLeastOnce)
        .startClean();
    try {
      await client.connect(config.username, config.password);
    } catch (e) {
      _log('[PRINT-RELAY][MQTT] Kết nối ${config.host} lỗi: $e');
      client.disconnect();
      return null;
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      return null;
    }
    client.updates?.listen((events) {
      for (final e in events) {
        _messages.add(e);
      }
    });
    _client = client;
    _subscribed.clear();
    _setConnected(true);
    _log('[PRINT-RELAY][MQTT] Đã kết nối ${config.host}:${config.port}');
    return client;
  }

  Future<MqttServerClient?> _subscribe(String filter) async {
    final client = await _connect();
    if (client != null && _subscribed.add(filter)) {
      client.subscribe(filter, MqttQos.atLeastOnce);
    }
    return client;
  }

  Future<void> _publish(
    String topic,
    Object? data, {
    bool retain = false,
  }) async {
    final client = await _connect();
    if (client == null) throw StateError('MQTT chưa kết nối');
    final builder = MqttClientPayloadBuilder();
    if (data != null) builder.addString(_encrypt(data));
    client.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: retain,
    );
  }

  /// Lọc tin nhắn theo [filter] (`+` ở cuối = mọi id) → (id, nội dung đã giải mã).
  Stream<(String, Object?)> _watch(String filter) {
    final base = filter.endsWith('/+')
        ? filter.substring(0, filter.length - 1)
        : null;
    late StreamController<(String, Object?)> out;
    StreamSubscription<MqttReceivedMessage<MqttMessage>>? sub;
    out = StreamController<(String, Object?)>(
      onListen: () async {
        sub = _messages.stream.listen((e) {
          final topic = e.topic;
          final String id;
          if (base != null) {
            if (!topic.startsWith(base)) return;
            id = topic.substring(base.length);
          } else {
            if (topic != filter) return;
            id = topic.split('/').last;
          }
          final message = e.payload;
          if (message is! MqttPublishMessage) return;
          final bytes = message.payload.message;
          out.add((id, bytes.isEmpty ? null : _decrypt(bytes)));
        });
        if (await _subscribe(filter) == null) {
          out.addError(StateError('MQTT chưa kết nối'));
        }
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  // ---------------------------------------------------------------------------
  // Mã hoá
  // ---------------------------------------------------------------------------

  String _encrypt(Object data) {
    final iv = enc.IV.fromSecureRandom(12);
    final encrypted = enc.Encrypter(
      enc.AES(_key, mode: enc.AESMode.gcm),
    ).encryptBytes(utf8.encode(jsonEncode(data)), iv: iv);
    return base64Encode([...iv.bytes, ...encrypted.bytes]);
  }

  /// `null` khi gói không giải mã được (khoá khác / bị sửa / gói rác).
  Object? _decrypt(List<int> payload) {
    try {
      final raw = base64Decode(utf8.decode(payload));
      if (raw.length < 13) return null;
      final iv = enc.IV(Uint8List.fromList(raw.sublist(0, 12)));
      final plain = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.gcm))
          .decryptBytes(
            enc.Encrypted(Uint8List.fromList(raw.sublist(12))),
            iv: iv,
          );
      return jsonDecode(utf8.decode(plain));
    } catch (_) {
      return null;
    }
  }

  static String _randomId() {
    final r = Random.secure();
    return List.generate(
      8,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  // ---------------------------------------------------------------------------
  // Trạm in
  // ---------------------------------------------------------------------------

  /// Thông tin trạm đang báo (để báo lại sau khi nối lại broker).
  Map<String, Object?>? _onlineInfo;

  @override
  Future<void> goOnline(Map<String, Object?> info) async {
    _onlineInfo = info;
    await _publish('$_topic/stations/$_stationId', {
      ...info,
      'at': DateTime.now().millisecondsSinceEpoch,
    }, retain: true);
    _listenClaims();
    // Chờ broker xác nhận đăng ký trước khi nhận lệnh.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<void> goOffline() async {
    _onlineInfo = null;
    final client = _client;
    if (client == null) return;
    try {
      // Retained rỗng = xoá trạng thái trực tuyến.
      client.publishMessage(
        '$_topic/stations/$_stationId',
        MqttQos.atLeastOnce,
        MqttClientPayloadBuilder().payload!,
        retain: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } catch (_) {}
  }

  @override
  Stream<PrintRelayQueuedJob> watchJobs() => _watch(
    '$_topic/jobs/+',
  ).where((e) => e.$2 is Map).map((e) => PrintRelayQueuedJob(e.$1, e.$2));

  /// Các trạm đã giành từng lệnh (theo mọi gói `claims` nhận được).
  final Map<String, Set<String>> _claimers = {};

  /// Báo khi thấy gói giành lệnh của CHÍNH trạm này quay về (đã qua broker).
  final Map<String, Completer<void>> _ownClaimEcho = {};
  StreamSubscription<(String, Object?)>? _claimSub;

  /// Nghe MỌI gói giành lệnh ngay từ lúc trạm lên mạng — nghe muộn (lúc nhận lệnh
  /// đầu tiên) sẽ lỡ gói của trạm khác, cả hai trạm đều tưởng mình thắng.
  void _listenClaims() {
    _claimSub ??= _watch('$_topic/claims/+').listen((e) {
      final by = e.$2 is Map ? (e.$2 as Map)['by'] : null;
      if (by is! String) return;
      _claimers.putIfAbsent(e.$1, () => <String>{}).add(by);
      if (by == _stationId) {
        final echo = _ownClaimEcho[e.$1];
        if (echo != null && !echo.isCompleted) echo.complete();
      }
    });
  }

  /// Giành lệnh: gửi gói giành, chờ gói của mình quay về rồi gom thêm gói của trạm
  /// khác trong một nhịp; trạm có mã NHỎ NHẤT thắng.
  ///
  /// Không dùng "gói tới trước thắng": broker công khai là một cụm nhiều máy chủ,
  /// mỗi trạm có thể thấy thứ tự gói khác nhau → hai trạm cùng tưởng mình thắng
  /// (đã gặp khi thử). So mã nhỏ nhất thì mọi trạm ra cùng một kết quả, không phụ
  /// thuộc thứ tự nhận.
  @override
  Future<bool> claimJob(String id) async {
    _listenClaims();
    final echo = _ownClaimEcho.putIfAbsent(id, Completer<void>.new);
    await _publish('$_topic/claims/$id', {'by': _stationId});
    try {
      await echo.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // Gói của mình không quay về được (mạng chập chờn): KHÔNG in, tránh in trùng.
      // Máy gửi hết thời gian chờ sẽ báo lỗi kèm nút In lại.
      return false;
    } finally {
      Timer(const Duration(minutes: 3), () {
        _ownClaimEcho.remove(id);
        _claimers.remove(id);
      });
    }
    // Chờ gói giành của các trạm khác (gửi cùng lúc) tới nơi.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final claimers = _claimers[id] ?? {_stationId};
    final winner = claimers.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    if (winner != _stationId) return false;
    await _publish('$_topic/status/$id', PrintRelayStatus.printing);
    return true;
  }

  @override
  Future<void> ackJob(String id) =>
      _publish('$_topic/status/$id', PrintRelayStatus.printing);

  @override
  Future<void> completeJob(String id, {required bool success}) => _publish(
    '$_topic/status/$id',
    success ? PrintRelayStatus.done : PrintRelayStatus.failed,
  );

  /// Lệnh không retained nên không có gì để xoá trên broker.
  @override
  Future<void> deleteJob(String id) async {}

  // ---------------------------------------------------------------------------
  // Máy gửi
  // ---------------------------------------------------------------------------

  @override
  Stream<List<Map<Object?, Object?>>> watchStations() {
    final stations = <String, Map<Object?, Object?>>{};
    late StreamController<List<Map<Object?, Object?>>> out;
    StreamSubscription<(String, Object?)>? sub;
    Timer? empty;
    out = StreamController(
      onListen: () {
        // Không có trạm thì broker không gửi gì (không có retained): báo rỗng
        // sau một nhịp để máy gửi không phải chờ mỗi lần in.
        empty = Timer(const Duration(milliseconds: 1500), () {
          if (stations.isEmpty) out.add(const []);
        });
        sub = _watch('$_topic/stations/+').listen((e) {
          final info = e.$2;
          if (info is Map) {
            stations[e.$1] = Map<Object?, Object?>.from(info);
          } else {
            stations.remove(e.$1);
          }
          out.add(stations.values.toList());
        }, onError: out.addError);
      },
      onCancel: () {
        empty?.cancel();
        return sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<String> submitJob(Map<String, Object?> data) async {
    final id = _randomId();
    // Nghe trạng thái trước khi gửi lệnh để không lỡ kết quả của trạm.
    await _subscribe('$_topic/status/$id');
    await _publish('$_topic/jobs/$id', data);
    return id;
  }

  @override
  Stream<bool> watchConnection() async* {
    yield _connected;
    yield* _connection.stream;
  }

  @override
  Stream<String?> watchJobStatus(String id) => _watch(
    '$_topic/status/$id',
  ).map((e) => e.$2 is String ? e.$2 as String : null);

  /// Đóng kết nối (VD đổi quán / đăng xuất).
  Future<void> dispose() async {
    await goOffline();
    await _claimSub?.cancel();
    _client?.disconnect();
    _client = null;
  }
}
