import 'dart:io';
import 'dart:typed_data';

import 'package:printer_label/desktop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Máy in LAN giả: ghi lại byte nhận được mỗi kết nối, trả lời `DLE EOT n` theo
/// [statusReply] (`null` = im lặng như máy giá rẻ).
class FakeLanPrinter {
  FakeLanPrinter._(this._server) {
    _server.listen((s) {
      final buf = BytesBuilder();
      s.listen(
        (data) {
          for (var i = 0; i < data.length; i++) {
            if (i + 2 < data.length && data[i] == 0x10 && data[i + 1] == 0x04) {
              final r = statusReply?.call(data[i + 2]);
              if (r != null) s.add([r]);
              i += 2;
            } else {
              buf.addByte(data[i]);
            }
          }
        },
        onDone: () {
          jobs.add(buf.takeBytes());
          s.destroy();
        },
      );
    });
  }

  static Future<FakeLanPrinter> start() async => FakeLanPrinter._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  final ServerSocket _server;
  final List<Uint8List> jobs = [];
  int? Function(int n)? statusReply;

  int get port => _server.port;
  Future<void> close() => _server.close();

  Future<void> waitJobs(int n) async {
    for (var i = 0; i < 100 && jobs.length < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

void main() {
  late FakeLanPrinter printer;
  late TcpPrinterPort port;

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('printer_label_dirty_');
    TcpPrinterPort.dirtyStore.path = '${tmp.path}/dirty.json';
    printer = await FakeLanPrinter.start();
    port = TcpPrinterPort(
      '127.0.0.1',
      port: printer.port,
      statusTimeout: const Duration(milliseconds: 150),
      chunkSize: 1000,
    );
  });
  tearDown(() async {
    TcpPrinterPort.busyMaxAttempts = 12;
    TcpPrinterPort.busyMaxDelay = const Duration(milliseconds: 1500);
    await printer.close();
    await tmp.delete(recursive: true);
  });

  test('gửi đủ byte theo gói', () async {
    final data = Uint8List.fromList(List.generate(5000, (i) => i & 0xff));
    await port.send(data);
    await printer.waitJobs(1);
    expect(printer.jobs.single, data);
  });

  test('máy không trả lời trạng thái vẫn in', () async {
    expect(await port.queryStatus(), PaperStatus.unknown);
    await port.send(Uint8List.fromList([1, 2, 3]));
    await printer.waitJobs(2);
    expect(printer.jobs.last, [1, 2, 3]);
  });

  test('hết giấy thì không gửi phiếu', () async {
    printer.statusReply = (n) => n == 4 ? 0x12 | 0x60 : 0x12;
    await expectLater(
      port.send(Uint8List.fromList([7, 7, 7])),
      throwsA(
        isA<PrinterStatusException>().having(
          (e) => e.code,
          'code',
          'PRINTER_OUT_OF_PAPER',
        ),
      ),
    );
    await printer.waitJobs(1);
    expect(printer.jobs.single, isEmpty);
  });

  test('mở nắp', () async {
    printer.statusReply = (n) => n == 2 ? 0x12 | 0x04 : 0x12;
    expect(await port.queryStatus(), PaperStatus.coverOpen);
  });

  test('lệnh song song tới cùng máy được xếp hàng, không chèn byte', () async {
    printer.statusReply = (_) => 0x12;
    final a = Uint8List.fromList(List.filled(3000, 0xAA));
    final b = Uint8List.fromList(List.filled(3000, 0xBB));
    await Future.wait([port.send(a), port.send(b)]);
    await printer.waitJobs(2);
    expect(printer.jobs, [a, b]);
  });

  test('in ảnh PNG: mở két rồi phiếu 2 bản', () async {
    final image = img.Image(width: 8, height: 1)..clear(img.ColorRgb8(0, 0, 0));
    await EscPosPrinter.printImage(
      port,
      img.encodePng(image),
      copies: 2,
      openDrawer: true,
    );
    await printer.waitJobs(2);
    expect(printer.jobs.first, EscPosCommands.openDrawer);
    final raster = Uint8List.fromList([0x1D, 0x76, 0x30, 0, 1, 0, 1, 0, 0xFF]);
    // Lệnh ESC/POS luôn mở đầu bằng phần xả (16384 byte 0x00 + ESC @) rồi mới tới phiếu.
    final job = printer.jobs.last;
    expect(job.sublist(0, 16384).every((b) => b == 0), isTrue);
    expect(job.sublist(16384, 16386), [0x1B, 0x40]);
    expect(job.sublist(16386), EscPosCommands.receipt(raster, copies: 2));
  });

  test('không kết nối được máy in thì báo lỗi', () async {
    await printer.close();
    await expectLater(
      TcpPrinterPort('127.0.0.1', port: printer.port).send(Uint8List(1)),
      throwsA(isA<SocketException>()),
    );
  });

  test(
    'lần gửi trước đứt giữa chừng: lần sau xả bộ đệm (0x00 x16384 + ESC @) rồi mới in',
    () async {
      // Máy in cắt kết nối ngay khi nhận byte đầu tiên của lần đầu.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final jobs = <Uint8List>[];
      var n = 0;
      server.listen((s) {
        final first = n++ == 0;
        final buf = BytesBuilder();
        s.listen(
          (d) {
            if (first) {
              s.destroy();
            } else {
              buf.add(d);
            }
          },
          onDone: () {
            if (!first) jobs.add(buf.takeBytes());
            s.destroy();
          },
          onError: (_) {},
        );
      });
      addTearDown(server.close);
      final p = TcpPrinterPort('127.0.0.1', port: server.port, chunkSize: 1000);
      Object? error;
      try {
        await p.send(Uint8List(3 * 1024 * 1024), checkStatus: false);
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull, reason: 'lần đầu phải lỗi vì bị cắt');
      await p.send(Uint8List.fromList([1, 2, 3]), checkStatus: false);
      for (var i = 0; i < 100 && jobs.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final got = jobs.single;
      expect(got.length, 16386 + 3);
      expect(got.sublist(0, 16384).every((b) => b == 0), isTrue);
      expect(got.sublist(16384, 16386), [0x1B, 0x40]);
      expect(got.sublist(16386), [1, 2, 3]);
      // Lần thứ ba: đã xả rồi nên không xả nữa.
      await p.send(Uint8List.fromList([9]), checkStatus: false);
      for (var i = 0; i < 100 && jobs.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(jobs.last, [9]);
    },
  );

  test(
    'lệnh ESC/POS luôn được xả ở kết nối mới, kể cả khi Agent này không biết máy in còn dở',
    () async {
      // Một thiết bị KHÁC có thể vừa để máy in dở lệnh ảnh: sổ của Agent này sạch nhưng vẫn phải xả.
      final bill = Uint8List.fromList([0x1B, 0x40, 0x1B, 0x61, 0x01, 1, 2, 3]);
      await port.send(bill, checkStatus: false);
      await printer.waitJobs(1);
      final job = printer.jobs.single;
      expect(job.length, 16386 + bill.length);
      expect(job.sublist(0, 16384).every((b) => b == 0), isTrue);
      expect(job.sublist(16384, 16386), [0x1B, 0x40]);
      expect(job.sublist(16386), bill);
    },
  );

  test(
    'lệnh không phải ESC/POS (không mở đầu ESC @) và sổ sạch thì KHÔNG xả',
    () async {
      final data = Uint8List.fromList([9, 8, 7]);
      await port.send(data, checkStatus: false);
      await printer.waitJobs(1);
      expect(printer.jobs.single, data);
    },
  );

  test('sổ "in dở" lưu bền: Agent khởi động lại vẫn biết', () {
    final path = '${tmp.path}/persist.json';
    DirtyStore(path: path).mark('tcp://192.168.1.50:9100');
    // Một Agent mới (tiến trình mới) nạp cùng tệp.
    final restarted = DirtyStore(path: path);
    expect(restarted.isDirty('tcp://192.168.1.50:9100'), isTrue);
    expect(restarted.isDirty('tcp://192.168.1.51:9100'), isFalse);
    restarted.clear('tcp://192.168.1.50:9100');
    expect(DirtyStore(path: path).isDirty('tcp://192.168.1.50:9100'), isFalse);
  });

  test('tệp sổ hỏng thì coi như sạch, không làm hỏng việc in', () async {
    File('${tmp.path}/dirty.json').writeAsStringSync('{không phải json');
    await port.send(Uint8List.fromList([1]), checkStatus: false);
    await printer.waitJobs(1);
    expect(printer.jobs.single, [1]);
  });

  test(
    'máy in bận (từ chối socket) thì thử lại, chưa mất byte bill nào',
    () async {
      // Máy in cắt kết nối ngay khi nhận byte đầu (đang in cho thiết bị khác), lần 2 mới nhận.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final jobs = <Uint8List>[];
      var n = 0;
      server.listen((s) {
        final reject = n++ == 0;
        final buf = BytesBuilder();
        s.listen(
          (d) {
            if (reject) {
              s.destroy();
            } else {
              buf.add(d);
            }
          },
          onDone: () {
            if (!reject) jobs.add(buf.takeBytes());
            s.destroy();
          },
          onError: (_) {},
        );
      });
      addTearDown(server.close);
      TcpPrinterPort.busyMaxDelay = const Duration(milliseconds: 20);
      final bill = Uint8List.fromList([0x1B, 0x40, 7, 7, 7]);
      await TcpPrinterPort(
        '127.0.0.1',
        port: server.port,
      ).send(bill, checkStatus: false);
      for (var i = 0; i < 100 && jobs.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(n, 2, reason: 'lần đầu bị từ chối, lần hai được nhận');
      expect(
        jobs.single.sublist(16386),
        bill,
        reason: 'bill chỉ đi MỘT lần, nguyên vẹn',
      );
    },
  );

  test(
    'máy in bận mãi thì báo lỗi sau số lần thử tối đa (không treo)',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var n = 0;
      server.listen((s) {
        n++;
        s.listen((_) => s.destroy(), onError: (_) {});
      });
      addTearDown(server.close);
      TcpPrinterPort.busyMaxAttempts = 2;
      TcpPrinterPort.busyMaxDelay = const Duration(milliseconds: 10);
      await expectLater(
        TcpPrinterPort(
          '127.0.0.1',
          port: server.port,
        ).send(Uint8List.fromList([0x1B, 0x40, 1]), checkStatus: false),
        throwsA(isA<SocketException>()),
      );
      expect(n, 3, reason: '1 lần đầu + 2 lần thử lại');
    },
  );
}
