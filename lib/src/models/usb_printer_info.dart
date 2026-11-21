/// A USB printer that is plugged in (Android only).
class UsbPrinterInfo {
  const UsbPrinterInfo({
    required this.deviceId,
    required this.name,
    this.hasPermission = false,
    this.ieee1284,
  });

  factory UsbPrinterInfo.fromMap(Map<dynamic, dynamic> map) => UsbPrinterInfo(
    deviceId: map['device_id'] as String? ?? '',
    name: map['name'] as String? ?? '',
    hasPermission: map['has_permission'] as bool? ?? false,
    ieee1284: map['ieee1284'] as String?,
  );

  /// `USB:v{vid}_p{pid}` (+ `_s{serial}` once permitted): Android hides the serial
  /// number until permission is granted.
  final String deviceId;

  /// Product name reported by the printer, e.g. "Printer-80".
  final String name;

  /// The app already has USB permission for this printer.
  final bool hasPermission;

  /// IEEE 1284 Device ID the printer reports (`MFG:..;CMD:TSPL;MDL:..;`), only readable
  /// with permission. `CMD:` lists the command languages: see
  /// `PrinterLanguageProbe.fromIeee1284`.
  final String? ieee1284;
}
