import 'dart:io';

import '../printer_port.dart';
import 'linux_usb_printers.dart';
import 'mac_cups_printers.dart';
import 'usb_printer_info.dart';
import 'windows_raw_printers.dart';

/// Máy in cắm trực tiếp vào máy tính, theo hệ điều hành:
/// - Linux: `/dev/usb/lpN` (địa chỉ `usb:<vid>:<pid>:<serial>`);
/// - Windows: hàng in RAW (địa chỉ `queue:<tên hàng in>`);
/// - macOS: hàng in RAW của CUPS (địa chỉ `cups:<tên hàng in>`).
abstract final class UsbPrinters {
  static bool get supported =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// Địa chỉ [address] là máy in USB / hàng in (không phải LAN).
  static bool isLocal(String address) =>
      address.startsWith(LinuxUsbPrinters.prefix) ||
      address.startsWith(WindowsRawPrinters.prefix) ||
      address.startsWith(MacCupsPrinters.prefix);

  static Future<List<UsbPrinterInfo>> list() async {
    try {
      if (Platform.isLinux) return await LinuxUsbPrinters.list();
      if (Platform.isWindows) return await WindowsRawPrinters.list();
      if (Platform.isMacOS) return await MacCupsPrinters.list();
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

  static PrinterPort? port(String address) {
    if (address.startsWith(LinuxUsbPrinters.prefix) && Platform.isLinux) {
      return LinuxUsbPrinterPort(address);
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
    if (address.startsWith(LinuxUsbPrinters.prefix) && Platform.isLinux) {
      return await LinuxUsbPrinters.devicePath(address) != null;
    }
    if (address.startsWith(WindowsRawPrinters.prefix) && Platform.isWindows) {
      return WindowsRawPrinters.exists(address);
    }
    if (address.startsWith(MacCupsPrinters.prefix) && Platform.isMacOS) {
      return MacCupsPrinters.present(address);
    }
    return false;
  }

  /// Tên ngắn để hiện (bỏ tiền tố địa chỉ).
  static String label(String address) {
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
