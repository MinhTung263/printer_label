import 'package:example/tabs/cup_sticker_tab.dart';
import 'package:example/tabs/esc_tab.dart';
import 'package:example/tabs/label_tab.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class FunctionsTab extends StatefulWidget {
  final List<ProductBarcodeModel> products;
  final LabelPerRow selectedRow;
  final ValueChanged<LabelPerRow> onLabelPerRowChanged;
  final Function(List<ProductBarcodeModel> filteredProducts) onPrintLabels;
  final String ipAddress;
  final String? deviceId;

  const FunctionsTab({
    super.key,
    required this.products,
    required this.selectedRow,
    required this.onLabelPerRowChanged,
    required this.onPrintLabels,
    required this.ipAddress,
    this.deviceId,
  });

  @override
  State<FunctionsTab> createState() => _FunctionsTabState();
}

class _FunctionsTabState extends State<FunctionsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    Tab(icon: Icon(Icons.label_outline, size: 20), text: 'Nhãn'),
    Tab(icon: Icon(Icons.receipt_long, size: 20), text: 'Hoá đơn'),
    Tab(icon: Icon(Icons.local_drink_outlined, size: 20), text: 'Tem trà sữa'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              LabelTab(
                products: widget.products,
                selectedRow: widget.selectedRow,
                onLabelPerRowChanged: widget.onLabelPerRowChanged,
                onPrintLabels: widget.onPrintLabels,
                ipAddress: widget.ipAddress,
                deviceId: widget.deviceId,
              ),
              EscTab(ipAddress: widget.ipAddress, deviceId: widget.deviceId),
              CupStickerTab(ipAddress: widget.ipAddress, deviceId: widget.deviceId),
            ],
          ),
        ),
      ],
    );
  }
}
