enum PrinterConnectionType {
  USB('USB'),
  LAN('LAN'),
  BT('Bluetooth');

  const PrinterConnectionType(this.value);
  final String value;
}
