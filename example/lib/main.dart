import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:example/bt_picker.dart';
import 'package:example/connected_device.dart';
import 'package:example/context_extensions.dart';
import 'package:example/devices_tab.dart';
import 'package:example/functions_tab.dart';
import 'package:example/printer_screen.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printer_label/printer_label.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Printer Label Example',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          primary: const Color(0xFF4F46E5),
          secondary: const Color(0xFF0D9488),
          surface: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          color: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool isConnected = false;

  final TextEditingController textEditingController =
      TextEditingController(text: "192.168.1.56");
  final FocusNode focusNode = FocusNode();

  final List<ProductBarcodeModel> products = [
    ProductBarcodeModel(
      barcode: '83868888',
      name: 'iPhone 17 Pro Max',
      price: 28990000,
      quantity: 1,
    ),
    ProductBarcodeModel(
      barcode: '72341234',
      name: 'AirPods Pro 2',
      price: 6990000,
      quantity: 1,
    ),
    ProductBarcodeModel(
      barcode: '91250099',
      name: 'Apple Watch S10',
      price: 11990000,
      quantity: 3,
    ),
  ];
  LabelPerRow _selectedRow = LabelPerRow.single;

  final List<ConnectedDevice> _connectedDevices = [];
  StreamSubscription<UsbConnectionEvent>? _usbSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkConnectionState(ipAddress: textEditingController.text);
    _listenUsb();
  }

  @override
  void dispose() {
    _tabController.dispose();
    textEditingController.dispose();
    focusNode.dispose();
    _usbSub?.cancel();
    super.dispose();
  }

  void _addConnectedDevice(ConnectedDevice device) {
    setState(() {
      _connectedDevices.removeWhere((d) => d.id == device.id);
      _connectedDevices.add(device);
    });
  }

  void _removeConnectedDevice(String deviceId) {
    setState(() {
      _connectedDevices.removeWhere((d) => d.id == deviceId);
    });
  }

  void _listenUsb() {
    _usbSub = PrinterLabel.usbDeviceStream.listen((event) {
      if (!mounted) return;
      if (event.connected) {
        _addConnectedDevice(ConnectedDevice(
          id: event.deviceId,
          label: 'USB: ${event.deviceId.split('/').last}',
          type: 'USB',
        ));
      } else {
        _removeConnectedDevice(event.deviceId);
      }
    });
  }

  Future<void> _showAddBluetooth() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.locationWhenInUse,
      ].request();
      if (!statuses.values.every((s) => s.isGranted)) {
        if (!mounted) return;
        context.showSnackBar('Cần cấp quyền Bluetooth để tiếp tục',
            backgroundColor: Colors.amber[800]!);
        return;
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BtPicker(
        onConnected: (device) {
          if (!mounted) return;
          final id = DeviceId.bluetooth(device.mac);
          _addConnectedDevice(ConnectedDevice(
            id: id,
            label: device.name.isEmpty ? 'Bluetooth Printer' : device.name,
            type: 'BT',
          ));
          context.showSnackBar(
            'Kết nối Bluetooth thành công: ${device.name}',
            backgroundColor: const Color(0xFF10B981),
          );
        },
      ),
    );
  }

  Widget _buildBarcodeView(ProductBarcodeModel product, Dimensions dimensions) {
    return BarcodeView<ProductBarcodeModel>(
      data: product,
      dimensions: dimensions,
      nameBuilder: (p) => p.name,
      barcodeBuilder: (p) => p.barcode,
      priceBuilder: (p) => p.price,
    );
  }

  Future<List<Uint8List>> _captureProductLabels() async {
    return await LabelFromWidget.captureImages<ProductBarcodeModel>(
      products,
      context,
      labelPerRow: _selectedRow,
      itemBuilder: _buildBarcodeView,
      quantity: (p) => p.quantity,
    );
  }

  Future<LabelModel?> _buildLabelModel() async {
    final images = await _captureProductLabels();
    if (images.isEmpty) return null;
    return LabelModel(images: images, labelPerRow: _selectedRow);
  }

  Future<void> _printAllLan() async {
    if (!_connectedDevices.any((d) => d.type == 'LAN')) {
      context.showSnackBar('Không có máy in LAN nào đang kết nối',
          backgroundColor: Colors.amber[800]!);
      return;
    }
    final model = await _buildLabelModel();
    if (model == null) return;
    await PrinterLabel.printAll(
      labelModel: model,
      connectionType: PrinterConnectionType.lan,
    );
  }

  Future<void> _printAll() async {
    if (_connectedDevices.isEmpty) {
      context.showSnackBar('Chưa có thiết bị nào được kết nối',
          backgroundColor: Colors.amber[800]!);
      return;
    }
    final model = await _buildLabelModel();
    if (model == null) return;
    await PrinterLabel.printAll(labelModel: model);
  }

  Future<void> _printAllEsc() async {
    if (_connectedDevices.isEmpty) {
      context.showSnackBar('Chưa có thiết bị nào được kết nối',
          backgroundColor: Colors.amber[800]!);
      return;
    }
    final image = await ESCPrintService.instance.loadImageFromAssets(
      "packages/printer_label/images/ticket.png",
    );
    await PrinterLabel.printAll(
      escModel: PrintThermalModel(image: image, size: TicketSize.mm80),
    );
  }

  Future<void> _checkConnectionState({required String ipAddress}) async {
    final connected =
        await PrinterLabel.checkConnect(deviceId: DeviceId.lan(ipAddress));
    setState(() {
      isConnected = connected;
    });
  }

  Future<void> _printProductLabels() async {
    await LabelPrintService.instance.printLabels<ProductBarcodeModel>(
      items: products,
      context: context,
      deviceId: DeviceId.lan(textEditingController.text),
      labelPerRow: _selectedRow,
      itemBuilder: _buildBarcodeView,
      quantity: (p) => p.quantity,
    );
  }

  Future<void> _connectLanPrinter() async {
    final input = textEditingController.text.replaceAll(',', '.').trim();
    if (input.isEmpty) return;

    final bool alreadyConnected = await PrinterLabel.checkConnect(
      deviceId: DeviceId.lan(input),
    );
    if (!mounted) return;
    if (alreadyConnected) {
      context.showSnackBar('Thiết bị LAN $input đã kết nối từ trước',
          backgroundColor: Colors.amber[800]!);
      return;
    }

    final bool ok = await PrinterLabel.connectLan(ipAddress: input);
    if (!mounted) return;
    setState(() {
      isConnected = ok;
      if (ok) {
        _addConnectedDevice(ConnectedDevice(
          id: DeviceId.lan(input),
          label: 'LAN: $input',
          type: 'LAN',
        ));
      }
    });
    focusNode.unfocus();
    context.showSnackBar(
      ok ? 'Kết nối LAN thành công: $input' : 'Kết nối LAN thất bại',
      backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.print_outlined, color: Color(0xFF4F46E5)),
            SizedBox(width: 8),
            Text(
              "Printer Dashboard",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF4F46E5),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF4F46E5),
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.devices), text: "Thiết bị"),
            Tab(icon: Icon(Icons.print), text: "Chức năng"),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            DevicesTab(
              isConnected: isConnected,
              ipController: textEditingController,
              ipFocusNode: focusNode,
              connectedDevices: _connectedDevices,
              onCheckConnect: () =>
                  _checkConnectionState(ipAddress: textEditingController.text),
              onConnect: _connectLanPrinter,
              onDisconnectMain: () async {
                final disconnect = await PrinterLabel.disconnectPrinter();
                setState(() {
                  isConnected = !disconnect;
                  if (disconnect) {
                    _connectedDevices.clear();
                  }
                });
                if (!context.mounted) return;
                context.showSnackBar('Đã tắt kết nối chính',
                    backgroundColor: Colors.blueGrey);
              },
              onAddBluetooth: _showAddBluetooth,
              onPrintAllLan: _printAllLan,
              onPrintAll: _printAll,
              onPrintAllEsc: _printAllEsc,
              onDisconnectDevice: (device) async {
                await PrinterLabel.disconnectPrinter(deviceId: device.id);
                _removeConnectedDevice(device.id);
              },
              onPrintDeviceLabel: (device) async {
                await LabelPrintService.instance
                    .printLabels<ProductBarcodeModel>(
                  items: products,
                  context: context,
                  deviceId: device.id,
                  labelPerRow: _selectedRow,
                  itemBuilder: _buildBarcodeView,
                  quantity: (p) => p.quantity,
                );
              },
              onPrintDeviceEsc: (device) async {
                await ESCPrintService.instance
                    .printExample(deviceId: device.id);
              },
              onOpenBluetoothPage: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PrinterScreen(),
                  ),
                );
              },
            ),
            FunctionsTab(
              products: products,
              selectedRow: _selectedRow,
              onLabelPerRowChanged: (label) {
                setState(() {
                  _selectedRow = label;
                });
              },
              onPrintLabels: _printProductLabels,
              ipAddress: textEditingController.text,
            ),
          ],
        ),
      ),
    );
  }
}
