import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  late Future<ProcessResult> Function(String, List<String>) saved;
  setUp(() => saved = MacCupsPrinters.processRunner);
  tearDown(() => MacCupsPrinters.processRunner = saved);

  const uri = 'usb://Gprinter/USB%20Printer?serial=1';
  final queue = MacCupsPrinters.queueNameFor(uri);

  test('macOS mới từ chối raw → dùng driver Generic', () async {
    final calls = <List<String>>[];
    MacCupsPrinters.processRunner = (cmd, args) async {
      calls.add([cmd, ...args]);
      if (cmd == 'lpadmin' && args.contains('raw')) {
        return ProcessResult(
          0,
          1,
          '',
          'lpadmin: Raw queues are no longer supported on macOS.',
        );
      }
      if (cmd == 'lpadmin') return ProcessResult(0, 0, '', '');
      return ProcessResult(0, 0, 'device for $queue: $uri\n', '');
    };
    final address = await MacCupsPrinters.createRawQueue(uri);
    expect(address, isNotNull);
    expect(MacCupsPrinters.lastError, isNull);
    expect(calls.any((c) => c.contains(MacCupsPrinters.genericDriver)), isTrue);
  });

  test('thiếu quyền → hỏi mật khẩu quản trị qua osascript', () async {
    final cmds = <String>[];
    MacCupsPrinters.processRunner = (cmd, args) async {
      cmds.add(cmd);
      if (cmd == 'lpadmin') {
        return ProcessResult(0, 1, '', 'lpadmin: Unauthorized');
      }
      if (cmd == 'osascript') return ProcessResult(0, 0, '', '');
      return ProcessResult(0, 0, 'device for $queue: $uri\n', '');
    };
    expect(await MacCupsPrinters.createRawQueue(uri), isNotNull);
    expect(cmds, contains('osascript'));
  });

  test('người dùng huỷ → báo lý do dễ hiểu', () async {
    MacCupsPrinters.processRunner = (cmd, args) async => ProcessResult(
      0,
      1,
      '',
      cmd == 'osascript'
          ? 'execution error: User canceled. (-128)'
          : 'lpadmin: Unauthorized',
    );
    expect(await MacCupsPrinters.createRawQueue(uri), isNull);
    expect(MacCupsPrinters.lastError, contains('huỷ'));
  });

  test('thoát chuỗi cho shell và AppleScript', () {
    expect(MacCupsPrinters.shellQuote("a'b"), r"'a'\''b'");
    expect(MacCupsPrinters.appleScriptQuote(r'a"b\c'), r'"a\"b\\c"');
  });
}
