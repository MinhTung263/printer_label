import 'dart:async';
import 'dart:io';

import 'package:example/context_extensions.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

class BtPicker extends StatefulWidget {
  final List<String> connectedMacs;
  final void Function(BluetoothDeviceModel device) onConnected;

  const BtPicker({
    super.key,
    this.connectedMacs = const [],
    required this.onConnected,
  });

  @override
  State<BtPicker> createState() => _BtPickerState();
}

class _BtPickerState extends State<BtPicker> {
  final List<BluetoothDeviceModel> _pairedDevices = [];
  final List<BluetoothDeviceModel> _scannedDevices = [];
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
        _pairedDevices.clear();
        for (final d in paired) {
          if (!_pairedDevices.any((e) => e.mac == d.mac)) {
            _pairedDevices.add(d);
          }
        }
      });
    } catch (_) {}
  }

  void _startScan() async {
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _scannedDevices.clear();
    });
    _scanSub?.cancel();
    _scanSub = PrinterLabel.bluetoothScanStream.listen(
      (d) {
        if (!mounted) return;
        setState(() {
          // Tránh trùng với thiết bị đã ghép đôi hoặc thiết bị đã quét được
          final existsInPaired = _pairedDevices.any((e) => e.mac == d.mac);
          final existsInScanned = _scannedDevices.any((e) => e.mac == d.mac);
          if (!existsInPaired && !existsInScanned) {
            _scannedDevices.add(d);
          }
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

  void _stopScan() async {
    _scanSub?.cancel();
    if (Platform.isIOS) {
      await PrinterLabel.stopBluetoothScan();
    }
    if (mounted) {
      setState(() => _scanning = false);
    }
  }

  Future<void> _connect(BluetoothDeviceModel device) async {
    if (!mounted) return;
    if (widget.connectedMacs.contains(device.mac)) {
      context.showSnackBar('Thiết bị này đã được kết nối');
      return;
    }
    setState(() => _connecting.add(device.mac));
    // Dừng quét khi đang kết nối để tăng tính ổn định
    _stopScan();
    
    try {
      final ok = await PrinterLabel.connectBluetooth(macAddress: device.mac);
      if (!mounted) return;
      if (ok) {
        widget.onConnected(device);
        Navigator.pop(context);
      } else {
        context.showSnackBar(
          'Không thể kết nối ${device.name.isEmpty ? 'máy in' : device.name}',
          backgroundColor: const Color(0xFFF43F5E),
        );
        // Quét lại nếu kết nối lỗi
        _startScan();
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Lỗi kết nối: $e', backgroundColor: const Color(0xFFF43F5E));
        _startScan();
      }
    } finally {
      if (mounted) setState(() => _connecting.remove(device.mac));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
                    'Kết nối máy in Bluetooth',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  if (_scanning)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      _scanning ? Icons.stop_circle_outlined : Icons.refresh,
                      color: const Color(0xFF4F46E5),
                    ),
                    onPressed: _scanning ? _stopScan : _startScan,
                    tooltip: _scanning ? 'Dừng quét' : 'Quét lại',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  if (_pairedDevices.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'THIẾT BỊ ĐÃ GHÉP ĐÔI',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ..._pairedDevices.map((d) => _buildDeviceItem(d, isPaired: true)),
                    const SizedBox(height: 16),
                  ],
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'THIẾT BỊ KHẢ DỤNG XUNG QUANH',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (_scannedDevices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.bluetooth_searching,
                              size: 40,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _scanning
                                  ? 'Đang tìm kiếm máy in...'
                                  : 'Không tìm thấy thiết bị nào. Bấm nút quét để thử lại.',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._scannedDevices.map((d) => _buildDeviceItem(d, isPaired: false)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceItem(BluetoothDeviceModel d, {required bool isPaired}) {
    final isConnecting = _connecting.contains(d.mac);
    final isAlreadyConnected = widget.connectedMacs.contains(d.mac);

    return Card(
      elevation: 0,
      color: isAlreadyConnected ? const Color(0xFFF0FDF4) : Colors.grey.shade50,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isAlreadyConnected
              ? const Color(0xFFDCFCE7)
              : Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isAlreadyConnected
              ? const Color(0xFFDCFCE7)
              : const Color(0xFFEEF2FF),
          child: Icon(
            Icons.print,
            color: isAlreadyConnected ? const Color(0xFF16A34A) : const Color(0xFF6366F1),
          ),
        ),
        title: Text(
          d.name.isEmpty ? "Máy in không tên" : d.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isAlreadyConnected ? const Color(0xFF14532D) : Colors.black87,
          ),
        ),
        subtitle: Text(
          d.mac,
          style: TextStyle(
            fontSize: 11,
            color: isAlreadyConnected ? const Color(0xFF166534) : const Color(0xFF64748B),
          ),
        ),
        trailing: isConnecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4F46E5),
                ),
              )
            : isAlreadyConnected
                ? const Icon(Icons.check_circle, color: Color(0xFF16A34A))
                : const Icon(Icons.link, color: Color(0xFF4F46E5)),
        onTap: (isConnecting || isAlreadyConnected) ? null : () => _connect(d),
      ),
    );
  }
}
