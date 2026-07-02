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
  final Function(ConnectedDevice device)? onCheckPrinterStatus;

  final bool isCheckingStatus;
  final bool isCheckingConnection;
  final bool isPrinting;

  final bool hasBuiltInPrinter;

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
    this.hasBuiltInPrinter = false,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        // ─── Section 1: Thiết bị đang kết nối ───────────────────────────
        _buildSectionHeader("THIẾT BỊ ĐANG KẾT NỐI", Icons.offline_share),
        const SizedBox(height: 8),
        _buildConnectedDevicesList(context),
        const SizedBox(height: 24),

        // ─── Section 2: Kết nối LAN ──────────────────────────────────────
        _buildSectionHeader("KẾT NỐI MÁY IN QUA MẠNG LAN / WI-FI", Icons.settings_ethernet),
        const SizedBox(height: 8),
        _buildLanConnectionCard(context),
        const SizedBox(height: 24),

        // ─── Section 3: Quét Bluetooth ───────────────────────────────────
        _buildSectionHeader("MÁY IN BLUETOOTH XUNG QUANH", Icons.bluetooth_searching),
        const SizedBox(height: 8),
        _buildBluetoothScanCard(context),
        const SizedBox(height: 24),

        // ─── Section 4: Hướng dẫn USB ────────────────────────────────────
        _buildSectionHeader("KẾT NỐI CÁP USB (CHỈ ANDROID)", Icons.usb),
        const SizedBox(height: 8),
        _buildUsbGuideCard(),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedDevicesList(BuildContext context) {
    final hasAny = connectedDevices.isNotEmpty || hasBuiltInPrinter;

    if (!hasAny) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Column(
            children: [
              Icon(Icons.print_disabled_outlined, size: 44, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text(
                "Chưa có máy in nào được kết nối",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Vui lòng kết nối máy in qua LAN hoặc Bluetooth bên dưới.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (hasBuiltInPrinter)
          _buildBuiltInPrinterCard(),
        ...connectedDevices.map((device) {
        final (IconData icon, Color color) = switch (device.type) {
          'USB' => (Icons.usb, const Color(0xFF0D9488)),
          'LAN' => (Icons.lan, const Color(0xFF3B82F6)),
          'BT' => (Icons.bluetooth, const Color(0xFF6366F1)),
          _ => (Icons.device_unknown, Colors.grey),
        };

        final isMainLan = device.type == 'LAN' && isConnected;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withOpacity(0.15), width: 1.2),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withOpacity(0.1),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF16A34A),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  "Đã kết nối",
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isMainLan) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                "Chính",
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1D4ED8),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        device.id,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onCheckPrinterStatus != null) ...[
                      isCheckingStatus
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D9488)),
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.info_outline, size: 20),
                              color: const Color(0xFF0D9488),
                              tooltip: 'Kiểm tra trạng thái máy in',
                              onPressed: isCheckingConnection ? null : () => onCheckPrinterStatus!(device),
                            ),
                    ],
                    IconButton(
                      icon: const Icon(Icons.link_off, size: 20),
                      color: const Color(0xFFF43F5E),
                      tooltip: 'Ngắt kết nối',
                      onPressed: () => onDisconnectDevice(device),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
      ],
    );
  }

  Widget _buildBuiltInPrinterCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFF22C55E).withOpacity(0.25), width: 1.5),
      ),
      color: const Color(0xFFF0FDF4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF22C55E).withOpacity(0.15),
              child: const Icon(Icons.print, color: Color(0xFF16A34A), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Máy in tích hợp sẵn',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF14532D),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Được phát hiện tự động qua phần cứng thiết bị',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF16A34A),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Sẵn sàng',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanConnectionCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ipController,
              focusNode: ipFocusNode,
              decoration: InputDecoration(
                labelText: 'Địa chỉ IP máy in',
                hintText: 'VD: $defaultPrinterIp',
                prefixIcon: const Icon(Icons.network_ping, size: 20, color: Color(0xFF64748B)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                        : const Icon(Icons.link, size: 18),
                    label: Text(isConnecting ? "Đang kết nối..." : "Kết nối mạng LAN"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (isConnected) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: onDisconnectMain,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text("Ngắt"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF43F5E),
                      side: const BorderSide(color: Color(0xFFF43F5E)),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothScanCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const Text(
                  "Tìm kiếm thiết bị",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                  ),
                ),
                const Spacer(),
                if (isScanningBt)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onRefreshBtScan,
                  icon: Icon(
                    isScanningBt ? Icons.stop_circle_outlined : Icons.search,
                    size: 18,
                  ),
                  label: Text(isScanningBt ? "Dừng quét" : "Quét Bluetooth"),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4F46E5),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

          if (!hasScannedBt)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.bluetooth, size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    const Text(
                      "Nhấn 'Quét Bluetooth' để tìm máy in gần bạn",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            )
          else if (btDevices.isEmpty && !isScanningBt)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.bluetooth_disabled_outlined, size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    const Text(
                      "Không tìm thấy máy in Bluetooth nào xung quanh",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: btDevices.length,
              separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final d = btDevices[index];
                final isConnecting = connectingBtMacs.contains(d.mac);
                final connectedDevice = connectedDevices.firstWhere(
                  (cd) => cd.type == 'BT' && (cd.id == d.mac || cd.id == 'BT:${d.mac}'),
                  orElse: () => const ConnectedDevice(id: '', label: '', type: ''),
                );
                final isAlreadyConnected = connectedDevice.id.isNotEmpty;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: isAlreadyConnected
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF1F5F9),
                    child: Icon(
                      Icons.bluetooth,
                      color: isAlreadyConnected
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF64748B),
                      size: 18,
                    ),
                  ),
                  title: Text(
                    d.name.isEmpty ? "Máy in không tên" : d.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isAlreadyConnected ? const Color(0xFF14532D) : const Color(0xFF1E293B),
                    ),
                  ),
                  subtitle: Text(
                    d.mac,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isAlreadyConnected) ...[
                        const Text(
                          "Đã kết nối",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.link_off, size: 18),
                          color: const Color(0xFFF43F5E),
                          onPressed: () => onDisconnectDevice(connectedDevice),
                        ),
                      ] else if (isConnecting) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
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
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size(60, 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Kết nối', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildUsbGuideCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      color: Colors.white,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFF0FDF4),
              child: Icon(Icons.info_outline, color: Color(0xFF16A34A), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Tự động nhận diện thiết bị",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF334155),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Hãy cắm máy in USB qua cáp OTG. Ứng dụng sẽ tự động phát hiện, xin quyền và kết nối ngay lập tức.",
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
