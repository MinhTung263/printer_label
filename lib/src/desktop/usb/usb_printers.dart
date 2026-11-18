import 'dart:io';

import '../printer_port.dart';
import 'linux_cups_printers.dart';
import 'linux_usb_printers.dart';
import 'mac_cups_printers.dart';
import 'usb_printer_info.dart';
import 'windows_raw_printers.dart';
import 'windows_usb_print.dart';

/// Máy in cắm trực tiếp vào máy tính, theo hệ điều hành:
/// - Linux: `/dev/usb/lpN` (địa chỉ `usb:<vid>:<pid>:<serial>`);
/// - Windows: nói chuyện thẳng với driver máy in USB có sẵn của hệ điều hành (địa chỉ
///   `usbp:<đường dẫn thiết bị>`, không cần driver hãng / hàng in) hoặc hàng in RAW cũ
///   (`queue:<tên hàng in>`);
/// - macOS: hàng in RAW của CUPS (địa chỉ `cups:<tên hàng in>`).
abstract final class UsbPrinters {
  static bool get supported =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// Địa chỉ [address] là máy in USB / hàng in (không phải LAN).
  static bool isLocal(String address) =>
      address.startsWith(LinuxUsbPrinters.prefix) ||
      address.startsWith(LinuxCupsPrinters.prefix) ||
      address.startsWith(WindowsRawPrinters.prefix) ||
      address.startsWith(WindowsUsbPrint.prefix) ||
      address.startsWith(MacCupsPrinters.prefix);

  static Future<List<UsbPrinterInfo>> list() async {
    try {
      if (Platform.isLinux) {
        final direct = await LinuxUsbPrinters.list();
        // Máy chỉ có trong CUPS (hoặc `usblp` không nhận): dự phòng qua `lp -o raw`.
        final cups = await LinuxCupsPrinters.list(
          directNames: [for (final d in direct) d.name],
        );
        return [...direct, ...cups];
      }
      if (Platform.isWindows) {
        // Máy in USB cắm trực tiếp (không cần hàng in / driver) + hàng in do chính app tạo trước đây.
        final direct = await WindowsUsbPrint.list();
        final queues = await WindowsRawPrinters.list();
        return [
          ...direct,
          for (final q in queues)
            if (q.name.startsWith('EasyPOS')) q,
        ];
      }
      if (Platform.isMacOS) return await MacCupsPrinters.list();
    } catch (_) {}
    return const [];
  }

  /// Máy in USB mà hệ điều hành thấy nhưng chưa dùng được, kèm lý do (mới có trên Linux: chưa có cổng
  /// `/dev/usb/lpN` hoặc chưa có quyền ghi); nơi khác rỗng.
  static Future<List<UsbPrinterIssue>> issues() async {
    try {
      if (Platform.isLinux) return await LinuxUsbPrinters.issues();
    } catch (_) {}
    return const [];
  }

  /// Tạo hàng in RAW cho máy in USB chưa có hàng in
  /// ([UsbPrinterInfo.setupPort]): Windows hỏi quyền quản trị (UAC), macOS cần
  /// tài khoản quản trị. Trả địa chỉ để chọn, `null` khi không tạo được.
  static Future<String?> setup(String setupPort) async {
    try {
      if (Platform.isWindows) {
        return await WindowsRawPrinters.createRawQueue(setupPort);
      }
      if (Platform.isMacOS) {
        return await MacCupsPrinters.createRawQueue(setupPort);
      }
    } catch (_) {}
    return null;
  }

  /// Lý do lần [setup] gần nhất thất bại (nếu hệ điều hành báo); `null` khi không có.
  static String? get lastSetupError =>
      Platform.isMacOS ? MacCupsPrinters.lastError : null;

  /// Chuỗi định danh IEEE 1284 (`CMD:TSPL2;CLS:PRINTER;...`) của máy in USB [address] — dùng để biết
  /// máy hiểu lệnh nào (tem / hoá đơn). macOS (qua CUPS), Windows (usbprint), Linux (sysfs của `usblp`); nơi khác `null`.
  static Future<String?> deviceId(String address) async {
    try {
      if (Platform.isMacOS && address.startsWith(MacCupsPrinters.prefix)) {
        return await MacCupsPrinters.deviceIdOf(address);
      }
      if (Platform.isWindows && address.startsWith(WindowsUsbPrint.prefix)) {
        return await WindowsUsbPrint.deviceId(address);
      }
      if (Platform.isLinux && address.startsWith(LinuxUsbPrinters.prefix)) {
        return await LinuxUsbPrinters.deviceId(address);
      }
    } catch (_) {}
    return null;
  }

  static PrinterPort? port(String address) {
    if (address.startsWith(LinuxCupsPrinters.prefix) && Platform.isLinux) {
      return LinuxCupsPrinterPort(address);
    }
    if (address.startsWith(LinuxUsbPrinters.prefix) && Platform.isLinux) {
      return LinuxUsbPrinterPort(address);
    }
    if (address.startsWith(WindowsUsbPrint.prefix) && Platform.isWindows) {
      return WindowsUsbPrintPort(address);
    }
    if (address.startsWith(WindowsRawPrinters.prefix) && Platform.isWindows) {
      return WindowsRawPrinterPort(address);
    }
    if (address.startsWith(MacCupsPrinters.prefix) && Platform.isMacOS) {
      return MacCupsPrinterPort(address);
    }
    return null;
  }

  /// Máy in còn cắm / hàng in còn tồn tại.
  static Future<bool> present(String address) async {
    if (address.startsWith(LinuxCupsPrinters.prefix) && Platform.isLinux) {
      return LinuxCupsPrinters.present(address);
    }
    if (address.startsWith(LinuxUsbPrinters.prefix) && Platform.isLinux) {
      return await LinuxUsbPrinters.devicePath(address) != null;
    }
    if (address.startsWith(WindowsUsbPrint.prefix) && Platform.isWindows) {
      return WindowsUsbPrint.present(address);
    }
    if (address.startsWith(WindowsRawPrinters.prefix) && Platform.isWindows) {
      return WindowsRawPrinters.exists(address);
    }
    if (address.startsWith(MacCupsPrinters.prefix) && Platform.isMacOS) {
      return MacCupsPrinters.present(address);
    }
    return false;
  }

  /// Máy in USB [address] đã rút cắm sang cổng khác (địa chỉ đổi): trả địa chỉ mới.
  /// Mới có trên Windows (máy không có số serial); nơi khác / không tìm được → `null`.
  static Future<String?> relocate(
    String address, {
    Set<String> taken = const {},
  }) async {
    try {
      if (Platform.isWindows && address.startsWith(WindowsUsbPrint.prefix)) {
        return await WindowsUsbPrint.findMoved(address, taken: taken);
      }
    } catch (_) {}
    return null;
  }

  /// Tên ngắn để hiện (bỏ tiền tố địa chỉ).
  static String label(String address) {
    if (address.startsWith(LinuxCupsPrinters.prefix)) {
      return address
          .substring(LinuxCupsPrinters.prefix.length)
          .replaceAll('_', ' ');
    }
    if (address.startsWith(WindowsUsbPrint.prefix)) {
      return WindowsUsbPrint.shortName(address);
    }
    if (address.startsWith(WindowsRawPrinters.prefix)) {
      return address.substring(WindowsRawPrinters.prefix.length);
    }
    if (address.startsWith(MacCupsPrinters.prefix)) {
      final q = address.substring(MacCupsPrinters.prefix.length);
      return q.startsWith(MacCupsPrinters.queuePrefix)
          ? q.substring(MacCupsPrinters.queuePrefix.length).replaceAll('_', ' ')
          : q;
    }
    if (address.startsWith(LinuxUsbPrinters.prefix)) {
      return 'USB ${address.substring(LinuxUsbPrinters.prefix.length)}';
    }
    return address;
  }
}
