import 'package:example/connected_device.dart';
import 'package:example/widgets/print_preview_widgets.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

/// Tab test in tem vàng bạc (nhẫn/trang sức) - decal PVC 42mm rộng,
/// 10mm nội dung + 30mm đuôi nhọn.
class GoldSilverLabelTab extends StatefulWidget {
  final String ipAddress;
  final List<ConnectedDevice> connectedDevices;

  const GoldSilverLabelTab({
    super.key,
    required this.ipAddress,
    required this.connectedDevices,
  });

  @override
  State<GoldSilverLabelTab> createState() => _GoldSilverLabelTabState();
}

class _GoldSilverLabelTabState extends State<GoldSilverLabelTab> {
  int _previewCount = 1;
  bool _isPrinting = false;

  // Dữ liệu mẫu mô phỏng đúng tem trong ảnh thực tế.
  static const _sampleItem = GoldSilverLabelModel(
    companyLine1: 'CTY TNHH TMDV',
    companyLine2: 'VÀNG THIÊN TẠO',
    productType: 'NHẪN',
    barcodeData: 'N02951',
    barcodeCaption: 'N02951 HLV:610',
    tkl: '0c5p07',
    klh: '0c1p2',
    klv: '0.387',
    tc: '315.000 VNĐ',
  );
  static final _sampleData = List.filled(8, _sampleItem);

  void _showNoConnectionMsg() {
    showTopNotification(context, 'Vui lòng kết nối máy in trước khi in!');
  }

  Future<void> _handlePrint() async {
    if (widget.connectedDevices.isEmpty) {
      _showNoConnectionMsg();
      return;
    }
    setState(() => _isPrinting = true);
    try {
      final items = _sampleData.take(_previewCount).toList();
      for (final device in widget.connectedDevices) {
        try {
          await GoldSilverLabelPrinter.printLabels(
            items: items,
            context: context,
            deviceId: device.id,
          );
        } catch (e) {
          debugPrint('Lỗi in tem vàng bạc trên ${device.id}: $e');
          if (!mounted) return;
          showTopNotification(context, 'Lỗi in trên ${device.id}: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Số lượng tem',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: _previewCount > 1
                                      ? () => setState(() => _previewCount--)
                                      : null,
                                ),
                                Text(
                                  '$_previewCount',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: _previewCount < _sampleData.length
                                      ? () => setState(() => _previewCount++)
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Xem trước (42x10mm nội dung + đuôi 30mm)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _sampleData.take(_previewCount).map(
                                (data) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: GoldSilverLabelCanvas(data: data),
                                    ),
                                  );
                                },
                              ).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: _isPrinting
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFFB8860B), Color(0xFFDAA520)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                      color: _isPrinting ? Colors.grey.shade400 : null,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _isPrinting ? null : _handlePrint,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isPrinting)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              else
                                const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                _isPrinting ? 'ĐANG IN...' : 'IN TEM VÀNG BẠC',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
