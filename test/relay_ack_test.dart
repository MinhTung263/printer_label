import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

/// Kênh giả trong bộ nhớ: một trạm "sống" (nhận lệnh → báo nhận → in xong)
/// hoặc "chết" (vẫn nằm trong danh sách nhưng không phản hồi).
class _FakeTransport implements PrintRelayTransport {
  _FakeTransport({required this.alive});

  final bool alive;
  final _status = <String, StreamController<String?>>{};
  final submitted = <Map<String, Object?>>[];
  final deleted = <String>[];
  var _seq = 0;

  @override
  Stream<List<Map<Object?, Object?>>> watchStations() => Stream.value([
    {
      'id': 'agent-1',
      'name': 'Sunmi',
      'lan': {'token': 't1', 'port': 9101, 'ips': <String>[]},
    },
  ]);

  @override
  Future<String> submitJob(Map<String, Object?> data) async {
    final id = 'job${_seq++}';
    submitted.add(data);
    final c = _status[id] = StreamController<String?>.broadcast();
    if (alive) {
      Timer(const Duration(milliseconds: 20), () {
        c.add(PrintRelayStatus.printing);
        Timer(
          const Duration(milliseconds: 20),
          () => c.add(PrintRelayStatus.done),
        );
      });
    }
    return id;
  }

  @override
  Stream<String?> watchJobStatus(String id) => _status[id]!.stream;

  @override
  Future<void> deleteJob(String id) async => deleted.add(id);

  @override
  Future<void> ackJob(String id) async {}
  @override
  Future<bool> claimJob(String id) async => true;
  @override
  Future<void> completeJob(String id, {required bool success}) async {}
  @override
  Future<void> goOffline() async {}
  @override
  Future<void> goOnline(Map<String, Object?> info) async {}
  @override
  Stream<PrintRelayQueuedJob> watchJobs() => const Stream.empty();
  @override
  Stream<bool> watchConnection() => Stream.value(true);
}

/// Kênh "sống" thứ hai (khác loại với [_FakeTransport] để đo riêng từng kênh).
class _AliveTransport extends _FakeTransport {
  _AliveTransport() : super(alive: true);
}

PrintRelayJob _job() => PrintRelayJob.receipt(
  printer: const PrintRelayPrinter(address: '192.168.1.100'),
  image: Uint8List.fromList([1, 2, 3]),
  paperSize: 'size80',
  sender: 'Quầy 1',
);

void main() {
  test(
    'Agent đã tắt (không báo nhận): báo noResponse nhanh, lần sau bỏ qua',
    () async {
      final t = _FakeTransport(alive: false);
      final client = PrintRelayClient(
        ackTimeout: const Duration(milliseconds: 300),
        resultTimeout: const Duration(seconds: 20),
      );
      expect(await client.hasOnlineStation(t), isTrue);
      final sw = Stopwatch()..start();
      expect(await client.send(t, _job()), PrintRelayResult.noResponse);
      expect(sw.elapsedMilliseconds, lessThan(2000));
      // Lệnh đã gỡ khỏi hàng đợi; Agent tạm bị bỏ qua.
      await Future<void>.delayed(Duration.zero);
      expect(t.deleted, hasLength(1));
      expect(await client.hasOnlineStation(t), isFalse);
    },
  );

  test('Agent sống: báo nhận rồi in xong; lệnh mang tên máy gửi', () async {
    final t = _FakeTransport(alive: true);
    final client = PrintRelayClient(
      ackTimeout: const Duration(milliseconds: 300),
    );
    expect(await client.hasOnlineStation(t), isTrue);
    expect(await client.send(t, _job()), PrintRelayResult.done);
    expect(t.submitted.single['sender'], 'Quầy 1');
    expect(PrintRelayJob.fromMap('x', t.submitted.single)?.sender, 'Quầy 1');
  });

  test('Kênh đầu Agent không phản hồi: tự sang kênh sau và in được', () async {
    final dead = _FakeTransport(alive: false);
    final alive = _FakeTransport(alive: true);
    var built = 0;
    final relay = PrintRelay(
      queues: () async => [dead, alive],
      onJob: (_) async => true,
    );
    final sw = Stopwatch()..start();
    final result = await relay.relay(
      const PrintRelayPrinter(address: '192.168.1.100', isBuiltIn: true),
      () {
        built++;
        return _job();
      },
      force: true,
    );
    expect(result, PrintRelayResult.done);
    expect(built, 1, reason: 'dựng lệnh một lần, dùng cho cả hai kênh');
    expect(alive.submitted, hasLength(1));
    // ignore: avoid_print
    print('Chuyển kênh xong sau ${sw.elapsedMilliseconds}ms');
  });

  test(
    'Tự chọn kênh: kênh vừa không phản hồi bị đẩy xuống, lệnh sau đi kênh tốt ngay',
    () async {
      final dead = _FakeTransport(alive: false);
      final alive = _AliveTransport();
      final relay = PrintRelay(
        queues: () async => [dead, alive],
        onJob: (_) async => true,
      );
      const printer = PrintRelayPrinter(
        address: '192.168.1.100',
        isBuiltIn: true,
      );
      expect(
        await relay.relay(printer, _job, force: true),
        PrintRelayResult.done,
      );
      final sw = Stopwatch()..start();
      expect(
        await relay.relay(printer, _job, force: true),
        PrintRelayResult.done,
      );
      // Lần 2 không còn chờ ~6s ở kênh hỏng.
      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(dead.submitted, hasLength(1));
      expect(alive.submitted, hasLength(2));
    },
  );

  test(
    'Lệnh nhắm Agent đã tắt (còn Agent khác): báo ngay, không gửi lên hàng đợi',
    () async {
      final t = _FakeTransport(alive: true); // chỉ có agent-1 trực tuyến
      final client = PrintRelayClient();
      expect(await client.hasOnlineStation(t), isTrue);
      final job = PrintRelayJob.receipt(
        printer: const PrintRelayPrinter.stationBuiltIn(stationId: 'agent-2'),
        image: Uint8List.fromList([1]),
      );
      final sw = Stopwatch()..start();
      expect(await client.send(t, job), PrintRelayResult.noResponse);
      expect(sw.elapsedMilliseconds, lessThan(200));
      expect(t.submitted, isEmpty);
    },
  );

  testWidgets('Thu gọn ảnh: chỉ còn đen / trắng theo đúng quy tắc máy in', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Ảnh "hoá đơn" giả: nền trắng, chữ khử răng cưa (nhiều sắc xám).
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const w = 576, h = 1200;
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 576, 1200),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      for (var y = 0; y < h; y += 24) {
        for (var x = 8; x < w - 40; x += 46) {
          canvas.drawCircle(
            Offset(x + 18.3, y + 11.7),
            9.4,
            Paint()
              ..color = Color.fromARGB(255, (x * 7) % 256, 40, 90)
              ..isAntiAlias = true,
          );
        }
      }
      final image = await recorder.endRecording().toImage(w, h);
      final png = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!.buffer.asUint8List();

      final compact = await PrintRelayImage.compact(png);
      // ignore: avoid_print
      print('PNG ${png.length}B → ${compact.length}B');
      expect(compact.length, lessThan(png.length));

      final codec = await ui.instantiateImageCodec(compact);
      final out = (await (await codec.getNextFrame()).image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!.buffer.asUint8List();
      for (var i = 0; i < out.length; i += 4) {
        final black =
            rgba[i + 3] > 50 &&
            299 * rgba[i] + 587 * rgba[i + 1] + 114 * rgba[i + 2] < 200000;
        expect(out[i], black ? 0 : 255, reason: 'điểm ${i ~/ 4}');
      }
    });
  });
}
