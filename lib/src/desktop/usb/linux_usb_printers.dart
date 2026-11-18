import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../paper_status.dart';
import '../port_queue.dart';
import '../printer_port.dart';
import 'ieee1284.dart';
import 'usb_printer_info.dart';

/// Máy in USB trên Linux qua module `usblp` có sẵn trong kernel: mỗi máy in là
/// một file `/dev/usb/lpN`, ghi byte ESC/POS vào là in — không cần driver/CUPS.
///
/// Máy in nhận theo `vendor:product:serial` (không theo số `lpN` — cắm lại cổng
/// khác số đổi). Người dùng cần quyền ghi (`/dev/usb/lp*` thuộc nhóm `lp`): bộ
/// cài `.deb` thêm quy tắc udev mở quyền cho máy in USB.
abstract final class LinuxUsbPrinters {
  /// Thư mục sysfs / thiết bị — đặt lại được để kiểm thử bằng thư mục giả.
  static String sysClass = '/sys/class/usbmisc';
  static String devDir = '/dev/usb';
  static String usbBus = '/sys/bus/usb/devices';
  static const prefix = 'usb:';

  static Future<List<UsbPrinterInfo>> list() async {
    final dir = Directory(sysClass);
    if (!dir.existsSync()) return const [];
    final found = <UsbPrinterInfo>[];
    for (final e in dir.listSync()) {
      final lp = e.path.split('/').last;
      if (!lp.startsWith('lp')) continue;
      final dev = '$devDir/$lp';
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
      // Chuỗi định danh IEEE 1284 do chính máy in báo (`usblp` ghi sẵn trong sysfs): máy tem như 4BARCODE
      // không khai tên trong mô tả USB nhưng khai đủ hãng, model, lệnh (`CMD:TSPL2`) ở đây.
      final ieee = _readIeee(e.path);
      var name = '${read('manufacturer')} ${read('product')}'.trim();
      if (name.isEmpty && ieee != null) name = Ieee1284.name(ieee);
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

  /// Máy in USB mà hệ điều hành THẤY nhưng Agent chưa dùng được — để báo khách vì sao thay vì im lặng:
  /// - thiết bị kiểu máy in (class 7) chưa có `/dev/usb/lpN` (module `usblp` chưa nạp, hoặc driver khác giữ);
  /// - có `/dev/usb/lpN` nhưng người dùng chưa có quyền ghi (luật udev chưa áp dụng).
  static Future<List<UsbPrinterIssue>> issues() async {
    final out = <UsbPrinterIssue>[];
    final bus = Directory(usbBus);
    if (!bus.existsSync()) return out;
    String read(String path) {
      try {
        return File(path).readAsStringSync().trim();
      } catch (_) {
        return '';
      }
    }

    for (final e in bus.listSync()) {
      final base = e.path.split('/').last;
      if (!base.contains(':')) continue; // chỉ interface (VD `1-1:1.0`)
      if (read('${e.path}/bInterfaceClass') != '07') continue;
      final usb = '${e.path}/..';
      final vid = read('$usb/idVendor');
      final pid = read('$usb/idProduct');
      final ieee = _readIeee(e.path);
      var name = '${read('$usb/manufacturer')} ${read('$usb/product')}'.trim();
      if (name.isEmpty && ieee != null) name = Ieee1284.name(ieee);
      if (name.isEmpty) name = 'USB $vid:$pid';

      final misc = Directory('${e.path}/usbmisc');
      final lp = misc.existsSync()
          ? misc
                .listSync()
                .map((x) => x.path.split('/').last)
                .where((n) => n.startsWith('lp'))
                .firstOrNull
          : null;
      if (lp == null) {
        String? driver;
        try {
          driver = Link('${e.path}/driver').targetSync().split('/').last;
        } catch (_) {}
        out.add(
          UsbPrinterIssue(
            name,
            'hệ điều hành thấy máy in nhưng chưa cho dùng cổng in '
            '(${driver == null ? 'chưa có driver máy in USB — module usblp chưa nạp' : 'đang do driver "$driver" giữ'}). '
            'Chạy "sudo modprobe usblp" rồi rút và cắm lại máy in; bản cài .deb của Agent '
            'tự nạp usblp mỗi lần khởi động.',
          ),
        );
        continue;
      }
      final dev = '$devDir/$lp';
      if (!File(dev).existsSync()) continue;
      try {
        final raf = await File(
          dev,
        ).open(mode: FileMode.append).timeout(const Duration(seconds: 1));
        await raf.close();
      } on FileSystemException catch (ex) {
        if (ex.osError?.errorCode == 13) {
          out.add(
            UsbPrinterIssue(
              name,
              'không có quyền ghi $dev. Cài bản .deb mới nhất của Agent (có quy tắc udev) rồi rút và '
              'cắm lại máy in; hoặc thêm người dùng vào nhóm lp: sudo usermod -aG lp \$USER rồi đăng nhập lại.',
            ),
          );
        }
      } catch (_) {}
    }
    return out;
  }

  /// Chuỗi định danh IEEE 1284 của máy in ở thư mục lớp [classPath] (`.../usbmisc/lpN`), `null` khi
  /// không đọc được. File `ieee1284_id` nằm ở interface USB (`device`) — hoặc ở chính thư mục (kiểm thử).
  static String? _readIeee(String classPath) {
    for (final path in [
      '$classPath/device/ieee1284_id',
      '$classPath/ieee1284_id',
    ]) {
      try {
        final text = File(path).readAsStringSync().trim();
        if (text.isNotEmpty) return text;
      } catch (_) {}
    }
    return null;
  }

  /// Chuỗi định danh IEEE 1284 của máy in USB [address] (`MFG:..;CMD:TSPL2;MDL:..;`): máy hiểu lệnh
  /// nào (tem / hoá đơn); `null` khi không đọc được.
  static Future<String?> deviceId(String address) async {
    final dev = await devicePath(address);
    if (dev == null) return null;
    final lp = dev.split('/').last;
    return _readIeee('$sysClass/$lp');
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
