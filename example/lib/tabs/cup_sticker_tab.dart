import 'dart:typed_data';

import 'package:example/cup_sticker_example.dart';
import 'package:example/select_size.dart';
import 'package:example/widgets/print_preview_widgets.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class CupStickerTab extends StatefulWidget {
  final String ipAddress;

  const CupStickerTab({super.key, required this.ipAddress});

  @override
  State<CupStickerTab> createState() => _CupStickerTabState();
}

class _CupStickerTabState extends State<CupStickerTab> {
  CupStickerSize _selectedCupSize = CupStickerSize.s50x30;
  List<Uint8List> _cupStickerPreviews = [];
  bool _cupPreviewLoading = false;
  int _previewCupCount = 1;

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPreview());
  }

  Future<void> _refreshPreview() async {
    if (!mounted) return;
    setState(() => _cupPreviewLoading = true);
    try {
      final results = <Uint8List>[];
      final previewData = _cupSampleData.take(_previewCupCount).toList();
      for (final data in previewData) {
        if (!mounted) return;
        final bytes = await CupStickerPrinter.captureSticker(
          widget: PreviewCupSticker(data: data),
          size: _selectedCupSize,
          context: context,
        );
        results.add(bytes);
      }
      if (mounted) setState(() => _cupStickerPreviews = results);
    } finally {
      if (mounted) setState(() => _cupPreviewLoading = false);
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
                  icon: Icons.local_drink_outlined,
                  color: Color(0xFF0D9488),
                  title: 'In nhãn dán cốc (Cup Sticker)',
                  subtitle:
                      'In nhãn nhỏ dán lên cốc đồ uống, hỗ trợ nhiều kích thước.',
                ),
                const SizedBox(height: 16),
                if (_cupPreviewLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_cupStickerPreviews.isNotEmpty)
                  CupStickerCarousel(images: _cupStickerPreviews)
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child:
                          Icon(Icons.image_not_supported, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // ─── Controls ──────────────────────────────────────────────────────
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Text(
                  '${_selectedCupSize.widthMm.toInt()} × ${_selectedCupSize.heightMm.toInt()} mm • $_previewCupCount nhãn',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Số sản phẩm xem:',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _previewCupCount,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: 1, child: Text('1 sản phẩm')),
                          if (_cupSampleData.length > 1)
                            const DropdownMenuItem(
                                value: 2, child: Text('2 sản phẩm')),
                          DropdownMenuItem(
                            value: _cupSampleData.length,
                            child: const Text('Tất cả sản phẩm'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _previewCupCount = val);
                            _refreshPreview();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CupStickerSizeSelector(
                value: _selectedCupSize,
                onChanged: (size) {
                  setState(() => _selectedCupSize = size);
                  _refreshPreview();
                },
                onPrint: (select) => CupStickerExample.printOrderCupSticker(
                  select,
                  context: context,
                  deviceId: DeviceId.lan(widget.ipAddress),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
