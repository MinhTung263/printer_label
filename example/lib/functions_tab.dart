import 'package:example/connected_device.dart';
import 'package:example/tabs/cup_sticker_tab.dart';
import 'package:example/tabs/drawer_tab.dart';
import 'package:example/tabs/esc_tab.dart';
import 'package:example/tabs/gold_silver_label_tab.dart';
import 'package:example/tabs/label_tab.dart';
import 'package:example/tabs/raw_tab.dart';
import 'package:example/widgets/custom_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class FunctionsTab extends StatefulWidget {
  final List<ProductBarcodeModel> products;
  final LabelPerRow selectedRow;
  final ValueChanged<LabelPerRow> onLabelPerRowChanged;
  final Function(List<ProductBarcodeModel> filteredProducts) onPrintLabels;
  final String ipAddress;
  final List<ConnectedDevice> connectedDevices;
  final bool isBuiltInPrinterConnected;

  const FunctionsTab({
    super.key,
    required this.products,
    required this.selectedRow,
    required this.onLabelPerRowChanged,
    required this.onPrintLabels,
    required this.ipAddress,
    required this.connectedDevices,
    this.isBuiltInPrinterConnected = false,
  });

  @override
  State<FunctionsTab> createState() => _FunctionsTabState();
}

class _FunctionsTabState extends State<FunctionsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    CustomTab(
      icon: Icons.receipt_long,
      label: 'Hoá đơn',
      direction: Axis.vertical,
    ),
    CustomTab(
      icon: Icons.label_outline,
      label: 'Nhãn',
      direction: Axis.vertical,
    ),
    CustomTab(
      icon: Icons.local_drink_outlined,
      label: 'Trà sữa',
      direction: Axis.vertical,
    ),
    CustomTab(
      icon: Icons.diamond_outlined,
      label: 'Vàng bạc',
      direction: Axis.vertical,
    ),
    CustomTab(
      icon: Icons.lock_open_rounded,
      label: 'Mở két',
      direction: Axis.vertical,
    ),
    CustomTab(
      icon: Icons.science_outlined,
      label: 'Kiểm thử',
      direction: Axis.vertical,
    ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomTabBar(
          controller: _tabController,
          tabs: _tabs,
          isScrollable: false,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              EscTab(
                ipAddress: widget.ipAddress,
                connectedDevices: widget.connectedDevices,
                isBuiltInPrinterConnected: widget.isBuiltInPrinterConnected,
              ),
              LabelTab(
                products: widget.products,
                selectedRow: widget.selectedRow,
                onLabelPerRowChanged: widget.onLabelPerRowChanged,
                onPrintLabels: widget.onPrintLabels,
                ipAddress: widget.ipAddress,
                connectedDevices: widget.connectedDevices,
              ),
              CupStickerTab(
                  ipAddress: widget.ipAddress,
                  connectedDevices: widget.connectedDevices),
              GoldSilverLabelTab(
                  ipAddress: widget.ipAddress,
                  connectedDevices: widget.connectedDevices),
              CashDrawerTab(
                  ipAddress: widget.ipAddress,
                  connectedDevices: widget.connectedDevices),
              RawPrintTab(
                ipAddress: widget.ipAddress,
                connectedDevices: widget.connectedDevices,
                isBuiltInPrinterConnected: widget.isBuiltInPrinterConnected,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
