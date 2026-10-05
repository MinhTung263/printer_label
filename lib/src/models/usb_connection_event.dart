class UsbConnectionEvent {
  final String deviceId;
  final bool connected;

  /// Product name the printer reports over USB (e.g. "Printer-80"). `null`
  /// when unknown — always the case for detach events.
  final String? name;

  const UsbConnectionEvent({
    required this.deviceId,
    required this.connected,
    this.name,
  });
}
