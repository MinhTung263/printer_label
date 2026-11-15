import 'dart:io';
import 'dart:typed_data';

import '../paper_status.dart';
import '../port_queue.dart';
import '../printer_port.dart';
import 'usb_printer_info.dart';

/// Máy in USB trên macOS qua CUPS có sẵn của hệ điều hành, KHÔNG cần driver
/// hãng: máy in cắm vào được tạo một hàng in RAW (`lpadmin -m raw`) — CUPS
/// chuyển nguyên byte ESC/POS xuống máy in. Địa chỉ `cups:<tên hàng in>`.
///
/// - [list]: hàng in đang có (máy USB lên đầu) + máy in USB CUPS thấy mà chưa
///   có hàng in ([UsbPrinterInfo.setupPort] là URI `usb://...`).
/// - [createRawQueue]: tạo hàng in — tài khoản quản trị của Mac (mặc định) tạo
///   được không cần mật khẩu; tài khoản thường thì macOS từ chối.
abstract final class MacCupsPrinters {
  static const prefix = 'cups:';

  /// Tên hàng in do app tạo.
  static const queuePrefix = 'EasyPOS_';

  static const _timeout = Duration(seconds: 15);

  static Future<List<UsbPrinterInfo>> list() async {
    final queues = parseLpstat(await _run('lpstat', ['-v']));
    final devices = parseLpinfo(
      await _run('lpinfo', ['--include-schemes', 'usb', '-v']),
    );
    final used = {for (final q in queues) q.uri};
    final items =
        [
          for (final q in queues)
            UsbPrinterInfo(
              address: '$prefix${q.name}',
              name: q.name.startsWith(queuePrefix)
                  ? q.name.substring(queuePrefix.length).replaceAll('_', ' ')
                  : q.name,
              detail: q.uri.startsWith('usb:') ? 'USB' : q.uri.split(':').first,
            ),
        ]..sort(
          (a, b) => (a.detail == 'USB' ? 0 : 1) - (b.detail == 'USB' ? 0 : 1),
        );
    return [
      ...items,
      for (final uri in devices)
        if (!used.contains(uri))
          UsbPrinterInfo(
            address: '',
            name: modelOf(uri),
            detail: 'USB · chưa có hàng in',
            setupPort: uri,
          ),
    ];
  }

  /// Tạo hàng in RAW cho máy in USB [uri]. Trả địa chỉ hàng in mới, `null` khi
  /// không tạo được (tài khoản không có quyền quản trị...).
  static Future<String?> createRawQueue(String uri) async {
    final name = queueNameFor(uri);
    final r = await Process.run('lpadmin', [
      '-p',
      name,
      '-E',
      '-v',
      uri,
      '-m',
      'raw',
      '-o',
      'printer-is-shared=false',
    ]).timeout(_timeout);
    if (r.exitCode != 0) return null;
    return await exists('$prefix$name') ? '$prefix$name' : null;
  }

  static Future<bool> exists(String address) async {
    final name = address.substring(prefix.length);
    return parseLpstat(await _run('lpstat', ['-v'])).any((q) => q.name == name);
  }

  /// Hàng in còn và máy in USB của nó đang cắm (hàng in mạng: chỉ cần còn).
  static Future<bool> present(String address) async {
    final name = address.substring(prefix.length);
    final queue = parseLpstat(
      await _run('lpstat', ['-v']),
    ).where((q) => q.name == name).firstOrNull;
    if (queue == null) return false;
    if (!queue.uri.startsWith('usb:')) return true;
    final devices = parseLpinfo(
      await _run('lpinfo', ['--include-schemes', 'usb', '-v']),
    );
    return devices.contains(queue.uri);
  }

  /// `device for Q: usb://...` (dòng của `lpstat -v`, cả bản tiếng Anh).
  static List<({String name, String uri})> parseLpstat(String out) {
    final re = RegExp(r'^device for ([^:]+):\s*(\S+)', multiLine: true);
    return [
      for (final m in re.allMatches(out))
        (name: m.group(1)!.trim(), uri: m.group(2)!.trim()),
    ];
  }

  /// URI máy in USB trong `lpinfo -v` (`direct usb://Hãng/Model?serial=...`).
  static List<String> parseLpinfo(String out) => [
    for (final line in out.split('\n'))
      if (RegExp(r'^\s*direct\s+usb://').hasMatch(line))
        line.trim().split(RegExp(r'\s+'))[1],
  ];

  /// `usb://XPrinter/XP-80C?serial=123` → `XPrinter XP-80C`.
  static String modelOf(String uri) {
    final path = Uri.decodeComponent(
      uri.replaceFirst(RegExp('^usb://'), '').split('?').first,
    );
    final name = path.replaceAll('/', ' ').trim();
    return name.isEmpty ? 'Máy in USB' : name;
  }

  /// Tên hàng in hợp lệ với CUPS (chữ, số, `_`), kèm đuôi serial để hai máy
  /// cùng model không trùng tên.
  static String queueNameFor(String uri) {
    String clean(String s) => s
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final model = clean(modelOf(uri));
    final serial = clean(Uri.tryParse(uri)?.queryParameters['serial'] ?? '');
    final tail = serial.length > 6
        ? serial.substring(serial.length - 6)
        : serial;
    final base = model.isEmpty ? 'USB' : model;
    return '$queuePrefix$base${tail.isEmpty ? '' : '_$tail'}';
  }

  static Future<String> _run(String cmd, List<String> args) async {
    try {
      final r = await Process.run(cmd, args).timeout(_timeout);
      return '${r.stdout}';
    } catch (_) {
      return '';
    }
  }
}

/// Gửi byte ESC/POS qua hàng in RAW của CUPS (`lp -o raw`).
class MacCupsPrinterPort implements PrinterPort {
  MacCupsPrinterPort(this.address);

  final String address;

  String get _queue => address.substring(MacCupsPrinters.prefix.length);

  @override
  String get id => address;

  @override
  Future<void> send(Uint8List data, {bool checkStatus = true}) =>
      PortQueue.run(id, () async {
        if (!await MacCupsPrinters.exists(address)) {
          throw UsbPrinterNotFound(address);
        }
        final p = await Process.start('lp', [
          '-d',
          _queue,
          '-o',
          'raw',
          '-t',
          'EasyPOS',
        ]);
        p.stdin.add(data);
        await p.stdin.close();
        final code = await p.exitCode.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            p.kill();
            return -1;
          },
        );
        if (code != 0) {
          throw ProcessException('lp', ['-d', _queue], 'lp lỗi', code);
        }
      });

  /// CUPS không trả trạng thái giấy của máy ESC/POS — không hỏi giấy.
  @override
  Future<PaperStatus> queryStatus() async => PaperStatus.unknown;
}
