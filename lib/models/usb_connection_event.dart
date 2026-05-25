class UsbConnectionEvent {
  final String deviceId;
  final bool connected;
  const UsbConnectionEvent({required this.deviceId, required this.connected});
}
