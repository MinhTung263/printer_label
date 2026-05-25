import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printer_label/src.dart';

/// Màn hình test BLE CoreBluetooth độc lập.
/// Không phụ thuộc vào các màn hình khác.
/// Flow: Scan → Discover → Connect → Print test
class BleScanScreen extends StatefulWidget {
  const BleScanScreen({super.key});

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  // Devices được discover qua EventChannel
  final List<BluetoothDeviceModel> _discovered = [];

  // identifier (UUID trên iOS) → trạng thái kết nối
  final Map<String, _ConnState> _connState = {};

  StreamSubscription<BluetoothDeviceModel>? _scanSub;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) _beginScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    if (Platform.isIOS) PrinterLabel.stopBluetoothScan();
    super.dispose();
  }

  // MARK: - Scan

  Future<void> _beginScan() async {
    if (_scanning) return;

    setState(() {
      _scanning = true;
      _discovered.clear();
    });

    // Subscribe stream TRƯỚC khi gọi startScan — đảm bảo sink sẵn sàng
    // trước khi CBCentralManager bắt đầu báo cáo thiết bị
    _scanSub?.cancel();
    _scanSub = PrinterLabel.bluetoothScanStream.listen(
      (device) {
        if (!mounted) return;
        setState(() {
          final exists =
              _discovered.any((d) => d.identifier == device.identifier);
          if (!exists) _discovered.add(device);
        });
      },
      onError: (_) => mounted ? setState(() => _scanning = false) : null,
      onDone: () => mounted ? setState(() => _scanning = false) : null,
    );

    if (Platform.isIOS) {
      final ok = await PrinterLabel.startBluetoothScan();
      if (!ok && mounted) {
        setState(() => _scanning = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bluetooth bị từ chối quyền. Vào Settings → Privacy → Bluetooth để bật lại.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ));
      }
    }
  }

  Future<void> _stopScan() async {
    _scanSub?.cancel();
    _scanSub = null;
    if (Platform.isIOS) await PrinterLabel.stopBluetoothScan();
    if (mounted) setState(() => _scanning = false);
  }

  // MARK: - Connect / Disconnect

  Future<void> _connect(BluetoothDeviceModel device) async {
    final id = device.identifier;
    setState(() => _connState[id] = _ConnState.connecting);

    // connectBluetooth trên iOS nhận UUID identifier, không phải MAC
    final ok = await PrinterLabel.connectBluetooth(macAddress: id);
    if (!mounted) return;

    setState(() => _connState[id] = ok ? _ConnState.connected : _ConnState.failed);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Không thể kết nối ${device.name}'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _disconnect(BluetoothDeviceModel device) async {
    final id = device.identifier;
    setState(() => _connState[id] = _ConnState.disconnecting);

    // deviceId dùng prefix BT: để plugin biết đây là BLE disconnect
    await PrinterLabel.disconectPrinter(
      deviceId: DeviceId.bluetooth(id),
    );
    if (!mounted) return;
    setState(() => _connState.remove(id));
  }

  // MARK: - Print Test

  Future<void> _printTest(BluetoothDeviceModel device) async {
    final id = device.identifier;
    if (_connState[id] != _ConnState.connected) return;

    try {
      // In ảnh test qua BLE — dùng ESC/POS
      final image = await ESCPrintService.instance.loadImageFromAssets(
        "packages/printer_label/images/ticket.png",
      );
      await PrinterLabel.printESC(
        deviceId: DeviceId.bluetooth(id),   // "BT:<UUID>"
        connectionType: PrinterConnectionType.BT,
        printThermalModel: PrintThermalModel(
          image: image,
          size: TicketSize.mm80,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Đã gửi lệnh in tới ${device.name}'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Lỗi in: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  // MARK: - Build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner (iOS CoreBluetooth)'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_scanning)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Dừng scan',
              onPressed: _stopScan,
            )
          else
            IconButton(
              icon: const Icon(Icons.bluetooth_searching),
              tooltip: 'Scan lại',
              onPressed: _beginScan,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          Expanded(
            child: _discovered.isEmpty
                ? _buildEmpty()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _discovered.length + (_scanning ? 1 : 0),
                    separatorBuilder: (_, i) => i < _discovered.length - 1
                        ? const Divider(height: 1, indent: 72)
                        : const SizedBox.shrink(),
                    itemBuilder: (_, i) {
                      // Hiển thị loading indicator ở cuối
                      if (i == _discovered.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.indigo,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Đang tìm thêm thiết bị...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return _buildDeviceTile(_discovered[i]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      color: Colors.indigo.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (_scanning) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Đang scan...',
              style: TextStyle(color: Colors.indigo, fontSize: 13),
            ),
          ] else
            const Text(
              'Scan đã dừng',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          const Spacer(),
          Text(
            '${_discovered.length} thiết bị',
            style: const TextStyle(
                color: Colors.indigo,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            _scanning
                ? 'Đang tìm kiếm thiết bị BLE...'
                : 'Không tìm thấy thiết bị.\nNhấn icon bluetooth để scan lại.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(BluetoothDeviceModel device) {
    final id = device.identifier;
    final state = _connState[id] ?? _ConnState.idle;
    final isConnected = state == _ConnState.connected;
    final isBusy =
        state == _ConnState.connecting || state == _ConnState.disconnecting;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            isConnected ? Colors.indigo.shade100 : Colors.grey.shade100,
        child: Icon(
          isConnected ? Icons.bluetooth_connected : Icons.bluetooth_rounded,
          color: isConnected ? Colors.indigo : Colors.blueGrey,
          size: 22,
        ),
      ),
      title: Text(
        device.name,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            id,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
          if (state != _ConnState.idle)
            Text(
              _stateLabel(state),
              style: TextStyle(
                fontSize: 11,
                color: _stateColor(state),
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      isThreeLine: state != _ConnState.idle,
      trailing: isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isConnected)
                  IconButton(
                    icon: const Icon(Icons.print_rounded, size: 20),
                    color: Colors.indigo,
                    tooltip: 'In test',
                    onPressed: () => _printTest(device),
                  ),
                isConnected
                    ? IconButton(
                        icon: const Icon(Icons.link_off_rounded, size: 20),
                        color: Colors.red,
                        tooltip: 'Ngắt kết nối',
                        onPressed: () => _disconnect(device),
                      )
                    : TextButton(
                        onPressed: () => _connect(device),
                        child: const Text('Kết nối'),
                      ),
              ],
            ),
    );
  }

  String _stateLabel(_ConnState s) => switch (s) {
        _ConnState.connecting => 'Đang kết nối...',
        _ConnState.connected => 'Đã kết nối',
        _ConnState.disconnecting => 'Đang ngắt...',
        _ConnState.failed => 'Kết nối thất bại',
        _ConnState.idle => '',
      };

  Color _stateColor(_ConnState s) => switch (s) {
        _ConnState.connected => Colors.green,
        _ConnState.failed => Colors.red,
        _ => Colors.orange,
      };
}

enum _ConnState { idle, connecting, connected, disconnecting, failed }
