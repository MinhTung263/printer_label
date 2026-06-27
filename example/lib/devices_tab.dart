import 'package:flutter/material.dart';
import 'connected_device.dart';

enum PrintAction { lan, all, esc }

class DevicesTab extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;
  final TextEditingController ipController;
  final FocusNode ipFocusNode;
  final List<ConnectedDevice> connectedDevices;
  final VoidCallback onCheckConnect;
  final VoidCallback onConnect;
  final VoidCallback onDisconnectMain;
  final VoidCallback onAddBluetooth;
  final VoidCallback onPrintAllLan;
  final VoidCallback onPrintAll;
  final VoidCallback onPrintAllEsc;
  final Function(ConnectedDevice device) onDisconnectDevice;
  final Function(ConnectedDevice device) onPrintDeviceLabel;
  final Function(ConnectedDevice device) onPrintDeviceEsc;
  final VoidCallback? onCheckPrinterStatus;

  final bool isCheckingStatus;
  final bool isCheckingConnection;
  final bool isPrinting;
  final VoidCallback? onShowSavedBt;


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
    required this.onAddBluetooth,
    required this.onPrintAllLan,
    required this.onPrintAll,
    required this.onPrintAllEsc,
    required this.onDisconnectDevice,
    required this.onPrintDeviceLabel,
    required this.onPrintDeviceEsc,
    this.onCheckPrinterStatus,

    this.isCheckingStatus = false,
    this.isCheckingConnection = false,
    this.isPrinting = false,
    this.onShowSavedBt,
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
                hintText: 'VD: 192.168.1.56',
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
            if (onShowSavedBt != null)
              IconButton(
                onPressed: onShowSavedBt,
                icon: const Icon(Icons.bluetooth_connected,
                    color: Colors.indigo),
                tooltip: 'Chọn máy in BT đã lưu để kết nối lại',
              ),
            IconButton(
              onPressed: onAddBluetooth,
              icon: const Icon(Icons.bluetooth_searching,
                  color: Color(0xFF4F46E5)),
              tooltip: 'Thêm Bluetooth',
            ),
            PopupMenuButton<PrintAction>(
              icon: const Icon(Icons.print, color: Color(0xFF4F46E5)),
              tooltip: 'In hàng loạt',
              enabled: connectedDevices.isNotEmpty,
              onSelected: (action) {
                switch (action) {
                  case PrintAction.lan:
                    onPrintAllLan();
                  case PrintAction.all:
                    onPrintAll();
                  case PrintAction.esc:
                    onPrintAllEsc();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: PrintAction.lan,
                  enabled: connectedDevices.any((d) => d.type == 'LAN'),
                  child: const ListTile(
                    dense: true,
                    leading: Icon(Icons.lan),
                    title: Text('In tất cả máy LAN'),
                  ),
                ),
                const PopupMenuItem(
                  value: PrintAction.all,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.print_outlined),
                    title: Text('In tất cả thiết bị'),
                  ),
                ),
                const PopupMenuItem(
                  value: PrintAction.esc,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.receipt_long),
                    title: Text('In ESC trên tất cả'),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (connectedDevices.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.print_disabled,
                        size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    const Text(
                      'Chưa có thiết bị nào kết nối thành công',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: connectedDevices.length,
            itemBuilder: (_, i) => _buildDeviceCard(connectedDevices[i]),
          ),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.print, color: Color(0xFF4F46E5), size: 20),
              tooltip: 'Kiểm thử in',
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'label', child: Text('In nhãn (Label)')),
                PopupMenuItem(value: 'esc', child: Text('In hoá đơn (ESC)')),
              ],
              onSelected: (action) {
                switch (action) {
                  case 'label':
                    onPrintDeviceLabel(device);
                  case 'esc':
                    onPrintDeviceEsc(device);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.link_off, size: 18),
              color: const Color(0xFFF43F5E),
              tooltip: 'Ngắt kết nối',
              onPressed: () => onDisconnectDevice(device),
            ),
          ],
        ),
      ),
    );
  }
}


