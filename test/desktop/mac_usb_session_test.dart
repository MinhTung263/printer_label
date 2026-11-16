import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  late Directory dir;
  late String savedBackend;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('usb_session_');
    savedBackend = MacUsbSession.backendPath;
  });
  tearDown(() async {
    await MacUsbSession.closeAll();
    MacUsbSession.backendPath = savedBackend;
    dir.deleteSync(recursive: true);
  });

  /// Backend giả: báo nối máy in rồi ghi mọi byte nhận được ra tệp ngay lập tức.
  String fakeBackend({bool exitAtOnce = false}) {
    final out = '${dir.path}/out.bin';
    final script = File('${dir.path}/usb')
      ..writeAsStringSync(
        exitAtOnce
            ? '#!/bin/sh\nexit 1\n'
            : '#!/bin/sh\necho "INFO: Sending data to printer." >&2\ncat > "$out"\nsleep 1\n',
      );
    Process.runSync('chmod', ['+x', script.path]);
    return script.path;
  }

  test(
    'nhiều phiếu liên tiếp đi thẳng vào máy in trong CÙNG một phiên (không chờ đóng)',
    () async {
      MacUsbSession.backendPath = fakeBackend();
      final s = (await MacUsbSession.of('Q', 'usb://x'))!;
      expect(await s.waitConnected(const Duration(seconds: 3)), isTrue);
      final sw = Stopwatch()..start();
      for (var i = 1; i <= 3; i++) {
        await s.write(Uint8List.fromList([i, i]));
      }
      // Backend giả ghi ra tệp ngay khi nhận — chưa đóng phiên mà dữ liệu đã tới.
      final out = File('${dir.path}/out.bin');
      for (
        var i = 0;
        i < 40 && (!out.existsSync() || out.lengthSync() < 6);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(out.readAsBytesSync(), [1, 1, 2, 2, 3, 3]);
      expect(sw.elapsedMilliseconds, lessThan(2500));
      expect(MacUsbSession.peek('Q'), same(s));
    },
    skip: Platform.isMacOS ? false : 'chỉ macOS',
  );

  test(
    'backend thoát ngay (không nối được máy in): không báo nối, không nhận dữ liệu',
    () async {
      MacUsbSession.backendPath = fakeBackend(exitAtOnce: true);
      final s = (await MacUsbSession.of('Q2', 'usb://x'))!;
      expect(await s.waitConnected(const Duration(seconds: 2)), isFalse);
      expect(MacUsbSession.peek('Q2'), isNull);
      s.kill();
    },
    skip: Platform.isMacOS ? false : 'chỉ macOS',
  );
}
