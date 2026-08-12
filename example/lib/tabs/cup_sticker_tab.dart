import 'package:example/connected_device.dart';
import 'package:example/cup_sticker_example.dart';
import 'package:example/widgets/print_preview_widgets.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class CupStickerTab extends StatefulWidget {
  final String ipAddress;
  final List<ConnectedDevice> connectedDevices;

  const CupStickerTab({super.key, required this.ipAddress, required this.connectedDevices});

  @override
  State<CupStickerTab> createState() => _CupStickerTabState();
}

class _CupStickerTabState extends State<CupStickerTab> {
  CupStickerSize _selectedCupSize = CupStickerSize.s50x30;
  int _previewCupCount = 1;
  bool _isPrinting = false;

  void _showNoConnectionMsg() {
    showTopNotification(context, 'Vui lòng kết nối máy in trước khi in!');
  }

  void _showCupSizePickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Chọn khổ giấy tem',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomInset),
                child: StatefulBuilder(
                  builder: (context, setSheetState) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: CupStickerSize.defaults.map((size) {
                        final isSelected = _selectedCupSize == size;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedCupSize = size);
                            setSheetState(() {});
                            Navigator.pop(context);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF0D9488) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Text(
                              '${size.key}mm',
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.black87,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  // Sample data mirrors CupStickerExample.printOrderCupSticker
  static final _cupSampleData = [
    PreviewLabelModel(
      code: '1213',
      productName: 'Trà sữa',
      price: '27.000 đ',
      companyName: 'Printer Label',
      note: 'Test print',
      labelIndex: 1,
      billDate: '01/01/2026',
      totalLabels: 3,
      toppings: ['Đá', 'Đường'],
    ),
    PreviewLabelModel(
      code: '1214',
      productName: 'Trà đào',
      price: '30.000 đ',
      companyName: 'Printer Label',
      note: 'Order #2',
      labelIndex: 2,
      billDate: '02/01/2026',
      totalLabels: 3,
      toppings: ['Đá', 'Trân châu'],
    ),
    PreviewLabelModel(
      code: '1215',
      productName: 'Trà sữa matcha',
      price: '35.000 đ',
      companyName: 'Printer Label',
      note: 'Order #3',
      labelIndex: 3,
      billDate: '03/01/2026',
      totalLabels: 3,
      toppings: ['Đá', 'Thạch', 'Sữa đặc'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Preview area ──────────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── Thanh Cài Đặt Siêu Gọn (Pill Selector) ───────────────────
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Khổ giấy (Pill Button mở Modal)
                            Expanded(
                              child: GestureDetector(
                                onTap: _showCupSizePickerSheet,
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.local_drink_outlined, size: 16, color: Color(0xFF0D9488)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${_selectedCupSize.key}mm',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF0D9488)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Số lượng sản phẩm (Stepper)
                            Container(
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    icon: const Icon(Icons.remove, size: 16, color: Colors.black54),
                                    onPressed: () {
                                      if (_previewCupCount > 1) {
                                        setState(() => _previewCupCount--);
                                      }
                                    },
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      '$_previewCupCount SP',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    icon: const Icon(Icons.add, size: 16, color: Colors.black54),
                                    onPressed: () {
                                      if (_previewCupCount < _cupSampleData.length) {
                                        setState(() => _previewCupCount++);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ─── Khung Hiển Thị Tem ───────────────────────────────────────
                      Container(
                        width: double.infinity,
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
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            alignment: WrapAlignment.center,
                            children: _cupSampleData.take(_previewCupCount).map((data) {
                              final double cardWidth = _selectedCupSize.widthMm * 4.5;
                              final double cardHeight = _selectedCupSize.heightMm * 4.5;

                              return Container(
                                width: cardWidth,
                                height: cardHeight,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                  border: Border.all(color: Colors.grey.shade200, width: 0.5),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: SizedBox(
                                      width: 350,
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: PreviewCupSticker(data: data),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ─── Futuristic Print Button (Floating) ───────────────────────
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
                              colors: [Color(0xFF0D9488), Color(0xFF14B8A6)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                      color: _isPrinting ? Colors.grey.shade400 : null,
                      boxShadow: _isPrinting
                          ? []
                          : [
                              BoxShadow(
                                color: const Color(0xFF14B8A6).withValues(alpha: 0.5),
                                blurRadius: 20,
                                spreadRadius: 2,
                                offset: const Offset(0, 6),
                              )
                            ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _isPrinting
                            ? null
                            : () async {
                                if (widget.connectedDevices.isEmpty) {
                                  _showNoConnectionMsg();
                                  return;
                                }
                                setState(() => _isPrinting = true);
                                try {
                                  final targets = widget.connectedDevices.map((d) => d.id).toList();
                                  for (final targetId in targets) {
                                    try {
                                      await CupStickerExample.printOrderCupSticker(
                                        _selectedCupSize,
                                        items: _cupSampleData.take(_previewCupCount).toList(),
                                        context: context,
                                        deviceId: targetId,
                                      );
                                    } catch (e) {
                                      debugPrint('Lỗi in tem trà sữa trên $targetId: $e');
                                      if (!context.mounted) return;
                                      showTopNotification(context, 'Lỗi in trên $targetId: $e');
                                    }
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _isPrinting = false);
                                  }
                                }
                              },
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
                                _isPrinting ? 'ĐANG IN...' : 'IN TEM TRÀ SỮA',
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
