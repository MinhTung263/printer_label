import 'package:example/cup_sticker_example.dart';
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
  int _previewCupCount = 1;
  bool _isPrinting = false;

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PrintSectionHeader(
                  icon: Icons.local_drink_outlined,
                  color: Color(0xFF0D9488),
                  title: 'In tem trà sữa',
                  subtitle:
                      'In tem dán cốc trà sữa, đồ uống, hỗ trợ nhiều kích thước.',
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200, width: 0.5),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children:
                          _cupSampleData.take(_previewCupCount).map((data) {
                        final double cardWidth = _selectedCupSize.widthMm * 4.5;
                        final double cardHeight =
                            _selectedCupSize.heightMm * 4.5;

                        return Container(
                          width: cardWidth,
                          height: cardHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                            border: Border.all(
                                color: Colors.grey.shade200, width: 0.5),
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
        // ─── Controls + Print button ───────────────────────────────────────
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Khổ giấy Dropdown
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<CupStickerSize>(
                      value: _selectedCupSize,
                      isExpanded: true,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                      items: CupStickerSize.defaults.map((size) {
                        return DropdownMenuItem(
                          value: size,
                          child: Text('${size.key} mm'),
                        );
                      }).toList(),
                      onChanged: (size) {
                        if (size != null) {
                          setState(() => _selectedCupSize = size);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Số sản phẩm Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                      const DropdownMenuItem(value: 1, child: Text('1 SP')),
                      if (_cupSampleData.length > 1)
                        const DropdownMenuItem(value: 2, child: Text('2 SP')),
                      DropdownMenuItem(
                        value: _cupSampleData.length,
                        child: const Text('Tất cả'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _previewCupCount = val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Nút In
              ElevatedButton.icon(
                onPressed: _isPrinting
                    ? null
                    : () async {
                        setState(() => _isPrinting = true);
                        try {
                          await CupStickerExample.printOrderCupSticker(
                            _selectedCupSize,
                            items:
                                _cupSampleData.take(_previewCupCount).toList(),
                            context: context,
                            deviceId: DeviceId.lan(widget.ipAddress),
                          );
                        } finally {
                          if (mounted) {
                            setState(() => _isPrinting = false);
                          }
                        }
                      },
                icon: _isPrinting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.print, size: 16),
                label: Text(
                  _isPrinting
                      ? 'Đang in...'
                      : 'In tem  •  $_previewCupCount tờ',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
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
