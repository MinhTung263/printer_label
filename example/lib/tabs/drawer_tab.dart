import 'package:example/connected_device.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

import '../widgets/print_preview_widgets.dart';

class CashDrawerTab extends StatefulWidget {
  final String ipAddress;
  final List<ConnectedDevice> connectedDevices;

  const CashDrawerTab({
    super.key,
    required this.ipAddress,
    required this.connectedDevices,
  });

  @override
  State<CashDrawerTab> createState() => _CashDrawerTabState();
}

class _CashDrawerTabState extends State<CashDrawerTab> {
  bool _isOpening = false;

  Future<void> _handleOpenDrawer() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    try {
      final success = await PrinterLabel.openDrawer();
      if (mounted) {
        if (success) {
          showTopNotification(context, 'Đã gửi lệnh mở két đựng tiền thu ngân',
              isError: false);
        } else {
          showTopNotification(
              context, 'Vui lòng kết nối mạng LAN/Bluetooth của máy in mới mở két được!');
        }
      }
    } catch (e) {
      if (mounted) {
        showTopNotification(
            context, 'Vui lòng kết nối mạng LAN/Bluetooth của máy in mới mở két được!');
      }
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Banner Thao tác Mở Két Đựng Tiền Sang Trọng
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF0D9488), Color(0xFF10B981)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_open_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Két Thu Ngân (RJ11/RJ12)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Gửi xung điện kích mở két đựng tiền thu ngân ngay lập tức',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFCCFBF1),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isOpening ? null : _handleOpenDrawer,
                  icon: _isOpening
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF0F766E)),
                          ),
                        )
                      : const Icon(Icons.bolt,
                          size: 22, color: Color(0xFF0F766E)),
                  label: Text(
                    _isOpening ? 'ĐANG GỬI LỆNH...' : 'BẤM MỞ KÉT ĐỰNG TIỀN',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Thẻ hướng dẫn sơ đồ kết nối
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200, width: 1.2),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Color(0xFF0D9488), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Sơ đồ kết nối phần cứng',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _buildGuideStep(
                  step: '1',
                  title: 'Máy POS Android',
                  subtitle:
                      'Cắm cáp RJ12 của két vào cổng Drawer dưới gầm/thân máy POS.',
                ),
                const SizedBox(height: 12),
                _buildGuideStep(
                  step: '2',
                  title: 'iPhone / iPad (iOS)',
                  subtitle:
                      'Cắm cáp RJ11/RJ12 của két vào cổng DK phía sau máy in hóa đơn.',
                ),
                const SizedBox(height: 12),
                _buildGuideStep(
                  step: '3',
                  title: 'Chìa khóa két cơ',
                  subtitle:
                      'Vặn chìa khóa về nấc chính giữa (vị trí 12h) để két sẵn sàng bật mở.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuideStep({
    required String step,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: const Color(0xFFCCFBF1),
          child: Text(
            step,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F766E),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
