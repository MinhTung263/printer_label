class BluetoothDeviceModel {
  final String name;
  final String mac;

  const BluetoothDeviceModel({required this.name, required this.mac});

  factory BluetoothDeviceModel.fromMap(Map<String, dynamic> map) {
    return BluetoothDeviceModel(
      name: map['name'] as String? ?? 'Unknown',
      mac: map['mac'] as String,
    );
  }
}
