import 'dart:async';
import 'dart:io';

import 'package:example/connected_device.dart';
import 'package:example/context_extensions.dart';
import 'package:example/devices_tab.dart';
import 'package:example/functions_tab.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

import 'widgets/print_preview_widgets.dart';

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

const String defaultPrinterIp = '192.168.1.199';

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool isConnected = false;
  bool isConnecting = false;
  bool isCheckingStatus = false;
  bool isCheckingConnection = false;
  bool isPrinting = false;

  final TextEditingController textEditingController =
      TextEditingController(text: defaultPrinterIp);
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
  bool _hasBuiltInPrinter = false;
  bool _isBuiltInPrinterConnected = false;

  // Trạng thái quét Bluetooth inline
  List<BluetoothDeviceModel> _btDevices = [];
  bool _isScanningBt = false;
  bool _hasScannedBt = false;
  StreamSubscription<BluetoothDeviceModel>? _btScanSub;
  final Set<String> _connectingBtMacs = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkConnectionState(ipAddress: textEditingController.text);
    _listenUsb();
    _checkBuiltInPrinter();
  }

  Future<void> _checkBuiltInPrinter() async {
    final paperSize = await PrinterLabel.getBuiltInPrinterPaperSize();
    if (mounted) {
      setState(() {
        _hasBuiltInPrinter = paperSize > 0;
        _isBuiltInPrinterConnected = paperSize > 0;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    textEditingController.dispose();
    focusNode.dispose();
    _usbSub?.cancel();
    _btScanSub?.cancel();
    if (Platform.isIOS) {
      PrinterLabel.stopBluetoothScan();
    }
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

  Future<void> _startBtScan() async {
    if (!mounted) return;
    setState(() {
      _isScanningBt = true;
      _hasScannedBt = true;
      _btDevices.clear();
    });

    // Tải các thiết bị đã ghép đôi trước
    try {
      final paired = await PrinterLabel.getBluetoothDevices();
      if (mounted) {
        setState(() {
          for (final d in paired) {
            if (!_btDevices.any((e) => e.mac == d.mac)) {
              _btDevices.add(d);
            }
          }
        });
      }
    } catch (_) {}

    _btScanSub?.cancel();
    _btScanSub = PrinterLabel.bluetoothScanStream().listen(
      (d) {
        if (!mounted) return;
        setState(() {
          if (!_btDevices.any((e) => e.mac == d.mac)) {
            _btDevices.add(d);
          }
        });
      },
      onDone: () {
        if (mounted) setState(() => _isScanningBt = false);
      },
      onError: (_) {
        if (mounted) setState(() => _isScanningBt = false);
      },
    );

    if (Platform.isIOS) {
      await PrinterLabel.startBluetoothScan();
    }
  }

  void _stopBtScan() async {
    _btScanSub?.cancel();
    if (Platform.isIOS) {
      await PrinterLabel.stopBluetoothScan();
    }
    if (mounted) {
      setState(() => _isScanningBt = false);
    }
  }

  Future<void> _connectBtDevice(BluetoothDeviceModel device) async {
    if (!mounted) return;
    final isAlreadyConnected = _connectedDevices.any(
      (d) =>
          d.type == 'BT' && (d.id == device.mac || d.id == 'BT:${device.mac}'),
    );
    if (isAlreadyConnected) {
      context.showSnackBar('Thiết bị này đã được kết nối');
      return;
    }

    setState(() => _connectingBtMacs.add(device.mac));
    _stopBtScan();

    try {
      final ok = await PrinterLabel.connectBluetooth(macAddress: device.mac);
      if (!mounted) return;
      if (ok) {
        final id = DeviceId.bluetooth(device.mac);
        _addConnectedDevice(ConnectedDevice(
          id: id,
          label: device.name.isEmpty ? 'Bluetooth Printer' : device.name,
          type: 'BT',
        ));
        context.showSnackBar(
          'Kết nối Bluetooth thành công: ${device.name.isEmpty ? "máy in" : device.name}',
          backgroundColor: const Color(0xFF10B981),
        );
      } else {
        context.showSnackBar(
          'Không thể kết nối ${device.name.isEmpty ? 'máy in' : device.name}',
          backgroundColor: const Color(0xFFF43F5E),
        );
        _startBtScan();
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Lỗi kết nối: $e',
            backgroundColor: const Color(0xFFF43F5E));
        _startBtScan();
      }
    } finally {
      if (mounted) setState(() => _connectingBtMacs.remove(device.mac));
    }
  }

  Widget _buildBarcodeView(ProductBarcodeModel product) {
    return BarcodeView<ProductBarcodeModel>(
      data: product,
      stampWidth: _selectedRow.stampWidth,
      stampHeight: _selectedRow.stampHeight,
      nameBuilder: (p) => p.name,
      barcodeBuilder: (p) => p.barcode,
      priceBuilder: (p) => p.price,
    );
  }

  Future<void> _checkPrinterStatus(ConnectedDevice device) async {
    setState(() => isCheckingStatus = true);
    context.showSnackBar('Đang kiểm tra máy in...',
        backgroundColor: Colors.blueGrey);
    try {
      // 1. Thử check theo giao thức ESC/POS trước
      var status = await PrinterLabel.checkPrinterStatus(
        deviceId: device.id,
        type: "ESC",
      );

      // 2. Nếu trả về UNKNOWN (do timeout / không phải máy ESC), thử sang TSPL
      if (status == PrinterStatus.unknown) {
        status = await PrinterLabel.checkPrinterStatus(
          deviceId: device.id,
          type: "TSPL",
        );
      }

      if (!mounted) return;
      final (msg, color) = switch (status) {
        PrinterStatus.normal => (
            'Máy in bình thường ✅',
            const Color(0xFF10B981)
          ),
        PrinterStatus.outOfPaper => ('Hết giấy 📄', const Color(0xFFF59E0B)),
        PrinterStatus.paperJam => ('Kẹt giấy ⚠️', Colors.orange),
        PrinterStatus.headOpened => ('Đầu in đang mở 🔓', Colors.orange),
        PrinterStatus.outOfRibbon => ('Hết ruy băng mực 🎞️', Colors.orange),
        PrinterStatus.pause => ('Máy in đang tạm dừng ⏸️', Colors.blueGrey),
        PrinterStatus.printing => ('Đang in... 🖨️', const Color(0xFF4F46E5)),
        PrinterStatus.offline => (
            'Máy in không phản hồi ❌',
            const Color(0xFFE11D48)
          ),
        PrinterStatus.unknown => (
            'Không xác định được trạng thái ❓',
            Colors.grey
          ),
      };
      context.showSnackBar(msg, backgroundColor: color);
    } finally {
      if (mounted) {
        setState(() => isCheckingStatus = false);
      }
    }
  }

  Future<void> _checkConnectionState({required String ipAddress}) async {
    setState(() => isCheckingConnection = true);
    try {
      final connected =
          await PrinterLabel.checkConnect(deviceId: DeviceId.lan(ipAddress));
      setState(() {
        isConnected = connected;
      });

      if (connected) {
        // Tự động kiểm tra loại máy in (thử ESC trước, fallback TSPL)
        var status = await PrinterLabel.checkPrinterStatus(
          deviceId: DeviceId.lan(ipAddress),
          type: "ESC",
        );
        if (status == PrinterStatus.unknown) {
          status = await PrinterLabel.checkPrinterStatus(
            deviceId: DeviceId.lan(ipAddress),
            type: "TSPL",
          );
        }
        if (!mounted) return;
        context.showSnackBar(
          'Trạng thái hoạt động máy in: ${status.name.toUpperCase()}',
          backgroundColor: status == PrinterStatus.normal
              ? const Color(0xFF10B981)
              : const Color(0xFFF59E0B),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isCheckingConnection = false);
      }
    }
  }

  Future<void> _printProductLabels(List<ProductBarcodeModel> items) async {
    if (_connectedDevices.isEmpty) {
      final fallbackId = DeviceId.lan(textEditingController.text);
      await LabelPrintService.instance.printLabels<ProductBarcodeModel>(
        items: items,
        context: context,
        deviceId: fallbackId,
        labelPerRow: _selectedRow,
        itemBuilder: _buildBarcodeView,
        quantity: (p) => p.quantity,
      );
      return;
    }

    for (final device in _connectedDevices) {
      try {
        await LabelPrintService.instance.printLabels<ProductBarcodeModel>(
          items: items,
          context: context,
          deviceId: device.id,
          labelPerRow: _selectedRow,
          itemBuilder: _buildBarcodeView,
          quantity: (p) => p.quantity,
        );
      } catch (e) {
        debugPrint('Lỗi in trên thiết bị ${device.label}: $e');
        if (mounted) {
          showTopNotification(context, 'Lỗi in trên ${device.label}: $e');
        }
      }
    }
  }

  Future<void> _connectLanPrinter() async {
    final input = textEditingController.text.replaceAll(',', '.').trim();
    if (input.isEmpty) return;

    setState(() => isConnecting = true);
    try {
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
    } finally {
      if (mounted) setState(() => isConnecting = false);
    }
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
              isConnecting: isConnecting,
              isCheckingStatus: isCheckingStatus,
              isCheckingConnection: isCheckingConnection,
              isPrinting: isPrinting,
              ipController: textEditingController,
              ipFocusNode: focusNode,
              connectedDevices: _connectedDevices,
              hasBuiltInPrinter: _hasBuiltInPrinter,
              isBuiltInPrinterConnected: _isBuiltInPrinterConnected,
              onConnectBuiltIn: () async {
                setState(() => isConnecting = true);
                try {
                  final ok = await PrinterLabel.autoConnectBuiltIn();
                  if (mounted) {
                    setState(() {
                      _isBuiltInPrinterConnected = ok;
                    });
                    if (ok) {
                      context.showSnackBar('Kết nối máy in tích hợp thành công', backgroundColor: const Color(0xFF10B981));
                    } else {
                      context.showSnackBar('Kết nối máy in tích hợp thất bại');
                    }
                  }
                } finally {
                  if (mounted) setState(() => isConnecting = false);
                }
              },
              onDisconnectBuiltIn: () async {
                final ok = await PrinterLabel.disconnectBuiltIn();
                if (mounted) {
                  setState(() {
                    _isBuiltInPrinterConnected = !ok;
                  });
                  context.showSnackBar('Đã ngắt kết nối máy in tích hợp', backgroundColor: Colors.blueGrey);
                }
              },
              onCheckConnect: () =>
                  _checkConnectionState(ipAddress: textEditingController.text),
              onConnect: _connectLanPrinter,
              onDisconnectMain: () async {
                final disconnect = await PrinterLabel.disconnectPrinter();
                setState(() {
                  isConnected = !disconnect;
                  if (disconnect) {
                    _connectedDevices.clear();
                    _isBuiltInPrinterConnected = false;
                  }
                });
                if (!context.mounted) return;
                context.showSnackBar('Đã tắt kết nối chính',
                    backgroundColor: Colors.blueGrey);
              },
              onDisconnectDevice: (device) async {
                await PrinterLabel.disconnectPrinter(deviceId: device.id);
                _removeConnectedDevice(device.id);
              },
              onCheckPrinterStatus: _checkPrinterStatus,
              btDevices: _btDevices,
              isScanningBt: _isScanningBt,
              hasScannedBt: _hasScannedBt,
              connectingBtMacs: _connectingBtMacs,
              onConnectBtDevice: _connectBtDevice,
              onRefreshBtScan: () {
                if (_isScanningBt) {
                  _stopBtScan();
                } else {
                  _startBtScan();
                }
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
              connectedDevices: _connectedDevices,
              isBuiltInPrinterConnected: _isBuiltInPrinterConnected,
            ),
          ],
        ),
      ),
    );
  }
}
