/// In ESC/POS trên máy tính (Windows / Linux / macOS) bằng Dart, KHÔNG cần driver:
/// ảnh hoá đơn → raster `GS v 0` (khớp từng byte bản native Android), gửi qua
/// TCP 9100 (máy in LAN), `/dev/usb/lp*` (Linux) hoặc hàng in RAW (Windows,
/// CUPS trên macOS).
///
/// Thư viện riêng (không nằm trong `printer_label.dart`) để app di động không
/// kéo theo `win32`.
library;

export 'src/desktop/arp_table.dart';
export 'src/desktop/dirty_store.dart';
export 'src/desktop/escpos_commands.dart';
export 'src/desktop/escpos_printer.dart';
export 'src/desktop/escpos_raster.dart';
export 'src/desktop/lan_printer_scanner.dart';
export 'src/desktop/paper_status.dart';
export 'src/desktop/port_queue.dart';
export 'src/desktop/printer_language_probe.dart';
export 'src/desktop/printer_beep.dart';
export 'src/desktop/printer_port.dart';
export 'src/desktop/tcp_printer_port.dart';
export 'src/desktop/xprinter_udp.dart';
export 'src/desktop/tspl_commands.dart';
export 'src/desktop/tspl_label_spec.dart';
export 'src/desktop/tspl_printer.dart';
export 'src/desktop/tspl_raster.dart';
export 'src/desktop/usb/ieee1284.dart';
export 'src/desktop/usb/linux_cups_printers.dart';
export 'src/desktop/usb/mac_cups_printers.dart';
export 'src/desktop/usb/usb_printer_info.dart';
export 'src/desktop/usb/usb_printers.dart';
export 'src/desktop/usb/windows_raw_printers.dart';
export 'src/desktop/usb/windows_usb_print.dart';
