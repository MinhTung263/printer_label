import 'package:example/connected_device.dart';
import 'package:example/widgets/print_preview_widgets.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class RawPrintTab extends StatefulWidget {
  final String ipAddress;
  final List<ConnectedDevice> connectedDevices;
  final bool isBuiltInPrinterConnected;

  const RawPrintTab({
    super.key,
    required this.ipAddress,
    required this.connectedDevices,
    this.isBuiltInPrinterConnected = false,
  });

  @override
  State<RawPrintTab> createState() => _RawPrintTabState();
}

class _RawPrintTabState extends State<RawPrintTab> {
  void _showNoConnectionMsg() {
    showTopNotification(context, 'Vui lòng kết nối máy in trước khi in!');
  }

  List<String> get _targetDeviceIds => widget.connectedDevices.isNotEmpty
      ? widget.connectedDevices.map((d) => d.id).toList()
      : [DeviceId.lan(widget.ipAddress)];

  // ─── ESC/POS Raw Methods ──────────────────────────────────────────────────
  Future<void> _printEscText() async {
    for (final deviceId in _targetDeviceIds) {
      try {
        await ESCPrintService.instance.printText(
          deviceId: deviceId,
          text: 'Printer Label - Test Raw Text ESC/POS\nXin chào Việt Nam!\n\n\n',
        );
        if (mounted) {
          showTopNotification(context, 'Đã gửi lệnh in Text ESC/POS tới $deviceId', isError: false);
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(context, 'Lỗi in Text ESC/POS: $e');
        }
      }
    }
  }

  Future<void> _printEscBarcode() async {
    for (final deviceId in _targetDeviceIds) {
      try {
        await ESCPrintService.instance.printBarcode(
          deviceId: deviceId,
          code: '123456789012',
          type: '128',
        );
        if (mounted) {
          showTopNotification(context, 'Đã gửi lệnh in Barcode ESC/POS tới $deviceId', isError: false);
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(context, 'Lỗi in Barcode ESC/POS: $e');
        }
      }
    }
  }

  Future<void> _printEscQRCode() async {
    for (final deviceId in _targetDeviceIds) {
      try {
        await ESCPrintService.instance.printQRCode(
          deviceId: deviceId,
          code: 'https://github.com/MinhTung263/printer_label',
          size: 8,
        );
        if (mounted) {
          showTopNotification(context, 'Đã gửi lệnh in QR Code ESC/POS tới $deviceId', isError: false);
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(context, 'Lỗi in QR ESC/POS: $e');
        }
      }
    }
  }

  // ─── TSPL Raw Methods ─────────────────────────────────────────────────────
  Future<void> _printTsplText() async {
    for (final deviceId in _targetDeviceIds) {
      try {
        await LabelPrintService.instance.printText(
          deviceId: deviceId,
          text: 'Printer Label - Test Raw Text TSPL',
          x: 10,
          y: 10,
          font: 0,
          rotation: 0,
          sizeX: 1,
          sizeY: 1,
        );
        if (mounted) {
          showTopNotification(context, 'Đã gửi lệnh in Text TSPL tới $deviceId', isError: false);
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(context, 'Lỗi in Text TSPL: $e');
        }
      }
    }
  }

  Future<void> _printTsplBarcode() async {
    for (final deviceId in _targetDeviceIds) {
      try {
        await LabelPrintService.instance.printBarcode(
          deviceId: deviceId,
          code: '123456789012',
          x: 10,
          y: 10,
          height: 80,
          type: '128',
        );
        if (mounted) {
          showTopNotification(context, 'Đã gửi lệnh in Barcode TSPL tới $deviceId', isError: false);
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(context, 'Lỗi in Barcode TSPL: $e');
        }
      }
    }
  }

  Future<void> _printTsplQRCode() async {
    for (final deviceId in _targetDeviceIds) {
      try {
        await LabelPrintService.instance.printQRCode(
          deviceId: deviceId,
          code: 'https://github.com/MinhTung263/printer_label',
          x: 10,
          y: 10,
          size: 4,
        );
        if (mounted) {
          showTopNotification(context, 'Đã gửi lệnh in QR Code TSPL tới $deviceId', isError: false);
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(context, 'Lỗi in QR TSPL: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasConnection = widget.connectedDevices.isNotEmpty || widget.isBuiltInPrinterConnected;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ─── Header Giới thiệu ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.science_outlined, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kiểm Thử Lệnh Máy In',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Gửi lệnh in chuỗi byte trực tiếp (Raw command) đến máy in mà không qua chuyển đổi ảnh.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ─── Nhóm ESC/POS ──────────────────────────────────────────────────
        _buildSectionCard(
          title: 'Giao Thức ESC/POS (Máy In Hoá Đơn)',
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFF6366F1),
          actions: [
            _buildActionButton(
              icon: Icons.text_fields_rounded,
              label: 'In Text Thô',
              color: const Color(0xFF6366F1),
              onPressed: hasConnection ? _printEscText : _showNoConnectionMsg,
            ),
            _buildActionButton(
              icon: Icons.barcode_reader,
              label: 'In Mã Vạch (128)',
              color: const Color(0xFF6366F1),
              onPressed: hasConnection ? _printEscBarcode : _showNoConnectionMsg,
            ),
            _buildActionButton(
              icon: Icons.qr_code_rounded,
              label: 'In Mã QR Code',
              color: const Color(0xFF6366F1),
              onPressed: hasConnection ? _printEscQRCode : _showNoConnectionMsg,
            ),
          ],
        ),

        const SizedBox(height: 20),

        // ─── Nhóm TSPL ─────────────────────────────────────────────────────
        _buildSectionCard(
          title: 'Giao Thức TSPL (Máy In Tem / Nhãn)',
          icon: Icons.label_outline_rounded,
          color: const Color(0xFF0D9488),
          actions: [
            _buildActionButton(
              icon: Icons.text_fields_rounded,
              label: 'In Text Thô',
              color: const Color(0xFF0D9488),
              onPressed: hasConnection ? _printTsplText : _showNoConnectionMsg,
            ),
            _buildActionButton(
              icon: Icons.barcode_reader,
              label: 'In Mã Vạch (128)',
              color: const Color(0xFF0D9488),
              onPressed: hasConnection ? _printTsplBarcode : _showNoConnectionMsg,
            ),
            _buildActionButton(
              icon: Icons.qr_code_rounded,
              label: 'In Mã QR Code',
              color: const Color(0xFF0D9488),
              onPressed: hasConnection ? _printTsplQRCode : _showNoConnectionMsg,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> actions,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            children: actions.map((btn) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: btn,
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 18, color: color),
        label: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.25), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: color.withValues(alpha: 0.03),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
