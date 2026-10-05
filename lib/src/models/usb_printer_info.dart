/// A USB printer that is plugged in but not yet permitted (Android only).
class UsbPrinterInfo {
  const UsbPrinterInfo({required this.deviceId, required this.name});

  factory UsbPrinterInfo.fromMap(Map<dynamic, dynamic> map) => UsbPrinterInfo(
        deviceId: map['device_id'] as String? ?? '',
        name: map['name'] as String? ?? '',
      );

  /// Id without serial (`USB:v{vid}_p{pid}`): Android hides the serial
  /// number until permission is granted.
  final String deviceId;

  /// Product name reported by the printer, e.g. "Printer-80".
  final String name;
}
