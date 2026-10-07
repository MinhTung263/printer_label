import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printer_label/printer_label.dart';

class NetworkConfigScreen extends StatefulWidget {
  const NetworkConfigScreen({super.key});

  @override
  State<NetworkConfigScreen> createState() => _NetworkConfigScreenState();
}

class _NetworkConfigScreenState extends State<NetworkConfigScreen>
    with SingleTickerProviderStateMixin {
  bool isScanning = false;
  List<Map<String, String>> printers = [];

  final ipController = TextEditingController();
  final maskController = TextEditingController(text: "255.255.255.0");
  final gatewayController = TextEditingController(text: "192.168.1.1");
  Map<String, String>? selectedPrinter;
  bool isConfiguring = false;
  bool useDhcp = false;
  StreamSubscription<LanDeviceModel>? _lanSub;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scan();
  }

  @override
  void dispose() {
    _lanSub?.cancel();
    _pulseController.dispose();
    ipController.dispose();
    maskController.dispose();
    gatewayController.dispose();
    super.dispose();
  }

  String _getBrandType(String? vendor, String name) {
    final lower = '${vendor ?? ''} $name'.toLowerCase();
    if (lower.contains('tsc') || lower.contains('godex')) {
      return 'TSC';
    }
    if (lower.contains('zebra')) {
      return 'ZEBRA';
    }
    return 'POS';
  }

  /// Máy trả lời XP0001FIND (Xprinter/PDIT...) hoặc là máy TSC/Zebra thì đổi IP được
  /// từ app. Còn lại (VD Epson) plugin sẽ báo không hỗ trợ.
  bool _canChangeIp(Map<String, String> p) =>
      p['xp'] == 'true' || _getBrandType(p['vendor'], p['name'] ?? '') != 'POS';

  String _getMethodLabel(String brandType) {
    switch (brandType) {
      case 'TSC':
        return 'TSPL Port 9100';
      case 'ZEBRA':
        return 'ZPL Port 9100';
      default:
        return 'UDP Broadcast 9000';
    }
  }

  Future<void> _scan() async {
    _lanSub?.cancel();

    setState(() {
      isScanning = true;
      printers.clear();
      selectedPrinter = null;
    });

    try {
      // 1. Quét UDP broadcast (XP0001FIND): máy trả lời được -> đổi IP được qua UDP.
      PrinterLabel.scanNetPrinters().then((list) {
        if (!mounted) return;
        setState(() {
          for (final item in list) {
            final ip = item['ip'];
            final mac = item['mac'];
            if (ip == null || ip.isEmpty) continue;

            final index = printers.indexWhere(
              (p) =>
                  p['ip'] == ip ||
                  (mac != null && mac.isNotEmpty && p['mac'] == mac),
            );
            final entry = index >= 0 ? printers[index] : <String, String>{};
            entry['ip'] = ip;
            entry['xp'] = 'true';
            if (mac != null && mac.isNotEmpty) entry['mac'] = mac;
            entry.putIfAbsent('mac', () => '');
            entry.putIfAbsent('name', () => item['name'] ?? 'Máy in LAN');
            entry.putIfAbsent('vendor', () => item['vendor'] ?? '');
            if (item['mask']?.isNotEmpty == true) entry['mask'] = item['mask']!;
            if (item['gateway']?.isNotEmpty == true) {
              entry['gateway'] = item['gateway']!;
            }
            entry['dhcp'] = (item['dhcp'] == 'true') ? 'true' : 'false';
            if (index < 0) printers.add(entry);
          }
        });
      }).catchError((_) {});

      // 2. Quét mạng LAN (cổng 9100): hiện MỌI máy in, kể cả Epson / máy không có
      // MAC — máy không đổi IP được từ app sẽ được đánh dấu trên thẻ.
      final completer = Completer<void>();
      _lanSub = PrinterLabel.discoverLanDevices().listen(
        (device) {
          if (!mounted) return;
          setState(() {
            final mac = device.mac ?? '';
            final index = printers.indexWhere(
              (p) =>
                  p['ip'] == device.ip ||
                  (mac.isNotEmpty && p['mac'] == mac),
            );
            if (index >= 0) {
              if (mac.isNotEmpty) printers[index]['mac'] = mac;
              if (device.name != 'Máy in LAN') {
                printers[index]['name'] = device.name;
              }
              if (device.vendor != null && device.vendor!.isNotEmpty) {
                printers[index]['vendor'] = device.vendor!;
              }
            } else {
              printers.add({
                'ip': device.ip,
                'mac': mac,
                'name': device.name,
                'vendor': device.vendor ?? '',
                'mask': '255.255.255.0',
                'gateway': '',
                'dhcp': 'false',
                'xp': 'false',
              });
            }
          });
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Lỗi quét mạng: $e"),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isScanning = false;
        });
      }
    }
  }

  Future<void> _applyConfig() async {
    if (selectedPrinter == null) return;
    setState(() {
      isConfiguring = true;
    });
    try {
      final newIp = ipController.text.trim();
      final newMask = maskController.text.trim();
      final newGateway = gatewayController.text.trim();
      final targetMac = selectedPrinter!['mac'] ?? '';
      final oldIp = selectedPrinter!['ip'] ?? '';

      // Plugin tự chọn cách gửi lệnh theo máy in, tự kiểm tra trùng IP và xác minh.
      final result = await PrinterLabel.changeLanPrinterIp(
        currentIp: oldIp,
        mac: targetMac.isNotEmpty ? targetMac : null,
        newIp: useDhcp ? null : newIp,
        dhcp: useDhcp,
        mask: newMask,
        gateway: newGateway,
      );
      debugPrint('[changeLanPrinterIp] $result');

      if (!mounted) return;
      final ok = result.status == LanIpChangeStatus.success;
      final warn = result.status == LanIpChangeStatus.unverified;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              Icon(
                ok
                    ? Icons.check_circle
                    : (warn ? Icons.info_outline : Icons.error_outline),
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.message,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: ok
              ? const Color(0xFF10B981)
              : (warn ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
          duration: Duration(seconds: ok || warn ? 5 : 4),
        ),
      );

      if (ok || warn) {
        setState(() {
          final idx = printers.indexWhere((p) =>
              (targetMac.isNotEmpty && p['mac'] == targetMac) ||
              (oldIp.isNotEmpty && p['ip'] == oldIp));
          if (idx >= 0) {
            if (result.ip != null) printers[idx]['ip'] = result.ip!;
            printers[idx]['mask'] = newMask;
            printers[idx]['gateway'] = newGateway;
            printers[idx]['dhcp'] = useDhcp ? 'true' : 'false';
            selectedPrinter = printers[idx];
          }
        });

        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _scan();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text("Lỗi cấu hình: $e"),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isConfiguring = false;
        });
      }
    }
  }

  /// Điền mask/gateway theo cấu hình thật của máy in (nếu máy trả lời XP0001FIND).
  Future<void> _prefillFromPrinter(String ip) async {
    final info = await PrinterLabel.queryXpUdpInfo(ip);
    if (info == null || !mounted || selectedPrinter?['ip'] != ip) return;
    setState(() {
      maskController.text = info.mask;
      gatewayController.text = info.gateway;
      useDhcp = info.dhcp;
    });
  }

  void _autoSuggestGatewayFromIp(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      final defaultGw = '${parts[0]}.${parts[1]}.${parts[2]}.1';
      gatewayController.text = defaultGw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedBrandType = selectedPrinter != null
        ? _getBrandType(
            selectedPrinter!['vendor'], selectedPrinter!['name'] ?? '')
        : 'POS';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Color(0xFF334155), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.router, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Text(
              "Cấu hình mạng",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF0F172A),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              onPressed: isScanning ? null : _scan,
              icon: isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF4F46E5)),
                      ),
                    )
                  : const Icon(Icons.radar,
                      color: Color(0xFF4F46E5), size: 24),
              tooltip: "Quét lại mạng",
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Top Scan Status Bar ─────────────────────────────────────────
              _buildScanStatusBar(),
              const SizedBox(height: 16),

              // ─── Section 1: Discovered Devices List ──────────────────────────
              _buildDeviceSectionHeader(),
              const SizedBox(height: 10),
              _buildDeviceList(),
              const SizedBox(height: 24),

              // ─── Section 2: Configuration Console ───────────────────────────
              if (selectedPrinter != null) ...[
                _buildConfigConsole(selectedBrandType),
                const SizedBox(height: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Top Scan Status Bar ───────────────────────────────────────────────────
  Widget _buildScanStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isScanning
              ? const Color(0xFF4F46E5).withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: isScanning
                ? const Color(0xFF4F46E5).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isScanning
                      ? const Color(0xFF4F46E5)
                      : (printers.isNotEmpty
                          ? const Color(0xFF10B981)
                          : const Color(0xFF94A3B8)),
                  boxShadow: [
                    BoxShadow(
                      color: isScanning
                          ? const Color(0xFF4F46E5).withValues(
                              alpha: 0.3 + 0.3 * _pulseController.value)
                          : (printers.isNotEmpty
                              ? const Color(0xFF10B981).withValues(alpha: 0.4)
                              : Colors.transparent),
                      blurRadius: isScanning ? 6 : 3,
                      spreadRadius: isScanning ? 1.5 : 0,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isScanning
                  ? "Đang dò quét UDP Broadcast & mạng LAN..."
                  : (printers.isNotEmpty
                      ? "Đã tìm thấy ${printers.length} máy in hỗ trợ cấu hình"
                      : "Sẵn sàng quét thiết bị"),
              style: TextStyle(
                color: isScanning
                    ? const Color(0xFF4F46E5)
                    : const Color(0xFF475569),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!isScanning)
            GestureDetector(
              onTap: _scan,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.2)),
                ),
                child: const Text(
                  "Quét lại",
                  style: TextStyle(
                    color: Color(0xFF4F46E5),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Section Header ─────────────────────────────────────────────────────────
  Widget _buildDeviceSectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Row(
          children: [
            Icon(Icons.sensors, size: 16, color: Color(0xFF4F46E5)),
            SizedBox(width: 6),
            Text(
              "DANH SÁCH MÁY IN KHẢ DỤNG",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4F46E5),
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        Text(
          "${printers.length} máy in",
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ─── Device List Cards ───────────────────────────────────────────────────────
  Widget _buildDeviceList() {
    if (printers.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                if (isScanning)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 68 + 18 * _pulseController.value,
                        height: 68 + 18 * _pulseController.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4F46E5).withValues(
                              alpha: 0.12 - 0.08 * _pulseController.value),
                        ),
                      );
                    },
                  ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Icon(
                    isScanning ? Icons.radar : Icons.print_disabled,
                    size: 26,
                    color: isScanning
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              isScanning
                  ? "Đang tìm kiếm máy in qua UDP & LAN..."
                  : "Không tìm thấy máy in nào",
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Đảm bảo máy in đã bật nguồn và cắm cáp mạng LAN cùng Router WiFi",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: printers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final p = printers[index];
        final isSelected = selectedPrinter == p;
        final hasMac = p['mac'] != null && p['mac']!.isNotEmpty;
        final hasModelName = p['name'] != null &&
            p['name']!.isNotEmpty &&
            p['name'] != 'Máy in LAN';
        final brandType = _getBrandType(p['vendor'], p['name'] ?? '');

        final primaryName = hasMac
            ? p['mac']!
            : (hasModelName ? p['name']! : (p['ip'] ?? 'Máy in LAN'));

        return InkWell(
          onTap: () {
            setState(() {
              selectedPrinter = p;
              ipController.text = p['ip'] ?? '';
              if (p['mask']?.isNotEmpty == true) {
                maskController.text = p['mask']!;
              }
              if (p['gateway']?.isNotEmpty == true) {
                gatewayController.text = p['gateway']!;
              }
              useDhcp = (p['dhcp'] == 'true');
            });
            final ip = p['ip'];
            if (ip != null && ip.isNotEmpty) _prefillFromPrinter(ip);
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF4F46E5).withValues(alpha: 0.04)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF4F46E5)
                    : Colors.grey.shade200,
                width: isSelected ? 1.8 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? const Color(0xFF4F46E5).withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.02),
                  blurRadius: isSelected ? 12 : 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFFEEF2F6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.print,
                    color: isSelected ? Colors.white : const Color(0xFF4F46E5),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              primaryName,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                fontSize: 13.5,
                                color: const Color(0xFF0F172A),
                                fontFamily: hasMac ? 'monospace' : null,
                                letterSpacing: hasMac ? 0.4 : 0.0,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F46E5)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: const Color(0xFF4F46E5)
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              (p['vendor']?.isNotEmpty == true
                                      ? p['vendor']!
                                      : brandType) +
                                  (_canChangeIp(p)
                                      ? ''
                                      : ' · không đổi IP được'),
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: Color(0xFF4F46E5),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lan,
                                  size: 12, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 4),
                              Text(
                                p['ip'] ?? '',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          if (hasMac && hasModelName)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.print_outlined,
                                    size: 12, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 4),
                                Text(
                                  p['name']!,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFFCBD5E1),
                      width: isSelected ? 2 : 1.5,
                    ),
                    color: isSelected
                        ? const Color(0xFF4F46E5)
                        : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Section 2: Configuration Console ───────────────────────────────────────
  Widget _buildConfigConsole(String selectedBrandType) {
    final methodLabel = _getMethodLabel(selectedBrandType);
    final targetMac = selectedPrinter!['mac'] ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune,
                    color: Color(0xFF4F46E5), size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "BẢNG ĐIỀU KHIỂN MẠNG",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      "Cấu hình thông số IP máy in",
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (targetMac.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tag, size: 14, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 6),
                  const Text(
                    "ĐỊA CHỈ MAC:",
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      targetMac,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4F46E5),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy,
                        size: 14, color: Color(0xFF64748B)),
                    tooltip: "Sao chép MAC",
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: targetMac));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Đã sao chép MAC vào clipboard"),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt, size: 14, color: Color(0xFFD97706)),
                const SizedBox(width: 6),
                Text(
                  "Giao thức thực thi: $methodLabel",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Segmented Mode Toggle (Static IP vs DHCP)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        useDhcp = false;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: !useDhcp ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [
                          if (!useDhcp)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.tune,
                            size: 14,
                            color: !useDhcp
                                ? const Color(0xFF4F46E5)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "IP TĨNH (STATIC)",
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: !useDhcp
                                  ? const Color(0xFF4F46E5)
                                  : const Color(0xFF64748B),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        useDhcp = true;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: useDhcp ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [
                          if (useDhcp)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: useDhcp
                                ? const Color(0xFF0D9488)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "TỰ ĐỘNG (DHCP)",
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: useDhcp
                                  ? const Color(0xFF0D9488)
                                  : const Color(0xFF64748B),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: useDhcp
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF86EFAC),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(
                            color: Color(0xFFDCFCE7),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.router,
                            color: Color(0xFF16A34A),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Chế độ DHCP kích hoạt",
                                style: TextStyle(
                                  color: Color(0xFF15803D),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                "Máy in sẽ tự động nhận dải IP từ Router WiFi nội bộ mỗi khi khởi động.",
                                style: TextStyle(
                                  color: Color(0xFF166534),
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      _buildFuturisticTextField(
                        label: "Địa chỉ IP mới",
                        controller: ipController,
                        icon: Icons.lan,
                        hint: "192.168.1.199",
                        onChanged: _autoSuggestGatewayFromIp,
                      ),
                      const SizedBox(height: 10),
                      _buildFuturisticTextField(
                        label: "Subnet Mask",
                        controller: maskController,
                        icon: Icons.mediation,
                        hint: "255.255.255.0",
                      ),
                      const SizedBox(height: 10),
                      _buildFuturisticTextField(
                        label: "Default Gateway",
                        controller: gatewayController,
                        icon: Icons.router,
                        hint: "192.168.1.1",
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 20),

          Container(
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF4F46E5),
                  Color(0xFF6366F1),
                  Color(0xFF06B6D4),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: isConfiguring ? null : _applyConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isConfiguring
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Đang gửi gói tin cấu hình...",
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save_outlined, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Lưu cấu hình mạng",
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Styled Light Input Field ───────────────────────────────────────────────
  Widget _buildFuturisticTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
          ),
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 12.5,
            fontFamily: 'monospace',
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF4F46E5), size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 30),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }
}
