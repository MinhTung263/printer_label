import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:printer_label/desktop.dart';

/// Máy tem TSPL giả: trả lời `<ESC>!?` bằng [statusByte] (`null` = im lặng), ghi lại các byte
/// còn lại của mỗi kết nối (không gồm câu hỏi trạng thái).
class FakeTsplPrinter {
  FakeTsplPrinter._(this._server) {
    _server.listen((s) {
      final buf = BytesBuilder();
      s.listen(
        (data) {
          for (var i = 0; i < data.length; i++) {
            if (i + 2 < data.length &&
                data[i] == 0x1B &&
                data[i + 1] == 0x21 &&
                data[i + 2] == 0x3F) {
              queries++;
              final b = statusByte;
              if (b != null) s.add([b]);
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

  static Future<FakeTsplPrinter> start() async => FakeTsplPrinter._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  final ServerSocket _server;
  final List<Uint8List> jobs = [];
  int queries = 0;
  int? statusByte = 0x00;
  int get port => _server.port;
  Future<void> close() => _server.close();

  Future<void> waitJobs(int n) async {
    for (var i = 0; i < 100 && jobs.length < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

Uint8List _png() {
  final image = img.Image(width: 16, height: 16);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late FakeTsplPrinter printer;
  late TcpPrinterPort port;
  const spec = TsplLabelSpec(widthMm: 40, heightMm: 30);

  setUp(() async {
    printer = await FakeTsplPrinter.start();
    port = TcpPrinterPort(
      '127.0.0.1',
      port: printer.port,
      statusTimeout: const Duration(milliseconds: 200),
    );
  });
  tearDown(() async {
    TcpPrinterPort.noStatusFor = const Duration(seconds: 60);
    await printer.close();
  });

  test('parseTspl: từng bit trạng thái', () {
    expect(PaperStatus.parseTspl(0x00), PaperStatus.ok);
    expect(PaperStatus.parseTspl(0x01), PaperStatus.coverOpen);
    expect(PaperStatus.parseTspl(0x02), PaperStatus.jam);
    expect(PaperStatus.parseTspl(0x04), PaperStatus.paperEnd);
    expect(PaperStatus.parseTspl(0x08), PaperStatus.ribbonEnd);
    // Đang in / tạm dừng: vẫn nhận lệnh.
    expect(PaperStatus.parseTspl(0x20), PaperStatus.ok);
    expect(PaperStatus.parseTspl(0x10), PaperStatus.ok);
    // Mở nắp thắng hết giấy khi cùng báo.
    expect(PaperStatus.parseTspl(0x05), PaperStatus.coverOpen);
    // Chữ cái / byte ngoài dải: máy không hiểu lệnh → không đoán.
    expect(PaperStatus.parseTspl(0x41), PaperStatus.unknown);
    expect(PaperStatus.parseTspl(0x80), PaperStatus.unknown);
  });

  test('máy tem sẵn sàng: hỏi trạng thái rồi gửi tem', () async {
    await TsplPrinter.printImages(port, [_png()], spec: spec);
    await printer.waitJobs(1);
    expect(printer.queries, 1);
    expect(String.fromCharCodes(printer.jobs.single), contains('BITMAP'));
  });

  for (final (byte, status) in [
    (0x01, PaperStatus.coverOpen),
    (0x04, PaperStatus.paperEnd),
    (0x08, PaperStatus.ribbonEnd),
    (0x02, PaperStatus.jam),
  ]) {
    test('máy báo $status: KHÔNG gửi tem (Agent sẽ giữ lệnh)', () async {
      printer.statusByte = byte;
      await expectLater(
        TsplPrinter.printImages(port, [_png()], spec: spec),
        throwsA(
          isA<PrinterStatusException>().having(
            (e) => e.status,
            'status',
            status,
          ),
        ),
      );
      await printer.waitJobs(1);
      expect(printer.jobs.single, isEmpty, reason: 'chưa gửi byte nào');
    });
  }

  test('đang in tem trước (0x20): vẫn gửi tiếp', () async {
    printer.statusByte = 0x20;
    await TsplPrinter.printImages(port, [_png()], spec: spec);
    await printer.waitJobs(1);
    expect(String.fromCharCodes(printer.jobs.single), contains('PRINT'));
  });

  test('máy im lặng: vẫn in, và lần sau không chờ hỏi lại', () async {
    printer.statusByte = null;
    await TsplPrinter.printImages(port, [_png()], spec: spec);
    await printer.waitJobs(1);
    expect(printer.queries, 1);
    final sw = Stopwatch()..start();
    await TsplPrinter.printImages(port, [_png()], spec: spec);
    await printer.waitJobs(2);
    expect(printer.queries, 1, reason: 'đã nhớ máy không trả lời');
    expect(sw.elapsedMilliseconds, lessThan(190));
  });
}
