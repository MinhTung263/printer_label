import 'dart:typed_data';

import 'package:example/select_size.dart';
import 'package:example/select_type_label.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class FunctionsTab extends StatefulWidget {
  final List<ProductBarcodeModel> products;
  final LabelPerRow selectedRow;
  final ValueChanged<LabelPerRow> onLabelPerRowChanged;
  final VoidCallback onPrintLabels;
  final String ipAddress;

  const FunctionsTab({
    super.key,
    required this.products,
    required this.selectedRow,
    required this.onLabelPerRowChanged,
    required this.onPrintLabels,
    required this.ipAddress,
  });

  @override
  State<FunctionsTab> createState() => _FunctionsTabState();
}

class _FunctionsTabState extends State<FunctionsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  CupStickerSize _selectedCupSize = CupStickerSize.s50x30;
  List<Uint8List> _cupStickerPreviews = [];
  bool _cupPreviewLoading = false;
  List<Uint8List> _labelPreviews = [];
  bool _labelPreviewLoading = false;
  int _previewProductCount = 1;
  int _previewCupCount = 1;

  // Mirrors the exact data used by CupStickerExample.printOrderCupSticker
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

  static const _tabs = [
    Tab(icon: Icon(Icons.label_outline, size: 20), text: 'Nhãn'),
    Tab(icon: Icon(Icons.receipt_long, size: 20), text: 'Hoá đơn'),
    Tab(icon: Icon(Icons.local_drink_outlined, size: 20), text: 'Cốc'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshCupPreview();
      _refreshLabelPreview();
    });
  }

  @override
  void didUpdateWidget(FunctionsTab old) {
    super.didUpdateWidget(old);
    // Re-capture when layout or product list changes
    if (old.selectedRow != widget.selectedRow ||
        old.products != widget.products) {
      _refreshLabelPreview();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Captures all cup sticker widgets and resizes them — same pipeline as [CupStickerPrinter.printWithWidgets].
  Future<void> _refreshCupPreview() async {
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

  /// Captures label images — same pipeline as [LabelPrintService.printLabels].
  Future<void> _refreshLabelPreview() async {
    if (!mounted) return;
    setState(() => _labelPreviewLoading = true);
    try {
      final previewProducts = widget.products.take(_previewProductCount).toList();
      final images = await LabelFromWidget.captureImages<ProductBarcodeModel>(
        previewProducts,
        context,
        labelPerRow: widget.selectedRow,
        itemBuilder: (product, dimensions) => BarcodeView<ProductBarcodeModel>(
          data: product,
          dimensions: dimensions,
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

  // ─── Tab bodies ──────────────────────────────────────────────────────────

  Widget _labelTab() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(
                  icon: Icons.label_outline,
                  color: const Color(0xFF4F46E5),
                  title: 'In nhãn TSPL',
                  subtitle:
                      'Tạo nhãn sản phẩm từ widget rồi gửi lệnh TSPL đến máy in.',
                ),
                const SizedBox(height: 16),
                // ─── Preview ───
                if (_labelPreviewLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_labelPreviews.isNotEmpty)
                  _LabelCarousel(
                    images: _labelPreviews,
                    accentColor: const Color(0xFF4F46E5),
                  )
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
                  '${widget.selectedRow.title} • ${_labelPreviews.length} tờ',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 12),
              // Quy cách
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Quy cách in:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: LabelPerRowSelector(
                      value: widget.selectedRow,
                      onChanged: widget.onLabelPerRowChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Số sản phẩm xem trước
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Số sản phẩm xem:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
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
                        items: [
                          const DropdownMenuItem(
                            value: 1,
                            child: Text('1 sản phẩm'),
                          ),
                          if (widget.products.length > 1)
                            const DropdownMenuItem(
                              value: 2,
                              child: Text('2 sản phẩm'),
                            ),
                          DropdownMenuItem(
                            value: widget.products.length,
                            child: const Text('Tất cả sản phẩm'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _previewProductCount = val);
                            _refreshLabelPreview();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.onPrintLabels,
                  icon: const Icon(Icons.print),
                  label: const Text('In nhãn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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

  Widget _escTab() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(
                  icon: Icons.receipt_long,
                  color: const Color(0xFF6366F1),
                  title: 'In hoá đơn ESC/POS',
                  subtitle:
                      'Sử dụng giao thức in hoá đơn nhiệt ESC/POS thông thường.',
                ),
                const SizedBox(height: 16),
                // Preview hóa đơn mẫu — hiển thị toàn bộ
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
              onPressed: () async {
                await ESCPrintService.instance.printExample(
                  deviceId: DeviceId.lan(widget.ipAddress),
                );
              },
              icon: const Icon(Icons.print),
              label: const Text('In thử hoá đơn ESC'),
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
      ],
    );
  }

  Widget _cupStickerTab(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(
                  icon: Icons.local_drink_outlined,
                  color: const Color(0xFF0D9488),
                  title: 'In nhãn dán cốc (Cup Sticker)',
                  subtitle:
                      'In nhãn nhỏ dán lên cốc đồ uống, hỗ trợ nhiều kích thước.',
                ),
                const SizedBox(height: 16),
                // ─── Preview ───
                if (_cupPreviewLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_cupStickerPreviews.isNotEmpty)
                  _CupStickerCarousel(
                    images: _cupStickerPreviews,
                    size: _selectedCupSize,
                  )
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
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 12),
              // Số sản phẩm xem trước
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Số sản phẩm xem:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                            value: 1,
                            child: Text('1 sản phẩm'),
                          ),
                          if (_cupSampleData.length > 1)
                            const DropdownMenuItem(
                              value: 2,
                              child: Text('2 sản phẩm'),
                            ),
                          DropdownMenuItem(
                            value: _cupSampleData.length,
                            child: const Text('Tất cả sản phẩm'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _previewCupCount = val);
                            _refreshCupPreview();
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
                  _refreshCupPreview();
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

  // ─── Shared header widget ─────────────────────────────────────────────────

  Widget _sectionHeader({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
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
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Sub-tab bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF4F46E5),
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: const Color(0xFF4F46E5),
            indicatorWeight: 2.5,
            labelStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            tabs: _tabs,
          ),
        ),
        // Tab body
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _labelTab(),
              _escTab(),
              _cupStickerTab(context),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Vertical preview widget for cup sticker ─────────────────────────────────

class _CupStickerCarousel extends StatelessWidget {
  final List<Uint8List> images;
  final CupStickerSize size;

  const _CupStickerCarousel({required this.images, required this.size});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < images.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _ImageCard(
              bytes: images[i],
              label: 'Nhãn ${i + 1}/${images.length}',
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Vertical preview widget for labels ───────────────────────────────────────

class _LabelCarousel extends StatelessWidget {
  final List<Uint8List> images;
  final Color accentColor;

  const _LabelCarousel({required this.images, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < images.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _ImageCard(
              bytes: images[i],
              label: 'Tờ ${i + 1}/${images.length}',
              accentColor: accentColor,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared image card ────────────────────────────────────────────────────────

class _ImageCard extends StatelessWidget {
  final Uint8List bytes;
  final String label;
  final Color accentColor;

  const _ImageCard({
    required this.bytes,
    required this.label,
    this.accentColor = const Color(0xFF0D9488),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: accentColor,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(
            bytes,
            fit: BoxFit.fitWidth,
            filterQuality: FilterQuality.high,
          ),
        ),
      ],
    );
  }
}
