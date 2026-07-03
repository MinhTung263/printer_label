// ignore_for_file: constant_identifier_names

enum PrinterConnectionType {
  usb('USB'),
  lan('LAN'),
  bt('Bluetooth');

  const PrinterConnectionType(this.value);
  final String value;

  @Deprecated('Use usb instead')
  static const PrinterConnectionType USB = usb;
  @Deprecated('Use lan instead')
  static const PrinterConnectionType LAN = lan;
  @Deprecated('Use bt instead')
  static const PrinterConnectionType BT = bt;
}
