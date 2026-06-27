import 'dart:async';
import 'dart:io';

import 'package:example/context_extensions.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printer_label/printer_label.dart';

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  final List<BluetoothDeviceModel> _devices = [];
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
      if (!mounted) return;
      setState(() {
        for (final d in paired) {
          if (!_devices.any((e) => e.mac == d.mac)) _devices.add(d);
        }
      });
    } catch (_) {}
  }

  void _startScan() {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });
    _scanSubscription?.cancel();
    _scanSubscription = PrinterLabel.bluetoothScanStream.listen(
      (device) {
        if (!mounted) return;
        if (_devices.any((d) => d.mac == device.mac)) return;
        setState(() => _devices.add(device));
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = e.toString();
          _isScanning = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isScanning = false);
      },
    );
  }

  void _cancelScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<void> _refresh() async {
    _cancelScan();
    if (!mounted) return;
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
    await Future.delayed(const Duration(milliseconds: 300));

    // Check if already connected
    final bool isConnected =
        await PrinterLabel.checkConnect(deviceId: DeviceId.bluetooth(device.mac));
    if (!mounted) return;
    if (isConnected) {
      setState(() => _connectedMacs.add(device.mac));
      context.showSnackBar(
        "Thiết bị ${device.name} đã kết nối từ trước",
        backgroundColor: const Color(0xFFD97706),
      );
      return;
    }

    context.showSnackBar("Đang kết nối tới ${device.name}...");

    final ok = await PrinterLabel.connectBluetooth(macAddress: device.mac);
    if (!mounted) return;

    setState(() {
      if (ok) {
        _connectedMacs.add(device.mac);
      } else {
        _connectedMacs.remove(device.mac);
      }
    });

    context.showSnackBar(
      ok ? "Đã kết nối: ${device.name}" : "Kết nối thất bại",
      backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
    );
  }

  Future<void> _printSample() async {
    if (_connectedMacs.isEmpty) {
      context.showSnackBar("Chưa kết nối thiết bị nào. Chọn thiết bị để kết nối.");
      return;
    }

    for (final mac in _connectedMacs) {
      try {
        await ESCPrintService.instance.printExample(deviceId: DeviceId.bluetooth(mac));
      } catch (e) {
        if (!mounted) return;
        context.showSnackBar(
          "Lỗi in trên $mac: $e",
          backgroundColor: const Color(0xFFF43F5E),
        );
      }
    }

    if (!mounted) return;
    context.showSnackBar(
      "Đã gửi lệnh in thành công",
      backgroundColor: const Color(0xFF10B981),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          "Chọn máy in Bluetooth",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.indigo,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.indigo),
              onPressed: _refresh,
            ),
        ],
      ),
      floatingActionButton: _connectedMacs.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _printSample,
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.print),
              label: Text("In thử (${_connectedMacs.length})"),
            )
          : null,
      body: SafeArea(
        child: _errorMessage != null
            ? Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFF43F5E), size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _refresh,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text("Thử lại"),
                      ),
                    ],
                  ),
                ),
              )
            : _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isScanning) ...[
                          const CircularProgressIndicator(color: Colors.indigo),
                          const SizedBox(height: 16),
                          const Text(
                            "Đang tìm kiếm thiết bị...",
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                        ] else ...[
                          Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          const Text(
                            "Không tìm thấy thiết bị nào",
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.search),
                            label: const Text("Quét lại"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ]
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        width: double.infinity,
                        color: Colors.indigo.shade50,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              _isScanning ? Icons.search : Icons.bluetooth_audio,
                              size: 16,
                              color: Colors.indigo,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isScanning ? "Đang quét..." : "Quét đã dừng",
                              style: TextStyle(
                                color: Colors.indigo.shade800,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              "Đã tìm thấy ${_devices.length} thiết bị",
                              style: TextStyle(
                                color: Colors.indigo.shade800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _devices.length,
                          itemBuilder: (_, i) {
                            final d = _devices[i];
                            final isConnected = _connectedMacs.contains(d.mac);
                            return Card(
                              elevation: 0,
                              color: Colors.white,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isConnected
                                      ? Colors.indigo.withValues(alpha: 0.2)
                                      : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isConnected
                                      ? Colors.indigo.shade50
                                      : Colors.grey.shade50,
                                  child: Icon(
                                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                                    color: isConnected ? Colors.indigo : Colors.grey,
                                  ),
                                ),
                                title: Text(
                                  d.name.isEmpty ? "Thiết bị không tên" : d.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Text(
                                  d.mac,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                                trailing: isConnected
                                    ? const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24)
                                    : const Icon(Icons.chevron_right, color: Colors.grey),
                                onTap: () => _connectDevice(d),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
