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
  static Future<List<UsbPrinterInfo>> list() async =>
      usbQueues(await _queues());

  /// Đọc thẳng `EnumPrintersW` (vài ms, không bật PowerShell); lỗi bất ngờ thì quay
  /// về `Get-Printer` như trước.
  static (DateTime, List<Map<String, Object?>>)? _queuesCache;

  static Future<List<Map<String, Object?>>> _queues() async {
    // Dò rút / cắm dày (mỗi giây): dùng lại kết quả vừa liệt kê trong 1s, khỏi tạo isolate.
    final hit = _queuesCache;
    if (hit != null &&
        DateTime.now().difference(hit.$1) < const Duration(seconds: 1)) {
      return hit.$2;
    }
    try {
      final out = await Isolate.run(
        _enumQueues,
      ).timeout(const Duration(seconds: 5));
      _queuesCache = (DateTime.now(), out);
      return out;
    } catch (_) {
      return _psJson(
        'Get-Printer | Select-Object Name,PortName,DriverName,WorkOffline',
      );
    }
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
    _queuesCache = null; // hàng in vừa đổi: bỏ kết quả liệt kê cũ
    final exists = await _psJson(
      "Get-Printer -Name '$name' -ErrorAction SilentlyContinue | "
      'Select-Object Name',
    );
    return exists.isEmpty ? null : '$prefix$name';
  }

  /// Xả mọi lệnh đang kẹt trong hàng in [name] (`PRINTER_CONTROL_PURGE`) — nút
  /// "Làm sạch hàng đợi" khi máy in từng hết giấy / tắt nguồn. Không cần quyền
  /// quản trị nếu hàng in của người dùng; `false` khi không xả được.
  static Future<bool> purgeQueue(String name) => Isolate.run(
    () => _purge(name),
  ).timeout(const Duration(seconds: 10), onTimeout: () => false);

  static Future<bool> exists(String address) async {
    final name = address.substring(prefix.length);
    return (await _queues()).any(
      (p) => '${p['Name']}'.toLowerCase() == name.toLowerCase(),
    );
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
  Future<void> send(
    Uint8List data, {
    bool checkStatus = true,
  }) => PortQueue.run(id, () async {
    final name = queueName;
    var error = await _sendInIsolate(name, data);
    // Lệnh cũ kẹt trong spooler (máy in từng tắt / hết giấy) làm lệnh mới không mở được:
    // xả hàng đợi rồi thử lại MỘT lần. Chỉ thử lại khi CHƯA gửi byte nào (lỗi ở bước
    // StartDocPrinter) — lỗi giữa chừng thì không in lại để khỏi ra hai phiếu.
    if (error != null && error.startsWith('StartDocPrinter')) {
      await WindowsRawPrinters.purgeQueue(name);
      error = await _sendInIsolate(name, data);
    }
    if (error == null) return;
    if (error.startsWith('OpenPrinter')) throw UsbPrinterNotFound(address);
    throw FileSystemException(error, name);
  });

  /// Lệnh spooler chạy đồng bộ — đưa sang isolate cho khỏi đứng giao diện; quá
  /// [sendTimeout] thì thôi chờ (không để một lệnh treo giữ mãi hàng đợi máy in).
  static Duration sendTimeout = const Duration(seconds: 30);

  static Future<String?> _sendInIsolate(String name, Uint8List data) =>
      Isolate.run(
        () => _rawPrint(name, data),
      ).timeout(sendTimeout, onTimeout: () => 'WritePrinter timeout');

  /// Spooler không trả trạng thái giấy của lệnh RAW — không hỏi.
  @override
  Future<PaperStatus> queryStatus() async => PaperStatus.unknown;
}

/// Kích thước mỗi lần `WritePrinter`.
const int writeChunk = 4096;

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
        // Gửi từng gói [writeChunk]: một cục lớn dễ tràn bộ đệm máy in giá rẻ.
        var sent = 0;
        var error = 0;
        while (sent < data.length) {
          final n = data.length - sent < writeChunk
              ? data.length - sent
              : writeChunk;
          final ok = api.writePrinter(h, buf + sent, n, written) != 0;
          if (!ok || written.value != n) {
            error = ok ? 0 : api.getLastError();
            sent += ok ? written.value : 0;
            break;
          }
          sent += n;
        }
        api.endPagePrinter(h);
        if (sent != data.length) {
          return 'WritePrinter $error ($sent/${data.length})';
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

/// `PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS`.
const int _enumFlags = 0x2 | 0x4;
const int _attributeWorkOffline = 0x400;

/// Liệt kê hàng in bằng `EnumPrintersW` cấp 2; cùng khoá với `Get-Printer`
/// (`Name`, `PortName`, `DriverName`, `WorkOffline`). Chạy trong isolate.
List<Map<String, Object?>> _enumQueues() {
  final api = Winspool();
  final needed = calloc<Uint32>();
  final returned = calloc<Uint32>();
  try {
    api.enumPrinters(_enumFlags, nullptr, 2, nullptr, 0, needed, returned);
    final size = needed.value;
    if (size == 0) return const [];
    final buf = calloc<Uint8>(size);
    try {
      final ok = api.enumPrinters(
        _enumFlags,
        nullptr,
        2,
        buf,
        size,
        needed,
        returned,
      );
      if (ok == 0) throw const FileSystemException('EnumPrinters');
      final infos = buf.cast<PrinterInfo2>();
      String str(Pointer<Utf16> p) => p == nullptr ? '' : p.toDartString();
      return [
        for (var i = 0; i < returned.value; i++)
          () {
            final info = (infos + i).ref;
            return <String, Object?>{
              'Name': str(info.pPrinterName),
              'PortName': str(info.pPortName),
              'DriverName': str(info.pDriverName),
              'WorkOffline': info.attributes & _attributeWorkOffline != 0,
            };
          }(),
      ];
    } finally {
      calloc.free(buf);
    }
  } finally {
    calloc
      ..free(needed)
      ..free(returned);
  }
}

/// `PRINTER_ACCESS_ADMINISTER | PRINTER_ACCESS_USE`.
const int _accessAdminister = 0x4 | 0x8;
const int _purgeCommand = 3;

bool _purge(String printer) {
  final api = Winspool();
  final name = printer.toNativeUtf16();
  final handle = calloc<IntPtr>();
  final defaults = calloc<PrinterDefaults>();
  try {
    defaults.ref
      ..pDatatype = nullptr
      ..pDevMode = nullptr
      ..desiredAccess = _accessAdminister;
    if (api.openPrinter(name, handle, defaults.cast()) == 0) return false;
    final h = handle.value;
    try {
      return api.setPrinter(h, 0, nullptr, _purgeCommand) != 0;
    } finally {
      api.closePrinter(h);
    }
  } finally {
    calloc
      ..free(name)
      ..free(handle)
      ..free(defaults);
  }
}
