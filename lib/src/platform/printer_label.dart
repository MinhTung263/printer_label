import 'dart:async';
import 'dart:io';

import '../src.dart';

enum BuiltInPrinterType {
  /// Không tìm thấy máy in tích hợp
  none(0),
  /// Máy in nhiệt khổ 58mm (K57)
  mm58(58),
  /// Máy in nhiệt khổ 80mm (K80)
  mm80(80);

  final int paperSize;
  const BuiltInPrinterType(this.paperSize);

  static BuiltInPrinterType fromPaperSize(int size) {
    if (size == 80) return BuiltInPrinterType.mm80;
    if (size == 58) return BuiltInPrinterType.mm58;
    return BuiltInPrinterType.none;
  }
}

PrinterLabelPlatform get _platform => PrinterLabelPlatform.instance;

/// Primary public class providing connections and print interfaces
/// for Flutter applications. Supports label (TSPL) and thermal receipt (ESC/POS)
/// printing via Bluetooth, LAN, or USB connections.
class PrinterLabel {
  /// Gets the platform operating system version string (Android/iOS).
  static Future<String?> get platformVersion => _platform.platformVersion;

  /// Checks if Bluetooth is currently enabled on the device.
  static Future<bool> bluetoothEnabled() => _platform.bluetoothEnabled();

  /// Checks the connection status of a specific printer by its [deviceId].
  ///
  /// If [deviceId] is null, checks if any printer connection is active.
  static Future<bool> checkConnect({String? deviceId}) async {
    return await _platform.checkConnect(deviceId: deviceId);
  }

  /// Queries the operational status of a specific printer by its [deviceId].
  ///
  /// Specify [type] as either "TSPL" or "ESC" to check specific protocols.
  /// Returns a [PrinterStatus] value.
  static Future<PrinterStatus> checkPrinterStatus({
    String? deviceId,
    String? type,
  }) async {
    return await _platform.checkPrinterStatus(deviceId: deviceId, type: type);
  }

  /// Gets a map of all currently active printer connections (only supported on Android).
  ///
  /// Returns a [Map] containing `deviceId` as keys and their connection states (`true`/`false`) as values.
  static Future<Map<String, bool>> getAllConnections() async {
    if (!Platform.isAndroid) return {};
    return await _platform.getAllConnections();
  }

  /// Disconnects a specific printer connection by [deviceId].
  ///
  /// If [deviceId] is null or empty, disconnects all active printer connections.
  static Future<bool> disconnectPrinter({String? deviceId}) async {
    return await _platform.disconnectPrinter(deviceId: deviceId);
  }

  /// [Deprecated] Use [disconnectPrinter] instead.
  @Deprecated('Use disconnectPrinter instead')
  static Future<bool> disconectPrinter({String? deviceId}) async {
    return await _platform.disconnectPrinter(deviceId: deviceId);
  }

  /// Connects to a network LAN printer using the specified [ipAddress].
  static Future<bool> connectLan({required String ipAddress}) async {
    return await _platform.connectLan(ipAddress: ipAddress);
  }

  /// Discovers LAN printers by scanning the local network for open port 9100.
  ///
  /// Returns a stream of IP addresses (e.g. '192.168.1.10') that have the port open.
  ///
  /// [timeout] is the per-IP TCP connect timeout. Printers on the same LAN normally
  /// answer well under 100ms, so the short default keeps a full /24 sweep fast.
  /// Raise it only for congested networks or printers behind a slow AP.
  static Stream<String> discoverLanPrinters({
    int port = 9100,
    Duration? timeout,
  }) {
    // ignore: close_sinks
    final controller = StreamController<String>();

    Future<List<String>> getLocalIps() async {
      List<String> validIps = [];
      // 3 lần thử là đủ để WiFi kịp cấp IP sau khi vừa bật; 5 lần chỉ thêm 1s chờ
      // vô ích khi thiết bị thực sự không có mạng LAN.
      for (int retry = 0; retry < 3; retry++) {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        validIps.clear();
        for (var interface in interfaces) {
          for (var address in interface.addresses) {
            final ip = address.address;
            bool isClassB = false;
            if (ip.startsWith('172.')) {
              final parts = ip.split('.');
              if (parts.length >= 2) {
                final secondOctet = int.tryParse(parts[1]) ?? 0;
                isClassB = secondOctet >= 16 && secondOctet <= 31;
              }
            }
            if (ip.startsWith('192.168.') || ip.startsWith('10.') || isClassB) {
              validIps.add(ip);
            }
          }
        }
        if (validIps.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      return validIps;
    }

    // IP đã phát ra stream — chặn trùng khi lần quét 2 chạy lại, và khi thiết bị có
    // nhiều interface cùng subnet (VD WiFi + VPN) làm subnet bị quét lặp.
    final Set<String> emitted = <String>{};

    Future<int> scanPass(List<String> validIps) async {
      int foundCount = 0;

      // Gộp theo subnet: hai IP cùng subnet (WiFi + hotspot/VPN) sẽ sinh cùng dải quét,
      // quét lặp chỉ làm chậm gấp đôi và tăng tải router — trên iOS còn kéo theo timeout.
      final Set<String> subnets = <String>{};
      for (var ip in validIps) {
        final parts = ip.split('.');
        if (parts.length != 4) continue;
        subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }

      final Set<String> ownIps = validIps.toSet();

      // Hàng đợi phẳng tất cả IP cần quét (mọi subnet gộp chung).
      final List<String> targets = <String>[];
      for (var subnet in subnets) {
        for (int j = 1; j < 255; j++) {
          final targetIp = '$subnet.$j';
          // IP của chính thiết bị — bỏ qua, không tự quét mình.
          if (ownIps.contains(targetIp)) continue;
          targets.add(targetIp);
        }
      }

      // Giới hạn số socket mở CÙNG LÚC để tránh nghẽn router (SYN flood) và tránh
      // đụng trần file descriptor trên iOS — nhưng KHÔNG chia batch có rào chắn.
      //
      // Batch + Future.wait khiến mỗi batch chậm bằng phần tử chậm nhất: 15 IP trả
      // lời trong 5ms vẫn phải chờ IP thứ 16 timeout đủ 1.5s. 16 batch x 1.5s = ~24s
      // dù mạng hoàn toàn khoẻ. Ở đây mỗi worker xong 1 IP là bốc IP kế tiếp ngay,
      // nên tổng thời gian ~ (số IP / số worker) x RTT thực, không x timeout.
      final bool isIOS = Platform.isIOS;
      final int concurrency = isIOS ? 24 : 48;
      // IP không tồn tại thường bị firewall drop (không có RST) -> luôn phải chờ hết
      // timeout. Giữ ngắn vì máy in trong cùng LAN gần như luôn trả lời dưới 100ms;
      // các IP chậm bất thường đã được lần quét 2 (auto retry) bọc lót.
      final connectTimeout = timeout ??
          (isIOS
              ? const Duration(milliseconds: 600)
              : const Duration(milliseconds: 400));

      int next = 0;
      Future<void> worker() async {
        while (true) {
          if (controller.isClosed) return;
          final index = next++;
          if (index >= targets.length) return;
          final targetIp = targets[index];
          try {
            final socket = await Socket.connect(
              targetIp,
              port,
              timeout: connectTimeout,
            );
            socket.destroy();
            // Chặn phát trùng: lần quét 2 chạy lại cùng dải, và nhiều interface
            // có thể sinh cùng subnet.
            if (!controller.isClosed && emitted.add(targetIp)) {
              foundCount++;
              controller.add(targetIp);
            }
          } catch (_) {
            // Ignore connection errors
          }
        }
      }

      await Future.wait(
        List.generate(
          concurrency < targets.length ? concurrency : targets.length,
          (_) => worker(),
        ),
      );
      return foundCount;
    }

    Future<void> runScan() async {
      try {
        // Lần quét 1
        List<String> currentIps = await getLocalIps();
        int found = await scanPass(currentIps);

        // Nếu không tìm thấy máy in nào, có thể do OS đang cache IP cũ hoặc ARP chưa cập nhật
        if (found == 0 && !controller.isClosed) {
          await Future.delayed(const Duration(milliseconds: 500)); // Chờ OS ổn định
          List<String> newIps = await getLocalIps();

          // Chỉ quét lại khi dải mạng thực sự khác lần 1. Nếu OS trả về đúng dải cũ
          // thì lần 1 đã quét hết dải đó — quét lại chỉ tốn thêm thời gian mà không
          // thể ra kết quả mới (trừ khi máy in vừa mới bật, hiếm).
          final before = currentIps.toSet();
          final changed = newIps.any((ip) => !before.contains(ip));
          if (changed || currentIps.isEmpty) {
            await scanPass(newIps);
          }
        }
      } catch (e) {
        // Ignore network errors
      } finally {
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }

    runScan();
    return controller.stream;
  }

  /// Prints labels using TSPL commands from [labelModel].
  ///
  /// Specify [deviceId] and [connectionType] to print to a specific target printer.
  static Future<void> printLabel({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required LabelModel labelModel,
  }) async {
    return await _platform.printLabel(
      deviceId: deviceId,
      connectionType: connectionType,
      labelModel: labelModel,
    );
  }

  /// Prints a rasterized image using the TSPL protocol.
  ///
  /// Takes an [imageModel] containing image byte data, coordinates, and dimensions.
  static Future<void> printImage({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required ImageModel imageModel,
  }) async {
    return await _platform.printImage(
      deviceId: deviceId,
      connectionType: connectionType,
      imageModel: imageModel,
    );
  }

  /// Prints a thermal receipt using ESC/POS commands from [printThermalModel].
  static Future<void> printESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel printThermalModel,
  }) async {
    return await _platform.printESC(
      deviceId: deviceId,
      connectionType: connectionType,
      printThermalModel: printThermalModel,
    );
  }

  /// Opens the cash drawer connected to the thermal printer via ESC/POS command (ESC p) or native cash drawer port.
  /// Returns `true` if the open command was successfully dispatched to a printer or native POS cash drawer.
  static Future<bool> openDrawer({
    String? deviceId,
    PrinterConnectionType? connectionType,
  }) async {
    return await _platform.openDrawer(
      deviceId: deviceId,
      connectionType: connectionType,
    );
  }

  // ==========================================
  // BLUETOOTH SECTION
  // ==========================================

  /// iOS: Starts scanning for Bluetooth Low Energy (BLE) devices.
  ///
  /// Discovered devices are emitted through [bluetoothScanStream].
  /// Call before subscribing to the stream on iOS.
  /// Android: No-op (scanning is automatically handled when retrieving devices).
  static Future<bool> startBluetoothScan() async {
    if (!Platform.isIOS) return false;
    return await _platform.startBluetoothScan();
  }

  /// iOS: Stops scanning for Bluetooth Low Energy (BLE) devices.
  /// Android: No-op.
  static Future<bool> stopBluetoothScan() async {
    if (!Platform.isIOS) return false;
    return await _platform.stopBluetoothScan();
  }

  /// Connects to a Bluetooth printer using its identifier [macAddress].
  ///
  /// - iOS: [macAddress] represents the CBPeripheral UUID string.
  /// - Android: [macAddress] represents the physical MAC address (e.g., `AA:BB:CC:DD:EE:FF`).
  static Future<bool> connectBluetooth({required String macAddress}) async {
    return await _platform.connectBluetooth(macAddress: macAddress);
  }

  static Future<bool> autoConnectBuiltIn() async {
    if (!Platform.isAndroid) return false;
    return await _platform.autoConnectBuiltIn();
  }

  /// Disconnects the built-in printer (only supported on Android).
  static Future<bool> disconnectBuiltIn() async {
    if (!Platform.isAndroid) return false;
    return await _platform.disconnectBuiltIn();
  }

  /// Checks if the current Android device has a built-in thermal printer.
  /// Always returns `false` on iOS/Web/Desktop.
  static Future<bool> hasBuiltInPrinter() async {
    if (!Platform.isAndroid) return false;
    return await _platform.hasBuiltInPrinter();
  }

  /// Gets the type (and paper size) of the built-in printer.
  /// Returns `BuiltInPrinterType.none` if the device has no built-in thermal printer.
  /// Always returns `BuiltInPrinterType.none` on iOS/Web/Desktop.
  static Future<BuiltInPrinterType> getBuiltInPrinterType() async {
    if (!Platform.isAndroid) return BuiltInPrinterType.none;
    final size = await _platform.getBuiltInPrinterPaperSize();
    return BuiltInPrinterType.fromPaperSize(size);
  }

  /// Retrieves a list of previously paired (bonded) Bluetooth devices.
  /// If [filterPrinterOnly] is true (default), only devices recognized as printers are returned.
  static Future<List<BluetoothDeviceModel>> getBluetoothDevices({bool filterPrinterOnly = true}) async {
    return await _platform.getBluetoothDevices(filterPrinterOnly: filterPrinterOnly);
  }

  /// Stream emitting discover.                       ed Bluetooth devices during active scans.
  ///
  /// If [filterPrinterOnly] is true (default), only devices recognized as printers are emitted.
  /// Call [startBluetoothScan] before listening to this stream on iOS.
  static Stream<BluetoothDeviceModel> bluetoothScanStream({bool filterPrinterOnly = true}) =>
      _platform.bluetoothScanStream(filterPrinterOnly: filterPrinterOnly);

  /// Stream emitting USB connection events (attach/detach) for USB printers (Android only).
  static Stream<UsbConnectionEvent> get usbDeviceStream =>
      _platform.usbDeviceStream;

  /// Prints raw text directly using TSPL printer commands.
  static Future<void> printText({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
    int x = 0,
    int y = 0,
    int font = 0,
    int rotation = 0,
    int sizeX = 1,
    int sizeY = 1,
    int width = 40,
    int height = 30,
  }) {
    return _platform.printText(
      deviceId: deviceId,
      connectionType: connectionType,
      text: text,
      x: x,
      y: y,
      font: font,
      rotation: rotation,
      sizeX: sizeX,
      sizeY: sizeY,
      width: width,
      height: height,
    );
  }

  /// Prints raw text directly using ESC/POS printer commands.
  static Future<void> printTextESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String text,
  }) {
    return _platform.printTextESC(
      deviceId: deviceId,
      connectionType: connectionType,
      text: text,
    );
  }

  /// Prints raw barcode directly using TSPL printer commands.
  static Future<void> printBarcode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int x = 0,
    int y = 0,
    int height = 100,
    String type = "128",
    int width = 40,
    int heightMM = 30,
  }) {
    return _platform.printBarcode(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      x: x,
      y: y,
      height: height,
      type: type,
      width: width,
      heightMM: heightMM,
    );
  }

  /// Prints raw QR code directly using TSPL printer commands.
  static Future<void> printQRCode({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int x = 0,
    int y = 0,
    int size = 4,
    int width = 40,
    int heightMM = 30,
  }) {
    return _platform.printQRCode(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      x: x,
      y: y,
      size: size,
      width: width,
      heightMM: heightMM,
    );
  }

  /// Prints raw barcode directly using ESC/POS printer commands.
  static Future<void> printBarcodeESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    String type = "128",
    int width = 2,
    int height = 162,
  }) {
    return _platform.printBarcodeESC(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      type: type,
      width: width,
      height: height,
    );
  }

  /// Prints raw QR code directly using ESC/POS printer commands.
  static Future<void> printQRCodeESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required String code,
    int size = 8,
  }) {
    return _platform.printQRCodeESC(
      deviceId: deviceId,
      connectionType: connectionType,
      code: code,
      size: size,
    );
  }
}
