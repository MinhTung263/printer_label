import 'dart:typed_data';

import 'package:example/select_type_label.dart';
import 'package:example/widgets/print_preview_widgets.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class LabelTab extends StatefulWidget {
  final List<ProductBarcodeModel> products;
  final LabelPerRow selectedRow;
  final ValueChanged<LabelPerRow> onLabelPerRowChanged;
  final Function(List<ProductBarcodeModel> filteredProducts) onPrintLabels;
  final String ipAddress;

  const LabelTab({
    super.key,
    required this.products,
    required this.selectedRow,
    required this.onLabelPerRowChanged,
    required this.onPrintLabels,
    required this.ipAddress,
  });

  @override
  State<LabelTab> createState() => _LabelTabState();
}

class _LabelTabState extends State<LabelTab> {
  List<Uint8List> _labelPreviews = [];
  bool _labelPreviewLoading = false;
  int _previewProductCount = 1;
  bool _isPrintingLabel = false;

  @override
  void initState() {
    super.initState();
    _previewProductCount = widget.selectedRow.count;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPreview());
  }

  @override
  void didUpdateWidget(LabelTab old) {
    super.didUpdateWidget(old);
    if (old.selectedRow != widget.selectedRow ||
        old.products != widget.products) {
      _previewProductCount = widget.selectedRow.count.clamp(1, widget.products.length);
      _refreshPreview();
    }
  }

  Future<void> _refreshPreview() async {
    if (!mounted) return;
    setState(() => _labelPreviewLoading = true);
    try {
      final previewProducts =
          widget.products.take(_previewProductCount).toList();
      final images = await LabelFromWidget.captureImages<ProductBarcodeModel>(
        previewProducts,
        context,
        labelPerRow: widget.selectedRow,
        itemBuilder: (product) => BarcodeView<ProductBarcodeModel>(
          data: product,
          stampWidth: widget.selectedRow.stampWidth,
          stampHeight: widget.selectedRow.stampHeight,
          nameBuilder: (p) => p.name,
          barcodeBuilder: (p) => p.barcode,
          priceBuilder: (p) => p.price,
        ),
        quantity: (p) => p.quantity,
      );
      if (mounted) setState(() => _labelPreviews = images);
    } finally {
      if (mounted) setState(() => _labelPreviewLoading = false);
    }
  }

  Future<void> _printLabels(List<ProductBarcodeModel> items) async {
    setState(() => _isPrintingLabel = true);
    try {
      await widget.onPrintLabels(items);
    } finally {
      if (mounted) setState(() => _isPrintingLabel = false);
    }
  }

  Future<void> _printRawText() async {
    try {
      await LabelPrintService.instance.printText(
        deviceId: DeviceId.lan(widget.ipAddress),
        text: 'Printer Label - Test Raw Text Printing TSPL',
        x: 10,
        y: 10,
        font: 0,
        rotation: 0,
        sizeX: 1,
        sizeY: 1,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi lệnh in Text TSPL')),
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
      await LabelPrintService.instance.printBarcode(
        deviceId: DeviceId.lan(widget.ipAddress),
        code: '123456789012',
        x: 10,
        y: 10,
        height: 80,
        type: '128',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi lệnh in Barcode TSPL')),
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
      await LabelPrintService.instance.printQRCode(
        deviceId: DeviceId.lan(widget.ipAddress),
        code: 'https://github.com/MinhTung263/printer_label',
        x: 10,
        y: 10,
        size: 4,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi lệnh in QR Code TSPL')),
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PrintSectionHeader(
                  icon: Icons.label_outline,
                  color: Color(0xFF4F46E5),
                  title: 'In nhãn TSPL',
                  subtitle:
                      'Tạo nhãn sản phẩm từ widget rồi gửi lệnh TSPL đến máy in.',
                ),
                const SizedBox(height: 10),
                if (_labelPreviewLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_labelPreviews.isNotEmpty)
                  LabelCarousel(
                    images: _labelPreviews,
                    accentColor: const Color(0xFF4F46E5),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child:
                          Icon(Icons.image_not_supported, color: Colors.grey),
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
              // Quy cách
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: LabelPerRowSelector(
                    value: widget.selectedRow,
                    onChanged: widget.onLabelPerRowChanged,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Số sản phẩm
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _previewProductCount,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    items: () {
                      final items = <DropdownMenuItem<int>>[];
                      final maxCount = widget.products.length;
                      final limit = maxCount > 15 ? 15 : maxCount;
                      for (int i = 1; i <= limit; i++) {
                        items.add(DropdownMenuItem(value: i, child: Text('$i SP')));
                      }
                      if (maxCount > limit) {
                        items.add(DropdownMenuItem(
                          value: maxCount,
                          child: const Text('Tất cả'),
                        ));
                      }
                      // Ensure current value is always in the list to prevent errors
                      if (!items.any((item) => item.value == _previewProductCount)) {
                        items.add(DropdownMenuItem(
                          value: _previewProductCount,
                          child: Text('$_previewProductCount SP'),
                        ));
                      }
                      // Sort items by value
                      items.sort((a, b) => a.value!.compareTo(b.value!));
                      return items;
                    }(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _previewProductCount = val);
                        _refreshPreview();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Nút In
              ElevatedButton.icon(
                onPressed: _isPrintingLabel
                    ? null
                    : () => _printLabels(
                          widget.products.take(_previewProductCount).toList(),
                        ),
                icon: _isPrintingLabel
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
                  _isPrintingLabel
                      ? 'Đang in...'
                      : 'In nhãn  •  ${_labelPreviews.length} tờ',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ─── Raw print (dev) ───────────────────────────────────────────────
        buildRawPrintBar(
          color: Colors.blue.shade600,
          title: 'In thô TSPL (dev)',
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
