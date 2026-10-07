import 'package:example/widgets/custom_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';
import 'connected_device.dart';
import 'network_config_screen.dart';

class DevicesTab extends StatefulWidget {
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
  final bool isBuiltInPrinterConnected;
  final VoidCallback? onConnectBuiltIn;
  final VoidCallback? onDisconnectBuiltIn;

  // LAN inline parameters
  final List<LanDeviceModel> lanDevices;
  final bool isScanningLan;
  final bool hasScannedLan;
  final VoidCallback onRefreshLanScan;
  final Function(LanDeviceModel device) onConnectLanDevice;
  final Function(LanDeviceModel device)? onIdentifyLanDevice;
  final Function(LanDeviceModel device)? onPrintTestSlip;

  /// Gọi khi đóng màn hình "Đổi IP" — để cập nhật IP các máy in đã kết nối.
  final VoidCallback? onNetworkConfigClosed;

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
    this.isBuiltInPrinterConnected = false,
    this.onConnectBuiltIn,
    this.onDisconnectBuiltIn,
    required this.lanDevices,
    required this.isScanningLan,
    required this.hasScannedLan,
    required this.onRefreshLanScan,
    required this.onConnectLanDevice,
    this.onIdentifyLanDevice,
    this.onPrintTestSlip,
    this.onNetworkConfigClosed,
    required this.btDevices,
    required this.isScanningBt,
    required this.hasScannedBt,
    required this.connectingBtMacs,
    required this.onConnectBtDevice,
    required this.onRefreshBtScan,
  });

  @override
  State<DevicesTab> createState() => _DevicesTabState();
}

enum DeviceTypeTab { lan, bluetooth, usb }

class _DevicesTabState extends State<DevicesTab> with TickerProviderStateMixin {
  DeviceTypeTab _selectedTab = DeviceTypeTab.lan;
  bool _showManualIp = false;
  late AnimationController _pulseController;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedTab = DeviceTypeTab.values[_tabController.index];
        });
      }
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Top Hero: Active Connected Printer Banner ─────────────────────
          _buildActiveConnectionHero(),
          const SizedBox(height: 16),

          // ─── 3 Category Segmented Control ──────────────────────────────────
          _buildSegmentedTabSelector(),
          const SizedBox(height: 16),

          // ─── Content View corresponding to Selected Tab ────────────────────
          IndexedStack(
            index: DeviceTypeTab.values.indexOf(_selectedTab),
            children: [
              _buildLanTabContent(),
              _buildBluetoothTabContent(),
              _buildUsbTabContent(),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── Top Hero: Active Connection (Compact) ─────────────────────────────────
  Widget _buildActiveConnectionHero() {
    final hasConnected =
        widget.connectedDevices.isNotEmpty || widget.isBuiltInPrinterConnected;

    if (!hasConnected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Row(
          children: [
            Icon(Icons.link_off, size: 16, color: Color(0xFF94A3B8)),
            SizedBox(width: 8),
            Text(
              "Chưa kết nối máy in",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            Spacer(),
            Text(
              "Chọn thiết bị bên dưới",
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.hasBuiltInPrinter && widget.isBuiltInPrinterConnected)
          _buildActiveDeviceCard(
            title: "Máy in tích hợp POS",
            subtitle: "Nội bộ",
            protocol: "BUILT-IN",
            icon: Icons.print,
            color: const Color(0xFF16A34A),
            onDisconnect: widget.onDisconnectBuiltIn,
          ),
        ...widget.connectedDevices.map((device) {
          final (IconData icon, Color color, String protocol) =
              switch (device.type) {
            'USB' => (Icons.usb, const Color(0xFF0D9488), 'USB'),
            'LAN' => (Icons.lan, const Color(0xFF4F46E5), 'LAN'),
            'BT' => (Icons.bluetooth, const Color(0xFF6366F1), 'BT'),
            _ => (Icons.device_unknown, Colors.grey, 'GEN'),
          };

          var cleanTitle = device.label;
          if (cleanTitle.contains('(')) {
            cleanTitle = cleanTitle.split('(').first.trim();
          }
          if (cleanTitle.startsWith('LAN: ')) {
            cleanTitle = cleanTitle.substring(5).trim();
          }

          final address =
              device.id.replaceAll('LAN:', '').replaceAll('BT:', '');

          return _buildActiveDeviceCard(
            title: cleanTitle,
            subtitle: address,
            protocol: protocol,
            icon: icon,
            color: color,
            isCheckingStatus: widget.isCheckingStatus,
            onCheckStatus: widget.onCheckPrinterStatus != null
                ? () => widget.onCheckPrinterStatus!(device)
                : null,
            onDisconnect: () => widget.onDisconnectDevice(device),
          );
        }),
      ],
    );
  }

  Widget _buildActiveDeviceCard({
    required String title,
    required String subtitle,
    required String protocol,
    required IconData icon,
    required Color color,
    bool isCheckingStatus = false,
    VoidCallback? onCheckStatus,
    VoidCallback? onDisconnect,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF86EFAC),
          width: 1.1,
        ),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF16A34A),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF16A34A).withValues(
                          alpha: 0.3 + 0.3 * _pulseController.value),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF16A34A), size: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        protocol,
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF64748B),
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onCheckStatus != null)
            IconButton(
              icon: isCheckingStatus
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
                      ),
                    )
                  : const Icon(Icons.info_outline, size: 16),
              color: const Color(0xFF4F46E5),
              tooltip: 'Kiểm tra máy',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              onPressed: onCheckStatus,
            ),
          const SizedBox(width: 6),
          if (onDisconnect != null)
            IconButton(
              icon: const Icon(Icons.link_off, size: 16),
              color: const Color(0xFFF43F5E),
              tooltip: 'Ngắt kết nối',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              onPressed: onDisconnect,
            ),
        ],
      ),
    );
  }

  // ─── 3 Segmented Tab Switcher (Synchronized with FunctionsTab) ─────────────
  Widget _buildSegmentedTabSelector() {
    return CustomTabBar(
      controller: _tabController,
      tabs: [
        CustomTab(
          icon: Icons.settings_ethernet,
          label: widget.lanDevices.isNotEmpty
              ? "LAN (${widget.lanDevices.length})"
              : "LAN",
        ),
        CustomTab(
          icon: Icons.bluetooth,
          label: widget.btDevices.isNotEmpty
              ? "Bluetooth (${widget.btDevices.length})"
              : "Bluetooth",
        ),
        const CustomTab(
          icon: Icons.usb,
          label: "Cáp USB",
        ),
      ],
    );
  }

  // ─── TAB 1: MẠNG LAN CONTENT ───────────────────────────────────────────────
  Widget _buildLanTabContent() {
    return Column(
      key: const ValueKey("tab_lan"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Toolbar: Scan Radar & Network Config
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (widget.isScanningLan)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
                    ),
                  )
                else
                  const Icon(Icons.radar, size: 16, color: Color(0xFF4F46E5)),
                const SizedBox(width: 6),
                Text(
                  widget.isScanningLan
                      ? "Đang quét mạng..."
                      : "Máy in tìm thấy (${widget.lanDevices.length})",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: widget.onRefreshLanScan,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              const Color(0xFF4F46E5).withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.refresh, size: 16, color: Color(0xFF4F46E5)),
                        SizedBox(width: 4),
                        Text(
                          "Quét lại",
                          style: TextStyle(
                            color: Color(0xFF4F46E5),
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NetworkConfigScreen()),
                    ).then((_) => widget.onNetworkConfigClosed?.call());
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.tune, size: 16, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          "Đổi IP",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Discovered LAN Printer Cards (1-Tap to Connect)
        if (widget.lanDevices.isEmpty &&
            widget.hasScannedLan &&
            !widget.isScanningLan)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.wifi_off, size: 36, color: Color(0xFFCBD5E1)),
                  SizedBox(height: 8),
                  Text(
                    "Không tìm thấy máy in LAN nào",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Hãy kiểm tra máy in đã bật và cắm dây LAN cùng Router WiFi",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.lanDevices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final device = widget.lanDevices[index];
              final connectedDevice = widget.connectedDevices.firstWhere(
                (cd) =>
                    cd.type == 'LAN' &&
                    (cd.id == device.ip ||
                        cd.id == 'LAN:${device.ip}' ||
                        cd.id == 'LAN:${device.ip}:${device.port}'),
                orElse: () =>
                    const ConnectedDevice(id: '', label: '', type: ''),
              );
              final isAlreadyConnected = connectedDevice.id.isNotEmpty;
              final isDeviceConnecting =
                  widget.isConnecting && widget.ipController.text == device.ip;

              return InkWell(
                onTap: isAlreadyConnected
                    ? null
                    : () => widget.onConnectLanDevice(device),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isAlreadyConnected
                        ? const Color(0xFFF0FDF4)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isAlreadyConnected
                          ? const Color(0xFF86EFAC)
                          : Colors.grey.shade200,
                      width: isAlreadyConnected ? 1.4 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isAlreadyConnected
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFF4F46E5)
                                      .withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.print,
                              color: isAlreadyConnected
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF4F46E5),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (device.vendor != null &&
                                          device.vendor!.isNotEmpty)
                                      ? device.vendor!
                                      : device.name,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: isAlreadyConnected
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFF0F172A),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  children: [
                                    Text(
                                      '${device.ip}${device.port != 9100 ? ":${device.port}" : ""}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF64748B),
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (device.mac != null &&
                                        device.mac!.isNotEmpty)
                                      Text(
                                        'MAC: ${device.mac}',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: Colors.grey.shade500,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isAlreadyConnected) ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  "Đang dùng",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.link_off, size: 16),
                                  color: const Color(0xFFF43F5E),
                                  tooltip: 'Ngắt kết nối',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => widget
                                      .onDisconnectDevice(connectedDevice),
                                ),
                              ],
                            ),
                          ] else if (isDeviceConnecting) ...[
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF4F46E5)),
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F46E5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "Kết nối",
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (widget.onIdentifyLanDevice != null)
                            TextButton.icon(
                              onPressed: () =>
                                  widget.onIdentifyLanDevice!(device),
                              icon: const Icon(
                                  Icons.notifications_active_outlined,
                                  size: 16),
                              label: const Text("Nhận diện máy",
                                  style: TextStyle(fontSize: 12.5)),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF4F46E5),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          if (widget.onPrintTestSlip != null)
                            TextButton.icon(
                              onPressed: () => widget.onPrintTestSlip!(device),
                              icon: const Icon(Icons.receipt_long_outlined,
                                  size: 16),
                              label: const Text("In test",
                                  style: TextStyle(fontSize: 12.5)),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF0D9488),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 14),

        // Collapsible Manual IP Input
        _buildManualIpSection(),
      ],
    );
  }

  Widget _buildManualIpSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _showManualIp = !_showManualIp;
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.edit_note,
                      size: 18, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 8),
                  const Text(
                    "Nhập địa chỉ IP thủ công",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showManualIp
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
          if (_showManualIp) ...[
            Container(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      child: TextField(
                        controller: widget.ipController,
                        focusNode: widget.ipFocusNode,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13.5,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          hintText: '192.168.1.199',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12.5,
                            fontFamily: 'monospace',
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: widget.isConnecting ? null : widget.onConnect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    child: widget.isConnecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            "Kết nối",
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── TAB 2: BLUETOOTH CONTENT ──────────────────────────────────────────────
  Widget _buildBluetoothTabContent() {
    return Column(
      key: const ValueKey("tab_bt"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bluetooth Scan Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.bluetooth_searching,
                  size: 16, color: Color(0xFF4F46E5)),
              const SizedBox(width: 8),
              Text(
                widget.isScanningBt
                    ? "Đang quét Bluetooth..."
                    : "Máy in Bluetooth (${widget.btDevices.length})",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: widget.onRefreshBtScan,
                icon: Icon(
                  widget.isScanningBt
                      ? Icons.stop_circle_outlined
                      : Icons.radar,
                  size: 16,
                ),
                label: Text(widget.isScanningBt ? "Dừng" : "Quét BT"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(60, 30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Discovered Bluetooth Devices
        if (!widget.hasScannedBt)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.bluetooth, size: 36, color: Color(0xFFCBD5E1)),
                  SizedBox(height: 8),
                  Text(
                    "Nhấn 'Quét BT' để tìm máy in gần bạn",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (widget.btDevices.isEmpty && !widget.isScanningBt)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.bluetooth_disabled_outlined,
                      size: 36, color: Color(0xFFCBD5E1)),
                  SizedBox(height: 8),
                  Text(
                    "Không tìm thấy máy in Bluetooth nào xung quanh",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.btDevices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final d = widget.btDevices[index];
              final isConnecting = widget.connectingBtMacs.contains(d.mac);
              final connectedDevice = widget.connectedDevices.firstWhere(
                (cd) =>
                    cd.type == 'BT' &&
                    (cd.id == d.mac || cd.id == 'BT:${d.mac}'),
                orElse: () =>
                    const ConnectedDevice(id: '', label: '', type: ''),
              );
              final isAlreadyConnected = connectedDevice.id.isNotEmpty;

              return InkWell(
                onTap: isAlreadyConnected
                    ? null
                    : () => widget.onConnectBtDevice(d),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isAlreadyConnected
                        ? const Color(0xFFF0FDF4)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isAlreadyConnected
                          ? const Color(0xFF86EFAC)
                          : Colors.grey.shade200,
                      width: isAlreadyConnected ? 1.4 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isAlreadyConnected
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFEEF2F6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.bluetooth,
                          color: isAlreadyConnected
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF4F46E5),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name.isEmpty ? "Máy in không tên" : d.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isAlreadyConnected
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              d.mac,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isAlreadyConnected) ...[
                            const Text(
                              "Đang dùng",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.link_off, size: 20),
                              color: const Color(0xFFF43F5E),
                              onPressed: () =>
                                  widget.onDisconnectDevice(connectedDevice),
                            ),
                          ] else if (isConnecting) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF4F46E5)),
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F46E5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Kết nối',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
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
            },
          ),
      ],
    );
  }

  // ─── TAB 3: CÁP USB CONTENT ────────────────────────────────────────────────
  Widget _buildUsbTabContent() {
    return Container(
      key: const ValueKey("tab_usb"),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Color(0xFFF0FDF4),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.usb, color: Color(0xFF16A34A), size: 26),
          ),
          const SizedBox(height: 12),
          const Text(
            "Tự động nhận diện thiết bị USB",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Cắm máy in vào thiết bị qua cáp OTG. Ứng dụng sẽ tự động phát hiện, xin cấp quyền và kết nối tức thì mà không cần thao tác thêm.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
