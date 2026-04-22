import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printer_label/src.dart';

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  final List<BluetoothDeviceModel> _devices = [];

  /// MACs của các thiết bị đang được kết nối thành công
  final Set<String> _connectedMacs = {};

  StreamSubscription<BluetoothDeviceModel>? _scanSubscription;
  bool _isScanning = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _cancelScan();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid) return true;
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> _init() async {
    final granted = await _requestPermissions();
    if (!granted) {
      setState(() =>
          _errorMessage = "Cần cấp đầy đủ quyền Bluetooth để quét thiết bị");
      return;
    }
    await _loadPairedDevices();
    _startScan();
  }

  Future<void> _loadPairedDevices() async {
    try {
      final paired = await PrinterLabel.getBluetoothDevices();
      setState(() {
        for (final d in paired) {
          if (!_devices.any((e) => e.mac == d.mac)) _devices.add(d);
        }
      });
    } catch (_) {}
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });
    _scanSubscription = PrinterLabel.bluetoothScanStream.listen(
      (device) {
        if (_devices.any((d) => d.mac == device.mac)) return;
        setState(() => _devices.add(device));
      },
      onError: (e) => setState(() {
        _errorMessage = e.toString();
        _isScanning = false;
      }),
      onDone: () => setState(() => _isScanning = false),
    );
  }

  void _cancelScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<void> _refresh() async {
    _cancelScan();
    setState(() {
      _devices.clear();
      _connectedMacs.clear();
      _isScanning = false;
      _errorMessage = null;
    });
    await _loadPairedDevices();
    _startScan();
  }

  Future<void> _connectDevice(BluetoothDeviceModel device) async {
    _cancelScan();
    await Future.delayed(const Duration(milliseconds: 500));

    final ok = await PrinterLabel.connectBluetooth(macAddress: device.mac);
    if (!mounted) return;

    setState(() {
      if (ok) {
        _connectedMacs.add(device.mac);
      } else {
        _connectedMacs.remove(device.mac);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? "Đã kết nối: ${device.name}" : "Kết nối thất bại"),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
  }

  /// In thử đến tất cả thiết bị đang connected (dùng deviceId để chính xác)
  Future<void> _printSample() async {
    if (_connectedMacs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Chưa kết nối thiết bị nào. Nhấn vào thiết bị để kết nối."),
      ));
      return;
    }

    for (final mac in _connectedMacs) {
      try {
        await ESCPrintService.instance.printExample(deviceId: mac);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Lỗi in $mac: $e"),
          backgroundColor: Colors.red,
        ));
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Đã gửi lệnh in"),
      backgroundColor: Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chọn máy in Bluetooth"),
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      floatingActionButton: _connectedMacs.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _printSample,
              icon: const Icon(Icons.print),
              label: Text("In thử (${_connectedMacs.length})"),
            )
          : null,
      body: _errorMessage != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_errorMessage!,
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _refresh, child: const Text("Thử lại")),
                ],
              ),
            )
          : _devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isScanning) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        const Text("Đang tìm kiếm thiết bị..."),
                      ] else ...[
                        const Text("Không tìm thấy thiết bị nào"),
                        const SizedBox(height: 12),
                        ElevatedButton(
                            onPressed: _refresh,
                            child: const Text("Quét lại")),
                      ]
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (_, i) {
                    final d = _devices[i];
                    final isConnected = _connectedMacs.contains(d.mac);
                    return ListTile(
                      leading: Icon(
                        Icons.bluetooth,
                        color: isConnected ? Colors.blue : Colors.grey,
                      ),
                      title: Text(d.name),
                      subtitle: Text(d.mac),
                      trailing: isConnected
                          ? const Icon(Icons.check_circle,
                              color: Colors.green, size: 20)
                          : null,
                      onTap: () => _connectDevice(d),
                    );
                  },
                ),
    );
  }
}
