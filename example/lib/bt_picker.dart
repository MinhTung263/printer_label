import 'dart:async';
import 'dart:io';

import 'package:example/context_extensions.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class BtPicker extends StatefulWidget {
  final void Function(BluetoothDeviceModel device) onConnected;
  const BtPicker({super.key, required this.onConnected});

  @override
  State<BtPicker> createState() => _BtPickerState();
}

class _BtPickerState extends State<BtPicker> {
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
    if (Platform.isIOS) {
      PrinterLabel.stopBluetoothScan();
    }
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

  void _startScan() async {
    if (!mounted) return;
    setState(() => _scanning = true);
    _scanSub?.cancel();
    _scanSub = PrinterLabel.bluetoothScanStream.listen(
      (d) {
        if (!mounted) return;
        setState(() {
          if (!_devices.any((e) => e.mac == d.mac)) _devices.add(d);
        });
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (_) {
        if (mounted) setState(() => _scanning = false);
      },
    );
    if (Platform.isIOS) {
      await PrinterLabel.startBluetoothScan();
    }
  }

  Future<void> _connect(BluetoothDeviceModel device) async {
    if (!mounted) return;
    setState(() => _connecting.add(device.mac));
    try {
      final ok = await PrinterLabel.connectBluetooth(macAddress: device.mac);
      if (!mounted) return;
      if (ok) {
        widget.onConnected(device);
        Navigator.pop(context);
      } else {
        context.showSnackBar(
          'Không thể kết nối ${device.name}',
          backgroundColor: const Color(0xFFF43F5E),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting.remove(device.mac));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _devices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bluetooth_searching, size: 40, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          const Text(
                            'Đang tìm kiếm thiết bị...',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _devices.length,
                      itemBuilder: (_, i) {
                        final d = _devices[i];
                        final isConnecting = _connecting.contains(d.mac);
                        return Card(
                          elevation: 0,
                          color: Colors.grey.shade50,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFEEF2FF),
                              child: Icon(Icons.bluetooth, color: Color(0xFF6366F1)),
                            ),
                            title: Text(
                              d.name.isEmpty ? "Thiết bị không tên" : d.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Text(d.mac, style: const TextStyle(fontSize: 11)),
                            trailing: isConnecting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)),
                                  )
                                : const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: isConnecting ? null : () => _connect(d),
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
