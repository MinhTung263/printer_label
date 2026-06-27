class BluetoothDeviceModel {
  final String name;

  /// Platform-specific device identifier:
  /// - iOS: CBPeripheral UUID string (e.g. "12345678-ABCD-1234-EFAB-123456789012")
  /// - Android: MAC address (e.g. "AA:BB:CC:DD:EE:FF")
  final String identifier;

  /// Backward-compat alias for [identifier]
  String get mac => identifier;

  const BluetoothDeviceModel({required this.name, required this.identifier});

  factory BluetoothDeviceModel.fromMap(Map<String, dynamic> map) {
    return BluetoothDeviceModel(
      name: map['name'] as String? ?? 'Unknown',
      // iOS emits 'identifier', Android emits 'mac' — support both
      identifier: (map['identifier'] ?? map['mac']) as String? ?? '',
    );
  }

  @override
  String toString() => 'BluetoothDeviceModel(name: $name, identifier: $identifier)';
}
