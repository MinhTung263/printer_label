import 'dart:async';
import 'dart:io';

/// Mức chất lượng mạng từ thiết bị này tới một máy in LAN.
enum LanQualityLevel {
  /// Trung vị < 100ms, không lần nào lỗi.
  good,

  /// Trung vị 100–500ms, hoặc 1 lần lỗi: in được nhưng có thể chậm.
  weak,

  /// Trung vị > 500ms, có lần > 1000ms, hoặc từ 2 lần lỗi: dễ in lỗi.
  veryWeak,

  /// Không lần nào kết nối được.
  offline,
}

/// Kết quả đo chất lượng mạng tới máy in LAN — xem [LanQuality.measure].
class LanQuality {
  final String ip;
  final int port;
  final LanQualityLevel level;

  /// Thời gian bắt tay TCP mỗi lần đo (ms); `null` = lần đó không kết nối được.
  final List<int?> samplesMs;

  /// Có lần nào máy in TỪ CHỐI kết nối (thường do thiết bị khác đang in) không.
  final bool refused;
  final DateTime measuredAt;

  const LanQuality({
    required this.ip,
    required this.port,
    required this.level,
    required this.samplesMs,
    required this.refused,
    required this.measuredAt,
  });

  int get failures => samplesMs.where((s) => s == null).length;

  List<int> get _ok => samplesMs.whereType<int>().toList()..sort();

  /// Trung vị thời gian bắt tay (ms) của các lần thành công.
  int? get medianMs {
    final ok = _ok;
    return ok.isEmpty ? null : ok[ok.length ~/ 2];
  }

  int? get maxMs {
    final ok = _ok;
    return ok.isEmpty ? null : ok.last;
  }

  /// Có nên cảnh báo người dùng trước khi in không.
  bool get shouldWarn => level != LanQualityLevel.good;

  String get emoji => switch (level) {
        LanQualityLevel.good => '🟢',
        LanQualityLevel.weak => '🟡',
        LanQualityLevel.veryWeak => '🟠',
        LanQualityLevel.offline => '🔴',
      };

  /// Câu thông báo ngắn cho nhân viên quán.
  String get message => switch (level) {
        LanQualityLevel.good => 'Mạng tới máy in tốt',
        LanQualityLevel.weak => 'Mạng tới máy in hơi yếu, in có thể chậm',
        LanQualityLevel.veryWeak =>
          'Mạng tới máy in rất yếu, có thể in lỗi. Kiểm tra Wi-Fi',
        LanQualityLevel.offline => refused
            ? 'Máy in đang bận hoặc từ chối kết nối. Thử lại sau ít giây'
            : 'Không tới được máy in. Kiểm tra Wi-Fi và máy in đã bật',
      };

  @override
  String toString() =>
      'LanQuality($ip:$port $emoji ${level.name}, median=${medianMs}ms, max=${maxMs}ms, '
      'lỗi=$failures/${samplesMs.length}, samples=$samplesMs)';

  static final Map<String, LanQuality> _cache = {};
  static final Map<String, Future<LanQuality>> _inFlight = {};

  /// Đo chất lượng mạng tới máy in [ip]:[port] bằng cách bắt tay TCP [samples] lần.
  ///
  /// Chỉ mở rồi đóng kết nối, KHÔNG gửi byte nào nên máy in không in gì. Chạy bằng Dart
  /// thuần nên giống hệt nhau trên Android và iOS.
  ///
  /// Máy in LAN chỉ nhận MỘT kết nối tại một thời điểm, nên mỗi lần đo chiếm máy in vài
  /// chục ms. Chỉ gọi khi cần (mở màn hình in, ngay trước khi in) — KHÔNG đo liên tục chạy
  /// nền, nhất là khi nhiều thiết bị dùng chung máy in. Kết quả được dùng lại trong
  /// [cacheFor], và các lời gọi trùng IP trong lúc đang đo sẽ chờ chung một lần đo.
  static Future<LanQuality> measure(
    String ip, {
    int port = 9100,
    int samples = 5,
    Duration timeout = const Duration(seconds: 3),
    Duration gap = const Duration(milliseconds: 150),
    Duration cacheFor = const Duration(seconds: 10),
  }) {
    final key = '$ip:$port';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.measuredAt) < cacheFor) {
      return Future.value(cached);
    }
    return _inFlight[key] ??=
        _measure(ip, port, samples, timeout, gap).then((q) {
      _cache[key] = q;
      return q;
    }).whenComplete(() {
      // KHÔNG viết `() => _inFlight.remove(key)`: remove() trả về chính Future này, và
      // whenComplete sẽ CHỜ Future được trả về -> tự chờ chính nó, không bao giờ xong.
      _inFlight.remove(key);
    });
  }

  static Future<LanQuality> _measure(
    String ip,
    int port,
    int samples,
    Duration timeout,
    Duration gap,
  ) async {
    final results = <int?>[];
    var refused = false;
    for (var i = 0; i < samples; i++) {
      if (i > 0) await Future.delayed(gap);
      final sw = Stopwatch()..start();
      try {
        final socket = await Socket.connect(ip, port, timeout: timeout);
        sw.stop();
        socket.destroy();
        results.add(sw.elapsedMilliseconds);
      } on SocketException catch (e) {
        // ECONNREFUSED: 61 (iOS/macOS), 111 (Android/Linux).
        final code = e.osError?.errorCode;
        if (code == 61 || code == 111) refused = true;
        results.add(null);
      } catch (_) {
        results.add(null);
      }
      // Hai lần đầu đều lỗi: gần như chắc chắn không tới được, dừng sớm để người dùng
      // không phải chờ samples x timeout.
      if (i == 1 && results.every((r) => r == null)) break;
    }
    return LanQuality(
      ip: ip,
      port: port,
      level: _classify(results),
      samplesMs: List.unmodifiable(results),
      refused: refused,
      measuredAt: DateTime.now(),
    );
  }

  static LanQualityLevel _classify(List<int?> results) {
    final ok = results.whereType<int>().toList()..sort();
    final failures = results.length - ok.length;
    if (ok.isEmpty) return LanQualityLevel.offline;
    final median = ok[ok.length ~/ 2];
    // Ngưỡng 1000ms: SDK máy in Android cũ chỉ chờ kết nối đúng 1 giây — có lần vượt
    // là dấu hiệu mạng đã chạm ngưỡng gây lỗi (docs/IN_LAN_ON_DINH.md mục 5.2).
    if (median > 500 || ok.last > 1000 || failures >= 2) {
      return LanQualityLevel.veryWeak;
    }
    if (median >= 100 || failures == 1) return LanQualityLevel.weak;
    return LanQualityLevel.good;
  }
}
