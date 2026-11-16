import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../paper_status.dart';
import '../port_queue.dart';
import '../printer_port.dart';
import 'usb_printer_info.dart';
import 'winspool_bindings.dart';

/// Máy in trên Windows: gửi byte ESC/POS kiểu RAW tới một hàng in (spooler) —
/// spooler chuyển nguyên byte xuống máy in, KHÔNG qua driver dựng trang. Máy in
/// USB chưa có hàng in thì tạo bằng driver có sẵn của Windows "Generic / Text
/// Only" (không phải tải driver hãng) — xem [createRawQueue].
abstract final class WindowsRawPrinters {
  static const prefix = 'queue:';
  static const genericDriver = 'Generic / Text Only';

  /// Các máy in USB đang cắm của Windows (hàng in trên cổng `USB…`). KHÔNG liệt kê máy in
  /// ảo / hệ thống (Microsoft Print to PDF, XPS Document Writer, Fax, OneNote...), máy in
  /// mạng và hàng in của máy USB đã rút cáp — chúng không in được ESC/POS / tem và làm sơ
  /// đồ rối. Cổng `USB…` chưa có hàng in cũng KHÔNG liệt kê: Windows tạo sẵn các cổng
  /// "Virtual printer port for USB" cả khi chưa cắm máy in nào, không phân biệt được máy
  /// thật; máy in USB cắm vào Windows thường tự có hàng in.
  static Future<List<UsbPrinterInfo>> list() async {
    final printers = await _psJson(
      'Get-Printer | Select-Object Name,PortName,DriverName,WorkOffline',
    );
    return usbQueues(printers);
  }

  /// Lọc kết quả `Get-Printer` (các trường `Name`, `PortName`, `DriverName`,
  /// `WorkOffline`) còn lại máy in USB đang cắm.
  static List<UsbPrinterInfo> usbQueues(List<Map<String, Object?>> printers) =>
      [
        for (final p in printers)
          if (_isUsbQueue(p))
            UsbPrinterInfo(
              address: '$prefix${p['Name']}',
              name: '${p['Name']}',
              detail: '${p['PortName']} · ${p['DriverName']}',
            ),
      ];

  static bool _isUsbQueue(Map<String, Object?> p) {
    if (p['WorkOffline'] == true) return false;
    final port = '${p['PortName']}'.trim().toUpperCase();
    // Hàng in do chính app tạo (`EasyPOS ...`) luôn là máy in của Agent, kể cả cổng tệp / cổng
    // khác USB (máy chạy kiểm thử, hàng in RAW thử).
    return RegExp(r'^USB\d+').hasMatch(port) ||
        '${p['Name']}'.startsWith('EasyPOS');
  }

  /// Tạo hàng in RAW `EasyPOS <cổng>` trên cổng USB [port] bằng driver có sẵn
  /// [genericDriver]. Cần quyền quản trị → Windows hỏi (UAC). Trả địa chỉ hàng
  /// in mới, `null` khi không tạo được / người dùng từ chối.
  static Future<String?> createRawQueue(String port) async {
    final name = 'EasyPOS $port';
    final inner =
        "Add-Printer -Name '$name' -DriverName '$genericDriver' "
        "-PortName '$port'";
    final encoded = base64Encode(_utf16le(inner));
    await _ps(
      "Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden "
      "-ArgumentList '-NoProfile -NonInteractive -EncodedCommand $encoded'",
    );
    final exists = await _psJson(
      "Get-Printer -Name '$name' -ErrorAction SilentlyContinue | "
      'Select-Object Name',
    );
    return exists.isEmpty ? null : '$prefix$name';
  }

  static Future<bool> exists(String address) async {
    final name = address.substring(prefix.length).replaceAll("'", "''");
    final r = await _psJson(
      "Get-Printer -Name '$name' -ErrorAction SilentlyContinue | "
      'Select-Object Name',
    );
    return r.isNotEmpty;
  }

  static List<int> _utf16le(String s) => [
    for (final c in s.codeUnits) ...[c & 0xff, c >> 8],
  ];

  static Future<String> _ps(String command) async {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      command,
    ], stdoutEncoding: utf8);
    return r.stdout.toString();
  }

  /// Chạy lệnh rồi đọc JSON (một đối tượng hay danh sách đều trả danh sách).
  static Future<List<Map<String, Object?>>> _psJson(String command) async {
    try {
      final out = await _ps('$command | ConvertTo-Json -Compress');
      if (out.trim().isEmpty) return const [];
      final raw = jsonDecode(out);
      final list = raw is List ? raw : [raw];
      return [
        for (final e in list)
          if (e is Map) e.cast<String, Object?>(),
      ];
    } catch (_) {
      return const [];
    }
  }
}

class WindowsRawPrinterPort implements PrinterPort {
  WindowsRawPrinterPort(this.address);

  final String address;

  String get queueName => address.substring(WindowsRawPrinters.prefix.length);

  @override
  String get id => address;

  @override
  Future<void> send(Uint8List data, {bool checkStatus = true}) =>
      PortQueue.run(id, () async {
        final name = queueName;
        // Lệnh spooler chạy đồng bộ — đưa sang isolate cho khỏi đứng giao diện.
        final error = await Isolate.run(() => _rawPrint(name, data));
        if (error == null) return;
        if (error.startsWith('OpenPrinter')) throw UsbPrinterNotFound(address);
        throw FileSystemException(error, name);
      });

  /// Spooler không trả trạng thái giấy của lệnh RAW — không hỏi.
  @override
  Future<PaperStatus> queryStatus() async => PaperStatus.unknown;
}

/// Gửi [data] kiểu RAW tới hàng in [printer]; `null` = thành công, ngược lại là
/// bước lỗi + mã lỗi Windows.
String? _rawPrint(String printer, Uint8List data) {
  final api = Winspool();
  final name = printer.toNativeUtf16();
  final docName = 'EasyPOS'.toNativeUtf16();
  final dataType = 'RAW'.toNativeUtf16();
  final handle = calloc<IntPtr>();
  final info = calloc<DocInfo1>();
  final buf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
  final written = calloc<Uint32>();
  try {
    info.ref
      ..pDocName = docName
      ..pOutputFile = nullptr
      ..pDatatype = dataType;
    buf.asTypedList(data.length).setAll(0, data);
    if (api.openPrinter(name, handle, nullptr) == 0) {
      return 'OpenPrinter ${api.getLastError()}';
    }
    final h = handle.value;
    try {
      if (api.startDocPrinter(h, 1, info) == 0) {
        return 'StartDocPrinter ${api.getLastError()}';
      }
      try {
        api.startPagePrinter(h);
        final ok = api.writePrinter(h, buf, data.length, written) != 0;
        final error = ok ? 0 : api.getLastError();
        api.endPagePrinter(h);
        if (!ok || written.value != data.length) {
          return 'WritePrinter $error (${written.value}/${data.length})';
        }
      } finally {
        api.endDocPrinter(h);
      }
    } finally {
      api.closePrinter(h);
    }
    return null;
  } finally {
    calloc
      ..free(name)
      ..free(docName)
      ..free(dataType)
      ..free(handle)
      ..free(info)
      ..free(buf)
      ..free(written);
  }
}
