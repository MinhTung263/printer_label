class LanDeviceModel {
  /// IP address of the LAN printer (e.g. "192.168.1.199")
  final String ip;

  /// Display name of the printer (model name e.g. "Xprinter XP-420B" or custom alias)
  final String name;

  /// Detected manufacturer/brand (e.g. "Xprinter", "Epson", "TSC", "Rongta", "Gprinter")
  final String? vendor;

  /// RAW TCP port for printer communication (defaults to 9100)
  final int port;

  /// Optional MAC address (if discovered via UDP / network scan)
  final String? mac;

  /// True if the name was customized by the user
  final bool isCustomName;

  const LanDeviceModel({
    required this.ip,
    required this.name,
    this.vendor,
    this.port = 9100,
    this.mac,
    this.isCustomName = false,
  });

  /// Factory helper to create a model with fallback name if name is empty
  factory LanDeviceModel.fromIp(
    String ip, {
    String? name,
    String? vendor,
    int port = 9100,
    String? mac,
    bool isCustomName = false,
  }) {
    final cleanName = name?.trim();
    final displayName = (cleanName != null && cleanName.isNotEmpty)
        ? cleanName
        : 'Máy in LAN ${ip.split('.').last}';

    return LanDeviceModel(
      ip: ip,
      name: displayName,
      vendor: vendor,
      port: port,
      mac: mac,
      isCustomName: isCustomName,
    );
  }

  factory LanDeviceModel.fromMap(Map<String, dynamic> map) {
    return LanDeviceModel(
      ip: map['ip'] as String? ?? '',
      name: map['name'] as String? ?? 'Máy in LAN',
      vendor: map['vendor'] as String?,
      port: map['port'] as int? ?? 9100,
      mac: map['mac'] as String?,
      isCustomName: map['isCustomName'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ip': ip,
      'name': name,
      'vendor': vendor,
      'port': port,
      'mac': mac,
      'isCustomName': isCustomName,
    };
  }

  LanDeviceModel copyWith({
    String? ip,
    String? name,
    String? vendor,
    int? port,
    String? mac,
    bool? isCustomName,
  }) {
    return LanDeviceModel(
      ip: ip ?? this.ip,
      name: name ?? this.name,
      vendor: vendor ?? this.vendor,
      port: port ?? this.port,
      mac: mac ?? this.mac,
      isCustomName: isCustomName ?? this.isCustomName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanDeviceModel &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port;

  @override
  int get hashCode => ip.hashCode ^ port.hashCode;

  @override
  String toString() =>
      'LanDeviceModel(ip: $ip, name: $name, vendor: $vendor, port: $port, mac: $mac)';
}
