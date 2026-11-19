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

  setUp(() async {
    printer = await FakeLanPrinter.start();
    port = TcpPrinterPort(
      '127.0.0.1',
      port: printer.port,
      statusTimeout: const Duration(milliseconds: 150),
      chunkSize: 1000,
    );
  });
  tearDown(() => printer.close());

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
    expect(printer.jobs.last, EscPosCommands.receipt(raster, copies: 2));
  });

  test('không kết nối được máy in thì báo lỗi', () async {
    await printer.close();
    await expectLater(
      TcpPrinterPort('127.0.0.1', port: printer.port).send(Uint8List(1)),
      throwsA(isA<SocketException>()),
    );
  });

  test(
    'lần gửi trước đứt giữa chừng: lần sau xả bộ đệm (0x00 x1024 + ESC @) rồi mới in',
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
      expect(got.length, 1026 + 3);
      expect(got.sublist(0, 1024).every((b) => b == 0), isTrue);
      expect(got.sublist(1024, 1026), [0x1B, 0x40]);
      expect(got.sublist(1026), [1, 2, 3]);
      // Lần thứ ba: đã xả rồi nên không xả nữa.
      await p.send(Uint8List.fromList([9]), checkStatus: false);
      for (var i = 0; i < 100 && jobs.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(jobs.last, [9]);
    },
  );
}
