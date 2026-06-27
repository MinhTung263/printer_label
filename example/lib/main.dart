import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:example/bt_picker.dart';
import 'package:example/connected_device.dart';
import 'package:example/context_extensions.dart';
import 'package:example/devices_tab.dart';
import 'package:example/functions_tab.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printer_label/printer_label.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

// ⭐ Model cho thiết bị BT đã lưu trong SharedPreferences
class _SavedBtDevice {
  final String id; // UUID (iOS) hoặc MAC (Android)
  final String name; // Tên hiển thị
  const _SavedBtDevice({required this.id, required this.name});
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
  bool isConnecting = false;
  bool isCheckingStatus = false;
  bool isCheckingConnection = false;
  bool isPrinting = false;

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
          _saveBtIdentifier(device.mac, device.name);
          context.showSnackBar(
            'Kết nối Bluetooth thành công: ${device.name}',
            backgroundColor: const Color(0xFF10B981),
          );
        },
      ),
    );
  }

  // ⭐ Lưu danh sách thiết bị BT đã kết nối (lưu nhiều máy)
  static const String _prefsBtListKey = 'saved_bt_devices';

  Future<void> _saveBtIdentifier(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsBtListKey) ?? [];
    // Format: "id|name"
    final entry = '$id|$name';
    // Nếu đã có thiết bị này thì cập nhật lại, không thêm trùng
    final idx = list.indexWhere((e) => e.startsWith('$id|'));
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    await prefs.setStringList(_prefsBtListKey, list);
  }

  /// Đọc danh sách thiết bị BT đã lưu
  Future<List<_SavedBtDevice>> _getSavedBtDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsBtListKey) ?? [];
    final result = <_SavedBtDevice>[];
    for (final entry in list) {
      final parts = entry.split('|');
      if (parts.length >= 2) {
        result.add(_SavedBtDevice(id: parts[0], name: parts[1]));
      }
    }
    return result;
  }

  /// Xóa 1 thiết bị khỏi danh sách đã lưu
  Future<void> _removeSavedBtDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsBtListKey) ?? [];
    list.removeWhere((e) => e.startsWith('$id|'));
    await prefs.setStringList(_prefsBtListKey, list);
  }

  // ⭐ Mở dialog chọn thiết bị BT đã lưu để reconnect
  Future<void> _showSavedBtPicker() async {
    final savedList = await _getSavedBtDevices();
    if (savedList.isEmpty) {
      context.showSnackBar(
        'Chưa có thiết bị BT nào được lưu. Hãy scan và kết nối trước.',
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SavedBtPicker(
        devices: savedList,
        onConnect: (device) => _reconnectBtFromSaved(device),
        onDelete: (device) async {
          await _removeSavedBtDevice(device.id);
          if (!mounted) return;
          setState(() {});
          context.showSnackBar('Đã xóa ${device.name} khỏi danh sách',
              backgroundColor: Colors.orange);
        },
      ),
    );
  }

  // ⭐ Thử reconnect BLE từ identifier đã lưu — KHÔNG CẦN SCAN TRÊN iOS
  Future<void> _reconnectBtFromSaved(_SavedBtDevice device) async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();
      if (!statuses.values.every((s) => s.isGranted)) {
        if (!mounted) return;
        context.showSnackBar('Cần cấp quyền Bluetooth', backgroundColor: Colors.orange);
        return;
      }
    }

    context.showSnackBar('Đang kết nối lại ${device.name}...', backgroundColor: Colors.blue);
    try {
      final ok = await PrinterLabel.connectBluetooth(macAddress: device.id);
      if (!mounted) return;
      if (ok) {
        setState(() {
          final id = DeviceId.bluetooth(device.id);
          _addConnectedDevice(ConnectedDevice(
            id: id,
            label: device.name.isEmpty ? 'Bluetooth Printer' : device.name,
            type: 'BT',
          ));
        });
        context.showSnackBar('Kết nối lại thành công: ${device.name}', backgroundColor: Colors.green);
      } else {
        context.showSnackBar('Kết nối lại thất bại. Hãy scan lại.', backgroundColor: Colors.red);
      }
    } catch (e) {
      context.showSnackBar('Lỗi kết nối: $e', backgroundColor: Colors.red);
    }
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
    final image = await _loadImageFromAssets(
      "packages/printer_label/images/ticket.png",
    );
    await PrinterLabel.printAll(
      escModel: PrintThermalModel(image: image, size: TicketSize.mm80),
    );
  }

  Future<void> _checkPrinterStatus({required String ipAddress}) async {
    setState(() => isCheckingStatus = true);
    context.showSnackBar('Đang kiểm tra máy in...', backgroundColor: Colors.blueGrey);
    try {
      // 1. Thử check theo giao thức ESC/POS trước
      var status = await PrinterLabel.checkPrinterStatus(
        deviceId: DeviceId.lan(ipAddress),
        type: "ESC",
      );

      // 2. Nếu trả về UNKNOWN (do timeout / không phải máy ESC), thử sang TSPL
      if (status == PrinterStatus.unknown) {
        status = await PrinterLabel.checkPrinterStatus(
          deviceId: DeviceId.lan(ipAddress),
          type: "TSPL",
        );
      }

      if (!mounted) return;
      final (msg, color) = switch (status) {
        PrinterStatus.normal => ('Máy in bình thường ✅', const Color(0xFF10B981)),
        PrinterStatus.outOfPaper => ('Hết giấy 📄', const Color(0xFFF59E0B)),
        PrinterStatus.paperJam => ('Kẹt giấy ⚠️', Colors.orange),
        PrinterStatus.headOpened => ('Đầu in đang mở 🔓', Colors.orange),
        PrinterStatus.outOfRibbon => ('Hết ruy băng mực 🎞️', Colors.orange),
        PrinterStatus.pause => ('Máy in đang tạm dừng ⏸️', Colors.blueGrey),
        PrinterStatus.printing => ('Đang in... 🖨️', const Color(0xFF4F46E5)),
        PrinterStatus.offline => ('Máy in không phản hồi ❌', const Color(0xFFE11D48)),
        PrinterStatus.unknown => ('Không xác định được trạng thái ❓', Colors.grey),
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
    await LabelPrintService.instance.printLabels<ProductBarcodeModel>(
      items: items,
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
              onPrintDeviceEsc: (device) => _printExampleESC(device.id),
              onCheckPrinterStatus: isConnected
                  ? () => _checkPrinterStatus(
                        ipAddress: textEditingController.text,
                      )
                  : null,
              onShowSavedBt: _showSavedBtPicker,
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

  Future<Uint8List> _loadImageFromAssets(String path) async {
    final byteData = await DefaultAssetBundle.of(context).load(path);
    return byteData.buffer.asUint8List();
  }

  Future<void> _printExampleESC(String deviceId) async {
    final image = await _loadImageFromAssets("packages/printer_label/images/ticket.png");
    await ESCPrintService.instance.print(
      deviceId: deviceId,
      model: PrintThermalModel(image: image, size: TicketSize.mm58),
    );
  }
}

// ⭐ Saved BT Picker bottom sheet — chọn máy in đã lưu để reconnect
class _SavedBtPicker extends StatefulWidget {
  final List<_SavedBtDevice> devices;
  final void Function(_SavedBtDevice device) onConnect;
  final void Function(_SavedBtDevice device) onDelete;

  const _SavedBtPicker({
    required this.devices,
    required this.onConnect,
    required this.onDelete,
  });

  @override
  State<_SavedBtPicker> createState() => _SavedBtPickerState();
}

class _SavedBtPickerState extends State<_SavedBtPicker> {
  final Set<String> _connecting = {};

  Future<void> _connect(_SavedBtDevice device) async {
    setState(() => _connecting.add(device.id));
    try {
      widget.onConnect(device);
    } finally {
      if (mounted) setState(() => _connecting.remove(device.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.4,
      minChildSize: 0.3,
      maxChildSize: 0.7,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.history, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Máy in đã lưu',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '${widget.devices.length} thiết bị',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.devices.isEmpty
                ? const Center(child: Text('Chưa có thiết bị nào được lưu'))
                : ListView.builder(
                    controller: controller,
                    itemCount: widget.devices.length,
                    itemBuilder: (_, i) {
                      final d = widget.devices[i];
                      final isConnecting = _connecting.contains(d.id);
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              Colors.indigo.withValues(alpha: 0.12),
                          child: const Icon(Icons.bluetooth_rounded,
                              color: Colors.indigo, size: 18),
                        ),
                        title: Text(
                          d.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          d.id,
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red, size: 20),
                              tooltip: 'Xóa khỏi danh sách',
                              onPressed: () => widget.onDelete(d),
                            ),
                            if (isConnecting)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: () => _connect(d),
                                icon:
                                    const Icon(Icons.wifi_tethering, size: 16),
                                label: const Text('Kết nối'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
