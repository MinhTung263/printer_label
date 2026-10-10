class ConnectedDevice {
  final String id; // USB path | IP | MAC
  final String label; // display name
  final String type; // 'USB' | 'LAN' | 'BT'

  /// MAC của máy in LAN — dùng để tìm lại máy in khi nó đổi IP (DHCP).
  final String? mac;
  const ConnectedDevice({
    required this.id,
    required this.label,
    required this.type,
    this.mac,
  });
}
