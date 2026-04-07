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

    // locationWhenInUse bắt buộc trên Android < 12 để startDiscovery() trả kết quả
    // Trên Android 12+ hệ thống tự bỏ qua nếu không cần
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
    // Load paired devices trước để hiển thị ngay
    await _loadPairedDevices();
    // Sau đó scan để tìm thêm
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
      _isScanning = false;
      _errorMessage = null;
    });
    await _loadPairedDevices();
    _startScan();
  }

  Future<void> _connectDevice(BluetoothDeviceModel device) async {
    _cancelScan();
    // Đợi cancelDiscovery() hoàn tất trước khi connect
    await Future.delayed(const Duration(milliseconds: 500));

    final ok = await PrinterLabel.connectBluetooth(macAddress: device.mac);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? "Đã kết nối: ${device.name}" : "Kết nối thất bại"),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chọn máy in"),
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
      floatingActionButton: ElevatedButton(
          onPressed: () async {
            await ESCPrintService.instance.printExample();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: const Text(
              "In thử đê",
              style: TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          )),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
                            onPressed: _refresh, child: const Text("Quét lại")),
                      ]
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (_, i) {
                    final d = _devices[i];
                    return ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(d.name),
                      subtitle: Text(d.mac),
                      onTap: () => _connectDevice(d),
                    );
                  },
                ),
    );
  }
}
