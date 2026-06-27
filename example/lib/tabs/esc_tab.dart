import 'dart:typed_data';

import 'package:example/widgets/print_preview_widgets.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class EscTab extends StatefulWidget {
  final String ipAddress;

  const EscTab({super.key, required this.ipAddress});

  @override
  State<EscTab> createState() => _EscTabState();
}

class _EscTabState extends State<EscTab> {
  bool _isPrintingEsc = false;

  Future<Uint8List> _loadImageFromAssets(String path) async {
    final byteData = await DefaultAssetBundle.of(context).load(path);
    return byteData.buffer.asUint8List();
  }

  Future<void> _printExample() async {
    setState(() => _isPrintingEsc = true);
    try {
      final image = await _loadImageFromAssets(
          'packages/printer_label/images/ticket.png');
      await ESCPrintService.instance.print(
        deviceId: DeviceId.lan(widget.ipAddress),
        model: PrintThermalModel(image: image, size: TicketSize.mm58),
      );
    } finally {
      if (mounted) setState(() => _isPrintingEsc = false);
    }
  }

  Future<void> _printRawText() async {
    try {
      await ESCPrintService.instance.printText(
        deviceId: DeviceId.lan(widget.ipAddress),
        text:
            'Printer Label - Test Raw Text Printing ESC/POS\nLine 2 - Hello World!\n\n',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi lệnh in Text ESC')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _printRawBarcode() async {
    try {
      await ESCPrintService.instance.printBarcode(
        deviceId: DeviceId.lan(widget.ipAddress),
        code: '123456789012',
        type: '128',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi lệnh in Barcode ESC')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _printRawQRCode() async {
    try {
      await ESCPrintService.instance.printQRCode(
        deviceId: DeviceId.lan(widget.ipAddress),
        code: 'https://github.com/MinhTung263/printer_label',
        size: 8,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi lệnh in QR Code ESC')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Preview area ──────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PrintSectionHeader(
                  icon: Icons.receipt_long,
                  color: Color(0xFF6366F1),
                  title: 'In hoá đơn ESC/POS',
                  subtitle:
                      'Sử dụng giao thức in hoá đơn nhiệt ESC/POS thông thường.',
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 240),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'packages/printer_label/images/ticket.png',
                      fit: BoxFit.fitWidth,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ─── Print button ──────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                offset: const Offset(0, -4),
                blurRadius: 8,
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isPrintingEsc ? null : _printExample,
              icon: _isPrintingEsc
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.print),
              label: Text(
                  _isPrintingEsc ? 'Đang in...' : 'In thử hoá đơn ESC'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        // ─── Raw print (dev) ───────────────────────────────────────────────
        buildRawPrintBar(
          color: Colors.indigo.shade600,
          title: 'In thô ESC/POS (dev)',
          buttons: [
            (label: 'In Text', onPressed: _printRawText),
            (label: 'In Barcode', onPressed: _printRawBarcode),
            (label: 'In QR', onPressed: _printRawQRCode),
          ],
        ),
      ],
    );
  }
}
