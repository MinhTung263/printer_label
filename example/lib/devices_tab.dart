import 'package:flutter/material.dart';
import 'connected_device.dart';
import 'main.dart';
import 'package:printer_label/printer_label.dart';

class DevicesTab extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;
  final TextEditingController ipController;
  final FocusNode ipFocusNode;
  final List<ConnectedDevice> connectedDevices;
  final VoidCallback onCheckConnect;
  final VoidCallback onConnect;
  final VoidCallback onDisconnectMain;
  final Function(ConnectedDevice device) onDisconnectDevice;
  final VoidCallback? onCheckPrinterStatus;

  final bool isCheckingStatus;
  final bool isCheckingConnection;
  final bool isPrinting;

  // Bluetooth inline parameters
  final List<BluetoothDeviceModel> btDevices;
  final bool isScanningBt;
  final bool hasScannedBt;
  final Set<String> connectingBtMacs;
  final Function(BluetoothDeviceModel device) onConnectBtDevice;
  final VoidCallback onRefreshBtScan;

  const DevicesTab({
    super.key,
    required this.isConnected,
    this.isConnecting = false,
    required this.ipController,
    required this.ipFocusNode,
    required this.connectedDevices,
    required this.onCheckConnect,
    required this.onConnect,
    required this.onDisconnectMain,
    required this.onDisconnectDevice,
    this.onCheckPrinterStatus,
    this.isCheckingStatus = false,
    this.isCheckingConnection = false,
    this.isPrinting = false,
    required this.btDevices,
    required this.isScanningBt,
    required this.hasScannedBt,
    required this.connectingBtMacs,
    required this.onConnectBtDevice,
    required this.onRefreshBtScan,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildConnectionStatusCard(),
        const SizedBox(height: 16),
        _buildLanConnectionCard(),
        const SizedBox(height: 16),
        _buildConnectedDevicesSection(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildConnectionStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: isConnected
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFFF1F2),
              child: Icon(
                isConnected ? Icons.cloud_done : Icons.cloud_off,
                color: isConnected
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF43F5E),
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Trạng thái LAN chính",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isConnected ? "Kết nối thành công" : "Chưa kết nối LAN",
                    style: TextStyle(
                      color: isConnected
                          ? const Color(0xFF059669)
                          : const Color(0xFFE11D48),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            isCheckingConnection
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh, color: Color(0xFF4F46E5)),
                    tooltip: 'Kiểm tra kết nối',
                    onPressed: isCheckingStatus ? null : onCheckConnect,
                  ),
            if (isConnected && onCheckPrinterStatus != null)
              isCheckingStatus
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D9488)),
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.fact_check_outlined, color: Color(0xFF0D9488)),
                      tooltip: 'Kiểm tra máy in',
                      onPressed: isCheckingConnection ? null : onCheckPrinterStatus,
                    ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanConnectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Kết nối máy in LAN",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipController,
              focusNode: ipFocusNode,
              decoration: InputDecoration(
                labelText: 'Địa chỉ IP máy in',
                hintText: 'VD: $defaultPrinterIp',
                prefixIcon: const Icon(Icons.network_ping),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnecting ? null : onConnect,
                    icon: isConnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.link),
                    label: Text(isConnecting ? "Đang kết nối..." : "Kết nối"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDisconnectMain,
                    icon: const Icon(Icons.link_off),
                    label: const Text("Ngắt"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF43F5E),
                      side: const BorderSide(color: Color(0xFFF43F5E)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedDevicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Danh sách thiết bị kết nối',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Spacer(),
            if (hasScannedBt && isScanningBt)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4F46E5),
                ),
              ),
            if (hasScannedBt)
              IconButton(
                icon: Icon(
                  isScanningBt ? Icons.stop_circle_outlined : Icons.refresh,
                  color: const Color(0xFF4F46E5),
                ),
                onPressed: onRefreshBtScan,
                tooltip: isScanningBt ? 'Dừng quét' : 'Quét thiết bị',
              ),
          ],
        ),
        const SizedBox(height: 8),
        
        // 1. Hiển thị các thiết bị LAN hoặc USB đang kết nối
        ...connectedDevices
            .where((d) => d.type != 'BT')
            .map((d) => _buildDeviceCard(d)),

        // 2. Hiển thị danh sách thiết bị Bluetooth (Quét được + Đã kết nối)
        if (!hasScannedBt)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.bluetooth,
                        size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: onRefreshBtScan,
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text('Quét thiết bị Bluetooth'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (btDevices.isEmpty && !isScanningBt)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.bluetooth_searching,
                        size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    const Text(
                      'Không tìm thấy máy in Bluetooth nào. Thử quét lại.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...btDevices.map((d) {
            final isConnecting = connectingBtMacs.contains(d.mac);
            final connectedDevice = connectedDevices.firstWhere(
              (cd) => cd.type == 'BT' && (cd.id == d.mac || cd.id == 'BT:${d.mac}'),
              orElse: () => const ConnectedDevice(id: '', label: '', type: ''),
            );
            final isAlreadyConnected = connectedDevice.id.isNotEmpty;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: isAlreadyConnected ? const Color(0xFFF0FDF4) : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isAlreadyConnected
                      ? const Color(0xFFDCFCE7)
                      : Colors.grey.shade200,
                  width: 1,
                ),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: isAlreadyConnected
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFEEF2FF),
                  child: Icon(
                    Icons.bluetooth,
                    color: isAlreadyConnected
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF6366F1),
                    size: 20,
                  ),
                ),
                title: Text(
                  d.name.isEmpty ? "Máy in không tên" : d.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isAlreadyConnected ? const Color(0xFF14532D) : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  d.mac,
                  style: TextStyle(
                    fontSize: 11,
                    color: isAlreadyConnected ? const Color(0xFF166534) : const Color(0xFF64748B),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isAlreadyConnected) ...[
                      const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 20),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.link_off, size: 18),
                        color: const Color(0xFFF43F5E),
                        tooltip: 'Ngắt kết nối',
                        onPressed: () => onDisconnectDevice(connectedDevice),
                      ),
                    ] else if (isConnecting) ...[
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ] else ...[
                      ElevatedButton(
                        onPressed: () => onConnectBtDevice(d),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: const Size(60, 30),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Kết nối', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildDeviceCard(ConnectedDevice device) {
    final (IconData icon, Color color) = switch (device.type) {
      'USB' => (Icons.usb, const Color(0xFF0D9488)),
      'LAN' => (Icons.lan, const Color(0xFF3B82F6)),
      'BT' => (Icons.bluetooth, const Color(0xFF6366F1)),
      _ => (Icons.device_unknown, Colors.grey),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          device.label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          device.id,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.link_off, size: 18),
          color: const Color(0xFFF43F5E),
          tooltip: 'Ngắt kết nối',
          onPressed: () => onDisconnectDevice(device),
        ),
      ),
    );
  }
}
