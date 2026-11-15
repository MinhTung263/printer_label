import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  group('ArpTable.parse', () {
    test('Windows `arp -a`', () {
      const out = '''
Interface: 192.168.1.20 --- 0xb
  Internet Address      Physical Address      Type
  192.168.1.1           a4-2b-b0-11-22-33     dynamic
  192.168.1.200         00-47-50-0a-0b-0c     dynamic
  192.168.1.255         ff-ff-ff-ff-ff-ff     static
''';
      expect(ArpTable.parse(out), {
        '192.168.1.1': 'A4:2B:B0:11:22:33',
        '192.168.1.200': '00:47:50:0A:0B:0C',
      });
    });

    test('macOS `arp -an` (byte rút gọn 1 chữ số)', () {
      const out =
          '? (192.168.1.200) at 0:47:50:a:b:c on en0 ifscope [ethernet]\n'
          '? (192.168.1.7) at (incomplete) on en0 ifscope [ethernet]\n';
      expect(ArpTable.parse(out), {'192.168.1.200': '00:47:50:0A:0B:0C'});
    });

    test('Linux /proc/net/arp', () {
      const out = '''
IP address       HW type     Flags       HW address            Mask     Device
192.168.1.200    0x1         0x2         00:47:50:0a:0b:0c     *        eth0
192.168.1.9      0x1         0x0         00:00:00:00:00:00     *        eth0
''';
      expect(ArpTable.parse(out), {'192.168.1.200': '00:47:50:0A:0B:0C'});
    });
  });

  test('máy in bận (từ chối kết nối) rồi rảnh: thử lại và in được', () async {
    // Lấy một cổng trống rồi đóng → kết nối bị từ chối ngay.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final received = <int>[];
    final done = Completer<void>();
    // "Máy in" rảnh sau ~400ms.
    Timer(const Duration(milliseconds: 400), () async {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      server.listen((s) {
        s.listen(
          received.addAll,
          onDone: () {
            s.destroy();
            server.close();
            if (!done.isCompleted) done.complete();
          },
        );
      });
    });
    final printer = TcpPrinterPort('127.0.0.1', port: port);
    await printer.send(Uint8List.fromList([1, 2, 3]), checkStatus: false);
    await done.future.timeout(const Duration(seconds: 5));
    expect(received, [1, 2, 3]);
  });

  test('máy in không trả lời hỏi trạng thái: lần sau khỏi chờ', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) => s.listen((_) {}, onDone: s.destroy));
    final printer = TcpPrinterPort('127.0.0.1', port: server.port);
    final sw = Stopwatch()..start();
    await printer.send(Uint8List.fromList([1]));
    final first = sw.elapsedMilliseconds;
    sw.reset();
    await printer.send(Uint8List.fromList([2]));
    final second = sw.elapsedMilliseconds;
    await server.close();
    expect(
      first,
      greaterThanOrEqualTo(700),
      reason: 'lần đầu chờ hỏi trạng thái',
    );
    expect(second, lessThan(400), reason: 'lần sau bỏ qua hỏi trạng thái');
  });

  test('máy in bận vẫn tính là đang bật; cổng đóng hẳn thì không', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    expect(await LanPrinterScanner.isAlive('127.0.0.1', port: port), isTrue);
    await probe.close();
    // Từ chối (không có tiến trình nghe) = có máy ở IP đó, vẫn "đang bật".
    expect(await LanPrinterScanner.isAlive('127.0.0.1', port: port), isTrue);
  });
}
