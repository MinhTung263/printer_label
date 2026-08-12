
import 'package:example/connected_device.dart';
import 'package:example/widgets/print_preview_widgets.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class LabelTab extends StatefulWidget {
  final List<ProductBarcodeModel> products;
  final LabelPerRow selectedRow;
  final ValueChanged<LabelPerRow> onLabelPerRowChanged;
  final Function(List<ProductBarcodeModel> filteredProducts) onPrintLabels;
  final String ipAddress;
  final List<ConnectedDevice> connectedDevices;

  const LabelTab({
    super.key,
    required this.products,
    required this.selectedRow,
    required this.onLabelPerRowChanged,
    required this.onPrintLabels,
    required this.ipAddress,
    required this.connectedDevices,
  });

  @override
  State<LabelTab> createState() => _LabelTabState();
}

class _LabelTabState extends State<LabelTab> {
  int _previewProductCount = 1;
  bool _isPrintingLabel = false;

  void _showNoConnectionMsg() {
    showTopNotification(context, 'Vui lòng kết nối máy in trước khi in!');
  }

  @override
  void initState() {
    super.initState();
    _previewProductCount = widget.selectedRow.count;
  }

  @override
  void didUpdateWidget(LabelTab old) {
    super.didUpdateWidget(old);
    if (old.selectedRow != widget.selectedRow ||
        old.products != widget.products) {
      _previewProductCount = widget.selectedRow.count.clamp(1, widget.products.length);
    }
  }

  List<ProductBarcodeModel> _getExpandedProducts() {
    final previewProducts = widget.products.take(_previewProductCount).toList();
    final List<ProductBarcodeModel> expanded = [];
    for (final p in previewProducts) {
      for (int i = 0; i < p.quantity; i++) {
        expanded.add(p);
      }
    }
    return expanded;
  }

  Widget _buildPreviewArea() {
    final expanded = _getExpandedProducts();
    if (expanded.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Icon(Icons.image_not_supported, color: Colors.grey),
        ),
      );
    }

    final int itemsPerRow = widget.selectedRow.count;
    final List<List<ProductBarcodeModel>> rows = [];
    for (int i = 0; i < expanded.length; i += itemsPerRow) {
      final end = (i + itemsPerRow < expanded.length) ? i + itemsPerRow : expanded.length;
      rows.add(expanded.sublist(i, end));
    }

    final double leftPadding = widget.selectedRow.name.startsWith('double')
        ? 10.0
        : (widget.selectedRow.name.startsWith('triple') ? 8.0 : 8.0);
    final double rightPadding = leftPadding;
    final double spacer = widget.selectedRow.name.startsWith('double')
        ? 10.0
        : (widget.selectedRow.name.startsWith('triple') ? 12.0 : 0.0);

    return Container(
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
      child: Column(
        children: rows.map((rowItems) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: FittedBox(
              fit: BoxFit.contain,
              child: Container(
                color: Colors.white,
                padding: EdgeInsets.fromLTRB(leftPadding, 10, rightPadding, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(itemsPerRow, (index) {
                    final Widget itemWidget;
                    if (index < rowItems.length) {
                      final product = rowItems[index];
                      itemWidget = Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300, width: 0.5),
                        ),
                        child: BarcodeView<ProductBarcodeModel>(
                          data: product,
                          stampWidth: widget.selectedRow.stampWidth,
                          stampHeight: widget.selectedRow.stampHeight,
                          nameBuilder: (p) => p.name,
                          barcodeBuilder: (p) => p.barcode,
                          priceBuilder: (p) => p.price,
                        ),
                      );
                    } else {
                      itemWidget = SizedBox(
                        width: widget.selectedRow.stampWidth * 6.57,
                        height: widget.selectedRow.stampHeight * 6.57,
                      );
                    }

                    if (index < itemsPerRow - 1) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          itemWidget,
                          SizedBox(width: spacer),
                        ],
                      );
                    }
                    return itemWidget;
                  }),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _printLabels(List<ProductBarcodeModel> items) async {
    setState(() => _isPrintingLabel = true);
    try {
      await widget.onPrintLabels(items);
    } finally {
      if (mounted) setState(() => _isPrintingLabel = false);
    }
  }


  void _showLabelPickerSheet() {
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
            // Drag handle
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
                'Chọn quy cách in nhãn',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabelSection('1 TEM / HÀNG', LabelPerRow.values.where((item) => !item.name.startsWith('double') && !item.name.startsWith('triple')).toList()),
                    const SizedBox(height: 16),
                    _buildLabelSection('2 TEM / HÀNG', LabelPerRow.values.where((item) => item.name.startsWith('double')).toList()),
                    const SizedBox(height: 16),
                    _buildLabelSection('3 TEM / HÀNG', LabelPerRow.values.where((item) => item.name.startsWith('triple')).toList()),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLabelSection(String title, List<LabelPerRow> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5), letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final isSelected = widget.selectedRow == opt;
            return GestureDetector(
              onTap: () {
                widget.onLabelPerRowChanged(opt);
                Navigator.pop(context);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF4F46E5) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : null,
                ),
                child: Text(
                  opt.title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

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
                      // ─── Thanh Cài Đặt Siêu Gọn ───────────────────────────────────
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
                            // Quy cách (Pill Button mở Modal)
                            Expanded(
                              child: GestureDetector(
                                onTap: _showLabelPickerSheet,
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.style_outlined, size: 16, color: Color(0xFF4F46E5)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          widget.selectedRow.title,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF4F46E5)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Số sản phẩm (Stepper)
                            Container(
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                    icon: const Icon(Icons.remove, size: 16, color: Colors.black54),
                                    onPressed: () {
                                      if (_previewProductCount > 1) {
                                        setState(() => _previewProductCount--);
                                      }
                                    },
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      '$_previewProductCount SP',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                    icon: const Icon(Icons.add, size: 16, color: Colors.black54),
                                    onPressed: () {
                                      if (_previewProductCount < widget.products.length) {
                                        setState(() => _previewProductCount++);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ─── Khung Hiển Thị Nhãn ──────────────────────────────────────
                      _buildPreviewArea(),
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
                      gradient: _isPrintingLabel
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                      color: _isPrintingLabel ? Colors.grey.shade400 : null,
                      boxShadow: _isPrintingLabel
                          ? []
                          : [
                              BoxShadow(
                                color: const Color(0xFF06B6D4).withValues(alpha: 0.5),
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
                        onTap: _isPrintingLabel
                            ? null
                            : () {
                                if (widget.connectedDevices.isEmpty) {
                                  _showNoConnectionMsg();
                                  return;
                                }
                                _printLabels(
                                  widget.products.take(_previewProductCount).toList(),
                                );
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isPrintingLabel)
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
                                _isPrintingLabel
                                    ? 'ĐANG IN...'
                                    : 'IN NHÃN • ${(_getExpandedProducts().length / widget.selectedRow.count).ceil()} TỜ',
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
