import 'dart:io';

import '../printer_port.dart';
import 'linux_usb_printers.dart';
import 'usb_printer_info.dart';
import 'windows_raw_printers.dart';

/// Máy in cắm trực tiếp vào máy tính, theo hệ điều hành:
/// - Linux: `/dev/usb/lpN` (địa chỉ `usb:<vid>:<pid>:<serial>`);
/// - Windows: hàng in RAW (địa chỉ `queue:<tên hàng in>`).
abstract final class UsbPrinters {
  static bool get supported => Platform.isLinux || Platform.isWindows;

  /// Địa chỉ [address] là máy in USB / hàng in (không phải LAN).
  static bool isLocal(String address) =>
      address.startsWith(LinuxUsbPrinters.prefix) ||
      address.startsWith(WindowsRawPrinters.prefix);

  static Future<List<UsbPrinterInfo>> list() async {
    try {
      if (Platform.isLinux) return await LinuxUsbPrinters.list();
      if (Platform.isWindows) return await WindowsRawPrinters.list();
    } catch (_) {}
    return const [];
  }

  static PrinterPort? port(String address) {
    if (address.startsWith(LinuxUsbPrinters.prefix) && Platform.isLinux) {
      return LinuxUsbPrinterPort(address);
    }
    if (address.startsWith(WindowsRawPrinters.prefix) && Platform.isWindows) {
      return WindowsRawPrinterPort(address);
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
    return false;
  }

  /// Tên ngắn để hiện (bỏ tiền tố địa chỉ).
  static String label(String address) {
    if (address.startsWith(WindowsRawPrinters.prefix)) {
      return address.substring(WindowsRawPrinters.prefix.length);
    }
    if (address.startsWith(LinuxUsbPrinters.prefix)) {
      return 'USB ${address.substring(LinuxUsbPrinters.prefix.length)}';
    }
    return address;
  }
}
