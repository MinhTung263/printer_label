class ConnectedDevice {
  final String id; // USB path | IP | MAC
  final String label; // display name
  final String type; // 'USB' | 'LAN' | 'BT'
  const ConnectedDevice({
    required this.id,
    required this.label,
    required this.type,
  });
}
