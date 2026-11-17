import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../paper_status.dart';
import '../port_queue.dart';
import '../printer_port.dart';
import 'usb_printer_info.dart';

/// Máy in USB trên Linux đã cài trong CUPS — dự phòng cho máy `usblp` không nhận (không
/// có `/dev/usb/lp*`, VD driver CUPS giữ cổng) hoặc máy chỉ có trong CUPS. Gửi byte thô bằng
/// `lp -d <hàng in> -o raw` (CUPS không dựng trang, không qua driver).
///
/// Chỉ liệt kê hàng in có địa chỉ `usb://` — máy in mạng đã có đường LAN riêng, máy in ảo
/// (PDF, fax…) không in được ESC/POS.
abstract final class LinuxCupsPrinters {
  static const prefix = 'lpq:';

  static final _virtual = RegExp(
    r'cups-pdf|pdf|fax|virtual|onenote|null',
    caseSensitive: false,
  );

  /// Đọc kết quả `lpstat -v` (`device for <tên>: <địa chỉ>`) → (tên hàng in, địa chỉ),
  /// bỏ máy in ảo và địa chỉ không phải USB. Thuần — kiểm thử được.
  static List<({String name, String uri})> parse(String lpstatV) {
    final re = RegExp(r'^device for\s+(.+?):\s+(\S+)\s*$');
    final out = <({String name, String uri})>[];
    for (final line in const LineSplitter().convert(lpstatV)) {
      final m = re.firstMatch(line.trim());
      if (m == null) continue;
      final name = m.group(1)!.trim();
      final uri = m.group(2)!.trim();
      if (!uri.toLowerCase().startsWith('usb://')) continue;
      if (_virtual.hasMatch(name) || _virtual.hasMatch(uri)) continue;
      out.add((name: name, uri: uri));
    }
    return out;
  }

  /// Hàng in CUPS [uri] (`usb://Hãng/Model?serial=…`) chính là một trong các máy in USB đã
  /// thấy trực tiếp ([directNames]) — không liệt kê hai lần.
  static bool isDuplicate(String uri, Iterable<String> directNames) {
    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final parsed = Uri.tryParse(uri);
    final model = norm(
      Uri.decodeComponent(
        parsed == null ? '' : parsed.path.replaceAll('/', ' '),
      ),
    );
    if (model.isEmpty) return false;
    return directNames.any((n) => norm(n).contains(model));
  }

  static (DateTime, List<({String name, String uri})>)? _cache;

  static Future<List<({String name, String uri})>> _queues() async {
    // Dò rút / cắm dày: dùng lại kết quả `lpstat` vừa chạy trong 1,5s (mỗi lần là một tiến trình).
    final hit = _cache;
    if (hit != null &&
        DateTime.now().difference(hit.$1) <
            const Duration(milliseconds: 1500)) {
      return hit.$2;
    }
    final fresh = await _runLpstat();
    _cache = (DateTime.now(), fresh);
    return fresh;
  }

  static Future<List<({String name, String uri})>> _runLpstat() async {
    try {
      final r = await Process.run(
        'lpstat',
        ['-v'],
        environment: {'LC_ALL': 'C'},
      ).timeout(const Duration(seconds: 4));
      return r.exitCode == 0 ? parse('${r.stdout}') : const [];
    } catch (_) {
      return const [];
    }
  }

  /// Hàng in USB trong CUPS, trừ máy đã có đường trực tiếp ([directNames]).
  static Future<List<UsbPrinterInfo>> list({
    Iterable<String> directNames = const [],
  }) async => [
    for (final q in await _queues())
      if (!isDuplicate(q.uri, directNames))
        UsbPrinterInfo(
          address: '$prefix${q.name}',
          name: q.name.replaceAll('_', ' '),
          detail: 'CUPS',
        ),
  ];

  static Future<bool> present(String address) async {
    final name = address.substring(prefix.length);
    return (await _queues()).any((q) => q.name == name);
  }
}

class LinuxCupsPrinterPort implements PrinterPort {
  LinuxCupsPrinterPort(this.address);

  final String address;

  static Duration sendTimeout = const Duration(seconds: 30);

  String get queue => address.substring(LinuxCupsPrinters.prefix.length);

  @override
  String get id => address;

  @override
  Future<void> send(Uint8List data, {bool checkStatus = true}) =>
      PortQueue.run(id, () async {
        if (!await LinuxCupsPrinters.present(address)) {
          throw UsbPrinterNotFound(address);
        }
        final proc = await Process.start('lp', ['-d', queue, '-o', 'raw']);
        final stderr = proc.stderr.transform(utf8.decoder).join();
        unawaited(proc.stdout.drain<void>());
        try {
          proc.stdin.add(data);
          await proc.stdin.close();
          final code = await proc.exitCode.timeout(sendTimeout);
          if (code != 0) {
            throw FileSystemException(
              'lp lỗi $code: ${(await stderr).trim()}',
              queue,
            );
          }
        } on TimeoutException {
          proc.kill();
          rethrow;
        }
      });

  /// CUPS không trả trạng thái giấy của lệnh thô — không hỏi.
  @override
  Future<PaperStatus> queryStatus() async => PaperStatus.unknown;
}
