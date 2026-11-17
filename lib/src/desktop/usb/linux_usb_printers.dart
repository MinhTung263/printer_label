import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../paper_status.dart';
import '../port_queue.dart';
import '../printer_port.dart';
import 'usb_printer_info.dart';

/// Máy in USB trên Linux qua module `usblp` có sẵn trong kernel: mỗi máy in là
/// một file `/dev/usb/lpN`, ghi byte ESC/POS vào là in — không cần driver/CUPS.
///
/// Máy in nhận theo `vendor:product:serial` (không theo số `lpN` — cắm lại cổng
/// khác số đổi). Người dùng cần quyền ghi (`/dev/usb/lp*` thuộc nhóm `lp`): bộ
/// cài `.deb` thêm quy tắc udev mở quyền cho máy in USB.
abstract final class LinuxUsbPrinters {
  static const _sysClass = '/sys/class/usbmisc';
  static const prefix = 'usb:';

  static Future<List<UsbPrinterInfo>> list() async {
    final dir = Directory(_sysClass);
    if (!dir.existsSync()) return const [];
    final found = <UsbPrinterInfo>[];
    for (final e in dir.listSync()) {
      final lp = e.path.split('/').last;
      if (!lp.startsWith('lp')) continue;
      final dev = '/dev/usb/$lp';
      if (!File(dev).existsSync()) continue;
      // `device` trỏ tới interface USB; thư mục cha là thiết bị (idVendor...).
      final usb = Directory('${e.path}/device/..');
      String read(String name) {
        try {
          return File('${usb.path}/$name').readAsStringSync().trim();
        } catch (_) {
          return '';
        }
      }

      final vid = read('idVendor');
      final pid = read('idProduct');
      final name = '${read('manufacturer')} ${read('product')}'.trim();
      found.add(
        UsbPrinterInfo(
          address: '$prefix$vid:$pid:${read('serial')}',
          name: name.isEmpty ? 'Máy in USB $vid:$pid' : name,
          detail: dev,
        ),
      );
    }
    found.sort((a, b) => a.detail.compareTo(b.detail));
    return found;
  }

  /// File thiết bị hiện tại của máy in [address]; `null` khi không cắm.
  static Future<String?> devicePath(String address) async {
    for (final p in await list()) {
      if (p.address == address) return p.detail;
    }
    // Không có serial: máy cùng vendor:product đầu tiên.
    final loose = address.substring(0, address.lastIndexOf(':') + 1);
    for (final p in await list()) {
      if (p.address.startsWith(loose)) return p.detail;
    }
    return null;
  }
}

class LinuxUsbPrinterPort implements PrinterPort {
  LinuxUsbPrinterPort(this.address, {this.chunkSize = 4096});

  final String address;
  final int chunkSize;

  @override
  String get id => address;

  @override
  Future<void> send(
    Uint8List data, {
    bool checkStatus = true,
  }) => PortQueue.run(id, () async {
    final dev = await LinuxUsbPrinters.devicePath(address);
    if (dev == null) throw UsbPrinterNotFound(address);
    final raf = await File(dev).open(mode: FileMode.writeOnlyAppend);
    try {
      // `usblp` chặn khi máy in tắt / hết giấy: có giới hạn thời gian để không treo mãi.
      await _write(raf, data).timeout(
        writeTimeout,
        onTimeout: () => throw TimeoutException(
          'Máy in USB không nhận dữ liệu',
          writeTimeout,
        ),
      );
    } finally {
      // Không chờ đóng nếu đang kẹt — đóng nền.
      unawaited(raf.close().catchError((_) => raf));
    }
  });

  /// Giới hạn một lần gửi tới máy in USB.
  static Duration writeTimeout = const Duration(seconds: 20);

  Future<void> _write(RandomAccessFile raf, Uint8List data) async {
    for (var off = 0; off < data.length; off += chunkSize) {
      final end = off + chunkSize < data.length ? off + chunkSize : data.length;
      await raf.writeFrom(data, off, end);
    }
  }

  /// `usblp` đọc trạng thái không ổn định giữa các máy — không hỏi giấy.
  @override
  Future<PaperStatus> queryStatus() async => PaperStatus.unknown;
}
