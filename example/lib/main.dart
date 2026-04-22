import 'dart:async';
import 'dart:io';

import 'package:example/printer_screen.dart';
import 'package:example/select_size.dart';
import 'package:example/select_type_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printer_label/src.dart';
import 'preview_image_printer.dart';

void main() {
  runApp(const MyApp());
}

enum _PrintAction { lan, all, esc }

// ── Model thiết bị đã kết nối ────────────────────────────────────────────────
class _ConnectedDevice {
  final String id; // USB path | IP | MAC
  final String label; // tên hiển thị
  final String type; // 'USB' | 'LAN' | 'BT'
  const _ConnectedDevice({
    required this.id,
    required this.label,
    required this.type,
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter example printer',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: MyHomePage(),
    );
  }
}

// ignore: must_be_immutable
class MyHomePage extends StatefulWidget {
  MyHomePage({super.key});
  bool isConnected = false;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final String image1 = "images/image1.png";
  final String image2 = "images/image2.png";
  final String imageBarCode = "images/barcode.png";

  List<Uint8List> productImages = [];

  final TextEditingController textEditingController =
      TextEditingController(text: "192.168.1.56");
  FocusNode focusNode = FocusNode();

  final List<ProductBarcodeModel> products = [];
  LabelPerRow _selectedRow = LabelPerRow.single;

  // ── Danh sách thiết bị đã kết nối ────────────────────────────────────────
  final List<_ConnectedDevice> _connectedDevices = [];
  StreamSubscription<UsbConnectionEvent>? _usbSub;

  @override
  void initState() {
    super.initState();
    checkConnectPrint(deviceId: textEditingController.text);
    addProducts();
    _listenUsb();
  }

  @override
  void dispose() {
    _usbSub?.cancel();
    super.dispose();
  }

  // ── USB auto-detect ───────────────────────────────────────────────────────
  void _listenUsb() {
    _usbSub = PrinterLabel.usbDeviceStream.listen((event) {
      if (!mounted) return;
      setState(() {
        if (event.connected) {
          if (_connectedDevices.any((d) => d.id == event.deviceId)) return;
          _connectedDevices.add(_ConnectedDevice(
            id: event.deviceId,
            label: 'USB: ${event.deviceId.split('/').last}',
            type: 'USB',
          ));
        } else {
          _connectedDevices.removeWhere((d) => d.id == event.deviceId);
        }
      });
    });
  }

  // ── Kết nối Bluetooth ─────────────────────────────────────────────────────
  Future<void> _showAddBluetooth() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.locationWhenInUse,
      ].request();
      if (!statuses.values.every((s) => s.isGranted)) {
        if (!mounted) return;
        _showSnack('Cần cấp quyền Bluetooth', Colors.orange);
        return;
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _BtPicker(
        onConnected: (device) {
          if (!mounted) return;
          setState(() {
            _connectedDevices.removeWhere((d) => d.id == device.mac);
            _connectedDevices.add(_ConnectedDevice(
              id: device.mac,
              label: '${device.name} (BT)',
              type: 'BT',
            ));
          });
          _showSnack(
            'Kết nối Bluetooth thành công: ${device.name}',
            Colors.green,
          );
        },
      ),
    );
  }

  // ── Capture label images helper ──────────────────────────────────────────
  Future<LabelModel?> _buildLabelModel() async {
    final images = await LabelFromWidget.captureImages<ProductBarcodeModel>(
      products,
      context,
      labelPerRow: _selectedRow,
      itemBuilder: _buildBarcodeLabel,
      quantity: (p) => p.quantity,
    );
    if (images.isEmpty) return null;
    return LabelModel(images: images, labelPerRow: _selectedRow);
  }

  // ── In Label tất cả thiết bị LAN ─────────────────────────────────────────
  Future<void> _printAllLan() async {
    if (!_connectedDevices.any((d) => d.type == 'LAN')) {
      _showSnack('Không có máy LAN nào đang kết nối', Colors.orange);
      return;
    }
    final model = await _buildLabelModel();
    if (model == null) return;
    await PrinterLabel.printAll(
      labelModel: model,
      connectionType: PrinterConnectionType.LAN,
    );
  }

  // ── In Label tất cả thiết bị đã kết nối ──────────────────────────────────
  Future<void> _printAll() async {
    if (_connectedDevices.isEmpty) {
      _showSnack('Chưa có thiết bị nào kết nối', Colors.orange);
      return;
    }
    final model = await _buildLabelModel();
    if (model == null) return;
    await PrinterLabel.printAll(labelModel: model);
  }

  // ── In ESC tất cả thiết bị đã kết nối ────────────────────────────────────
  Future<void> _printAllEsc() async {
    if (_connectedDevices.isEmpty) {
      _showSnack('Chưa có thiết bị nào kết nối', Colors.orange);
      return;
    }
    final image = await ESCPrintService.instance.loadImageFromAssets(
      "packages/printer_label/images/ticket.png",
    );
    await PrinterLabel.printAll(
      escModel: PrintThermalModel(image: image, size: TicketSize.mm80),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
    ));
  }

  void addProducts() {
    products.clear();
    products.addAll([
      ProductBarcodeModel(
        barcode: "83868888",
        name: "iPhone 17 Pro Max",
        price: 28990000,
        quantity: 1,
      ),
      // ProductBarcodeModel(
      //   barcode: "56782123931231",
      //   name: "iPad Pro",
      //   price: 34980000,
      //   quantity: 5,
      // ),
      // ProductBarcodeModel(
      //   barcode: "56789345233",
      //   name: "Apple Pencil",
      //   price: 2350000,
      //   quantity: 2,
      // ),
      // ProductBarcodeModel(
      //   barcode: "1234543234",
      //   name: "MacBook Pro",
      //   price: 6589000,
      //   quantity: 3,
      // )
    ]);
  }

  Widget _buildBarcodeLabel(
    ProductBarcodeModel product,
    Dimensions dimensions,
  ) {
    return BarcodeView<ProductBarcodeModel>(
      data: product,
      dimensions: dimensions,
      nameBuilder: (p) => p.name,
      barcodeBuilder: (p) => p.barcode,
      priceBuilder: (p) => p.price,
    );
  }

  Future<void> generateLabelImages({
    required LabelPerRow labelPerRow,
  }) async {
    final images = await LabelFromWidget.captureImages<ProductBarcodeModel>(
      products,
      context,
      labelPerRow: labelPerRow,
      itemBuilder: _buildBarcodeLabel,
      quantity: (p) => p.quantity,
    );

    productImages
      ..clear()
      ..addAll(images);
  }

  Future<void> checkConnectPrint({required String deviceId}) async {
    final isConnected = await PrinterLabel.checkConnect(deviceId: deviceId);
    setState(() {
      widget.isConnected = isConnected;
    });
  }

  Future<void> printLabels() async {
    await LabelPrintService.instance.printLabels<ProductBarcodeModel>(
      items: products,
      context: context,
      deviceId: textEditingController.text,
      labelPerRow: _selectedRow,
      itemBuilder: _buildBarcodeLabel,
      quantity: (p) => p.quantity,
    );
  }

  Future<void> connect() async {
    final input = textEditingController.text.replaceAll(',', '.');
    final bool ok = await PrinterLabel.connectLan(ipAddress: input);
    if (!mounted) return;
    setState(() {
      widget.isConnected = ok;
      if (ok) {
        _connectedDevices.removeWhere((d) => d.id == input);
        _connectedDevices.add(_ConnectedDevice(
          id: input,
          label: 'LAN: $input',
          type: 'LAN',
        ));
      }
    });
    focusNode.unfocus();
    _showSnack(
      ok ? 'Kết nối LAN thành công: $input' : 'Kết nối LAN thất bại',
      ok ? Colors.green : Colors.red,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Printer label"),
      ),
      body: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            padding(),
            _buildButtonConnect(),
            padding(),
            TextField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: const InputDecoration(
                hintText: 'Enter IP',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ), // nếu IP, nhập số và dấu .
            ),
            padding(),
            ElevatedButton(
              onPressed: () async => await connect(),
              child: const Text(
                "Connect Lan",
              ),
            ),
            padding(),
            ElevatedButton(
              onPressed: () async {
                final disconnect = await PrinterLabel.disconectPrinter();

                setState(() {
                  widget.isConnected = !disconnect;
                });
              },
              child: const Text(
                "Disconnect printer",
              ),
            ),
            padding(),
            const Text("Print single label"),
            Card(
              elevation: 2,
              child: BarcodeView<ProductBarcodeModel>(
                data: products.first,
                nameBuilder: (p) => p.name,
                barcodeBuilder: (p) => p.barcode,
                priceBuilder: (p) => p.price,
              ),
            ),
            padding(),
            _buildPrintBarcode(deviceId: textEditingController.text),
            padding(),
            _buildPrintMultilLabel(),
            padding(),
            _viewListImage(),
            padding(),
            _viewCupSticker(),
            padding(),
            ElevatedButton(
              onPressed: () async {
                await ESCPrintService.instance
                    .printExample(deviceId: textEditingController.text);
              },
              child: const Text(
                "Print ESC",
              ),
            ),
            padding(),
            _printCupSticket(deviceId: textEditingController.text),
            padding(),
            padding(),
            ElevatedButton(
              onPressed: () async {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrinterScreen(),
                  ),
                );
              },
              child: const Text(
                "Print Bluetooth",
              ),
            ),
            // ── Danh sách thiết bị đã kết nối ──────────────────────────────
            padding(),
            const Divider(),
            _buildConnectedDevicesSection(),
            padding(),
            padding(),
          ],
        ),
      ),
    );
  }

  // ── Section: danh sách thiết bị đã kết nối ───────────────────────────────
  Widget _buildConnectedDevicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Thiết bị đã kết nối',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const Spacer(),
            IconButton(
              onPressed: _showAddBluetooth,
              icon: const Icon(Icons.bluetooth_rounded),
              tooltip: 'Thêm Bluetooth',
            ),
            PopupMenuButton<_PrintAction>(
              icon: const Icon(Icons.print_rounded),
              tooltip: 'In',
              enabled: _connectedDevices.isNotEmpty,
              onSelected: (action) async {
                switch (action) {
                  case _PrintAction.lan:
                    await _printAllLan();
                  case _PrintAction.all:
                    await _printAll();
                  case _PrintAction.esc:
                    await _printAllEsc();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _PrintAction.lan,
                  enabled: _connectedDevices.any((d) => d.type == 'LAN'),
                  child: const ListTile(
                    dense: true,
                    leading: Icon(Icons.lan_rounded),
                    title: Text('In tất cả LAN'),
                  ),
                ),
                const PopupMenuItem(
                  value: _PrintAction.all,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.print_rounded),
                    title: Text('In tất cả thiết bị'),
                  ),
                ),
                const PopupMenuItem(
                  value: _PrintAction.esc,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.receipt_long_rounded),
                    title: Text('In ESC tất cả'),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (_connectedDevices.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Chưa có thiết bị nào kết nối',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _connectedDevices.length,
            itemBuilder: (_, i) => _buildDeviceCard(_connectedDevices[i]),
          ),
      ],
    );
  }

  Widget _buildDeviceCard(_ConnectedDevice device) {
    final (IconData icon, Color color) = switch (device.type) {
      'USB' => (Icons.usb_rounded, Colors.teal),
      'LAN' => (Icons.lan_rounded, Colors.blue),
      'BT' => (Icons.bluetooth_rounded, Colors.indigo),
      _ => (Icons.device_unknown, Colors.grey),
    };
    return Card(
      elevation: 1,
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(
          device.label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          device.id,
          style: const TextStyle(fontSize: 10),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.print_rounded, size: 20),
              tooltip: 'In',
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'label', child: Text('In Label')),
                PopupMenuItem(value: 'barcode', child: Text('In Barcode')),
                PopupMenuItem(value: 'esc', child: Text('In ESC')),
              ],
              onSelected: (action) async {
                switch (action) {
                  case 'label':
                    await LabelPrintService.instance
                        .printLabels<ProductBarcodeModel>(
                      items: products,
                      context: context,
                      deviceId: device.id,
                      labelPerRow: _selectedRow,
                      itemBuilder: _buildBarcodeLabel,
                      quantity: (p) => p.quantity,
                    );
                  case 'barcode':
                    await PrinterLabel.printBarcode(
                      deviceId: device.id,
                      printBarcodeModel: BarcodeModel(
                        barcodeY: 60,
                        width: 300,
                        barcodeContent: '123456',
                        quantity: 1,
                        textData: [
                          TextData(y: 20, data: 'Hello printer label'),
                          TextData(y: 170, data: '30.000'),
                        ],
                      ),
                    );
                  case 'esc':
                    await ESCPrintService.instance
                        .printExample(deviceId: device.id);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.link_off, size: 18),
              color: Colors.red,
              tooltip: 'Ngắt kết nối',
              onPressed: () async {
                await PrinterLabel.disconectPrinter(deviceId: device.id);
                setState(() => _connectedDevices.remove(device));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget padding() {
    return const Padding(padding: EdgeInsets.all(10));
  }

  Widget _buildPrintMultilLabel() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        LabelPerRowSelector(
          initialValue: LabelPerRow.single,
          onChanged: (label) {
            setState(() {
              _selectedRow = label;
            });
          },
        ),
        ElevatedButton(
          onPressed: printLabels,
          child: const Text(
            "Print multi label",
          ),
        )
      ],
    );
  }

  Widget _printCupSticket({required String deviceId}) {
    return CupStickerSizeSelector(
      onPrint: (select) => CupStickerPrintExample.printOrderCupSticker(
        select,
        context: context,
        deviceId: textEditingController.text,
      ),
    );
  }

  Widget _buildButtonConnect() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Connect Status"),
        Container(
          padding: const EdgeInsets.all(8),
          color: widget.isConnected ? Colors.green : Colors.red,
          child: Text(
            widget.isConnected ? "Connect success" : "Connect false",
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _viewListImage() {
    return ElevatedButton(
      onPressed: () async {
        addProducts();
        await generateLabelImages(
          labelPerRow: _selectedRow,
        );
        Navigator.push(
          // ignore: use_build_context_synchronously
          context,
          MaterialPageRoute(
            builder: (context) =>
                ImageDisplayScreen(imageBytesList: productImages),
          ),
        );
      },
      child: Text(
        "View list( ${products.map(
              (e) => e.quantity.toDouble(),
            ).reduce(
              (value, element) => value + element,
            )})",
      ),
    );
  }

  Widget _viewCupSticker() {
    return ElevatedButton(
      onPressed: () async {
        final image = await LabelFromWidget.captureFromWidget(
          PreviewCupSticker(
            data: PreviewLabelModel(
              code: "1213",
              productName: "Trà sữa",
              price: "27.000 đ",
              companyName: "Printer Label",
              note: "Test print",
              labelIndex: 1,
              billDate: "01/01/2026",
              totalLabels: 1,
              toppings: ["Đá", "Đường"],
            ),
          ),
          context: context,
        );

        Navigator.push(
          // ignore: use_build_context_synchronously
          context,
          MaterialPageRoute(
            builder: (context) => ImageDisplayScreen(imageBytesList: [image]),
          ),
        );
      },
      child: const Text(
        "View cup sticker",
      ),
    );
  }

  Widget _buildPrintBarcode({required String deviceId}) {
    return ElevatedButton(
      onPressed: () async {
        final List<TextData> textData = [
          TextData(
            y: 20,
            data: "Hello printer label",
          ),
          TextData(
            y: 170,
            data: "30.000",
          ),
          TextData(
            y: 200,
            data: "12345678",
          ),
        ];
        // Create an instance of PrintBarcodeModel
        final BarcodeModel printBarcodeModel = BarcodeModel(
          barcodeY: 60,
          width: 300,
          barcodeContent: "123456",
          textData: textData,
          quantity: 1,
        );
        await PrinterLabel.printBarcode(
            deviceId: deviceId, printBarcodeModel: printBarcodeModel);
      },
      child: const Text(
        "Print barcode",
      ),
    );
  }
}

// ── BT Picker bottom sheet ────────────────────────────────────────────────────
class _BtPicker extends StatefulWidget {
  final void Function(BluetoothDeviceModel device) onConnected;
  const _BtPicker({required this.onConnected});

  @override
  State<_BtPicker> createState() => _BtPickerState();
}

class _BtPickerState extends State<_BtPicker> {
  final List<BluetoothDeviceModel> _devices = [];
  final Set<String> _connecting = {};
  StreamSubscription<BluetoothDeviceModel>? _scanSub;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadPaired();
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPaired() async {
    try {
      final paired = await PrinterLabel.getBluetoothDevices();
      if (!mounted) return;
      setState(() {
        for (final d in paired) {
          if (!_devices.any((e) => e.mac == d.mac)) _devices.add(d);
        }
      });
    } catch (_) {}
  }

  void _startScan() {
    setState(() => _scanning = true);
    _scanSub = PrinterLabel.bluetoothScanStream.listen(
      (d) {
        if (!mounted) return;
        setState(() {
          if (!_devices.any((e) => e.mac == d.mac)) _devices.add(d);
        });
      },
      onDone: () => mounted ? setState(() => _scanning = false) : null,
      onError: (_) => mounted ? setState(() => _scanning = false) : null,
    );
  }

  Future<void> _connect(BluetoothDeviceModel device) async {
    setState(() => _connecting.add(device.mac));
    try {
      final ok = await PrinterLabel.connectBluetooth(macAddress: device.mac);
      if (!mounted) return;
      if (ok) {
        widget.onConnected(device);
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Không thể kết nối ${device.name}'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _connecting.remove(device.mac));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
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
                const Text(
                  'Chọn thiết bị Bluetooth',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                if (_scanning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _devices.isEmpty
                ? const Center(child: Text('Không tìm thấy thiết bị'))
                : ListView.builder(
                    controller: controller,
                    itemCount: _devices.length,
                    itemBuilder: (_, i) {
                      final d = _devices[i];
                      final isConnecting = _connecting.contains(d.mac);
                      return ListTile(
                        leading: const Icon(Icons.bluetooth_rounded,
                            color: Colors.indigo),
                        title: Text(d.name),
                        subtitle:
                            Text(d.mac, style: const TextStyle(fontSize: 11)),
                        trailing: isConnecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: isConnecting ? null : () => _connect(d),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
