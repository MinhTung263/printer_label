import '../service/gprinter_udp.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;

import '../desktop/lan_printer_scanner.dart' show LanPrinterScanner;
import '../desktop/printer_language_probe.dart';
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

  /// Android only: shows the system dialog asking the user to turn Bluetooth
  /// on, without leaving the app for Settings. Returns `true` if Bluetooth
  /// ends up enabled (already on, or user accepted the prompt), `false` if
  /// declined. iOS has no equivalent system prompt — always returns `false`.
  static Future<bool> requestBluetoothEnable() =>
      _platform.requestBluetoothEnable();

  /// Checks the connection status of a specific printer by its [deviceId].
  ///
  /// If [deviceId] is null, checks if any printer connection is active.
  static Future<bool> checkConnect({String? deviceId}) async {
    return await _platform.checkConnect(deviceId: deviceId);
  }

  /// Máy in Bluetooth [macAddress] đang nối có thật sự còn sống không (Android).
  ///
  /// Android chỉ báo mất liên kết sau thời gian giám sát (~20s) khi máy in tắt đột ngột, nên
  /// [checkConnect] vẫn `true` suốt lúc đó. Hàm này gửi lệnh hỏi trạng thái ESC/POS (DLE EOT —
  /// KHÔNG in ra giấy) qua kết nối đang mở: máy từng trả lời mà nay im lặng (2 lần × 1,5s) thì
  /// đóng kết nối đó (lần in sau nối lại từ đầu) và trả `false`. Máy chưa từng trả lời (không hỗ
  /// trợ lệnh) thì theo trạng thái kết nối. Chưa nối -> `false`.
  ///
  /// KHÔNG gọi cho máy in tem (lệnh TSPL) và lúc máy đang in. iOS: như [checkConnect].
  static Future<bool> probeBluetooth({required String macAddress}) async {
    if (!Platform.isAndroid) {
      return checkConnect(deviceId: DeviceId.bluetooth(macAddress));
    }
    return _platform.probeBluetooth(macAddress: macAddress);
  }

  /// Trạng thái giấy máy in [deviceId] báo ở lần in GẦN NHẤT của thiết bị này (Android, máy in
  /// LAN / USB — native hỏi `DLE EOT 4` ngay trước mỗi lần in nên đọc lại không tốn gì).
  /// `null`: chưa in lần nào từ khi mở app, hoặc nền tảng không hỗ trợ.
  static Future<PaperSensorState?> lastPaperStatus({
    required String deviceId,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return PaperSensorState.parse(
        await _platform.lastPaperStatus(deviceId: deviceId),
      );
    } on Object catch (_) {
      return null;
    }
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

  /// Re-connects to a previously seen USB printer using its stable
  /// [deviceId] (`DeviceId.usb(...)`, Android only). Call this before
  /// printing/checking a USB printer that was saved from a previous app
  /// session — after the process is killed and restarted while the printer
  /// stayed plugged in, no new USB-attached broadcast fires, so the native
  /// side never reconnects on its own. Returns `false` if the device isn't
  /// currently attached.
  static Future<bool> connectUsb({required String deviceId}) async {
    return await _platform.connectUsb(deviceId: deviceId);
  }

  /// Android only. Whether the plugin pops the system USB permission dialog by
  /// itself for printers already plugged in when the app starts (default
  /// `true`). Turn it off to show your own guidance first (e.g. a banner), then
  /// call [requestUsbPermissions] once the user agrees.
  static Future<void> setAutoRequestUsbPermission(bool enabled) =>
      _platform.setAutoRequestUsbPermission(enabled);

  /// Android only. When `true`, the next printer's permission dialog waits until
  /// [releaseUsbPermissionQueue] is called for the printer just granted (e.g.
  /// after the app closed its "create printer" screen), so dialogs never pop up
  /// over that screen. Released automatically if the connect fails or the
  /// printer is unplugged.
  static Future<void> setHoldUsbPermissionQueue(bool enabled) =>
      _platform.setHoldUsbPermissionQueue(enabled);

  /// Android only. Continue the permission queue held for [deviceId] (or any
  /// printer when `null`). See [setHoldUsbPermissionQueue].
  static Future<void> releaseUsbPermissionQueue({String? deviceId}) =>
      _platform.releaseUsbPermissionQueue(deviceId: deviceId);

  /// Android only. USB printers currently plugged in that still need the user
  /// to grant permission (e.g. after the device was powered off and on).
  /// Android only. Mọi máy in USB đang cắm, kèm trạng thái quyền và (khi đã có quyền)
  /// chuỗi IEEE 1284 để nhận biết máy in tem / hoá đơn.
  static Future<List<UsbPrinterInfo>> getUsbPrinters() =>
      _platform.getUsbPrinters();

  static Future<List<UsbPrinterInfo>> getUsbPrintersNeedingPermission() =>
      _platform.getUsbPrintersNeedingPermission();

  /// Android only. Shows the system permission dialog for each printer from
  /// [getUsbPrintersNeedingPermission], or a specific printer if [deviceId] is specified.
  /// Returns how many printers were granted.
  static Future<int> requestUsbPermissions({String? deviceId}) =>
      _platform.requestUsbPermissions(deviceId: deviceId);

  /// Discovers LAN printers by scanning the local network for open port 9100.
  ///
  /// Returns a stream of IP addresses (e.g. '192.168.1.10') that have the port open.
  ///
  /// [timeout] is the per-IP TCP connect timeout. Printers on the same LAN normally
  /// answer well under 100ms, so the short default keeps a full /24 sweep fast.
  /// Raise it only for congested networks or printers behind a slow AP.
  ///
  /// [extraSubnets]: các dải /24 khác cần quét thêm (dạng `192.168.1`), VD dải của
  /// máy in đã lưu khi thiết bị đang ở wifi của router phụ. Chỉ tìm thấy máy in khi
  /// router định tuyến giữa các dải. Dải trùng dải của thiết bị được bỏ qua.
  static Stream<String> discoverLanPrinters({
    int port = 9100,
    Duration? timeout,
    List<String> extraSubnets = const [],
  }) {
    // ignore: close_sinks
    final controller = StreamController<String>();

    Future<List<String>> getLocalIps() async {
      List<String> validIps = [];
      // 3 lần thử là đủ để WiFi kịp cấp IP sau khi vừa bật; 5 lần chỉ thêm 1s chờ
      // vô ích khi thiết bị thực sự không có mạng LAN.
      for (int retry = 0; retry < 3; retry++) {
        validIps = await _localPrivateIpv4s();
        if (validIps.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      return validIps;
    }

    // IP đã phát ra stream — chặn trùng khi lần quét 2 chạy lại, và khi thiết bị có
    // nhiều interface cùng subnet (VD WiFi + VPN) làm subnet bị quét lặp.
    final Set<String> emitted = <String>{};

    // Máy trả lời "từ chối kết nối" cổng in: máy còn sống nhưng cổng in không nhận lúc đó. Máy in
    // nhiệt LAN giá rẻ chỉ nhận 1–2 kết nối cùng lúc nên đang bận với thiết bị khác (Agent, máy
    // POS, điện thoại khác) cũng từ chối — quét một lượt sẽ bỏ sót máy đó ("lúc thấy lúc không").
    final Set<String> refused = <String>{};

    // Dò lại các máy đáng ngờ (từ chối kết nối + máy đã thấy ở lần quét trước) vài vòng, nghỉ giữa
    // vòng cho máy kịp nhả kết nối, thời gian chờ dài hơn lượt quét nhanh. Số máy ít nên rẻ.
    Future<int> recheck(Set<String> scanned) async {
      final candidates = <String>{
        ...refused,
        for (final ip in _lanDeviceCache.keys)
          if (scanned.contains(ip)) ip,
      }..removeAll(emitted);
      var found = 0;
      for (var round = 0; round < 2 && candidates.isNotEmpty; round++) {
        if (controller.isClosed) break;
        if (round > 0) await Future.delayed(const Duration(milliseconds: 400));
        final list = candidates.toList();
        for (var i = 0; i < list.length; i += 16) {
          final chunk = list.skip(i).take(16);
          await Future.wait(
            chunk.map((ip) async {
              try {
                final socket = await Socket.connect(
                  ip,
                  port,
                  timeout: const Duration(seconds: 1),
                );
                socket.destroy();
                if (!controller.isClosed && emitted.add(ip)) {
                  found++;
                  candidates.remove(ip);
                  controller.add(ip);
                }
              } catch (_) {}
            }),
          );
        }
      }
      return found;
    }

    Future<int> scanPass(
      List<String> validIps, {
      bool includeExtra = false,
    }) async {
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

      // Dải thêm quét sau dải của thiết bị (máy in cùng dải hiện ra trước).
      final List<String> extra = includeExtra
          ? extraSubnets
                .map((e) => e.trim())
                .where((e) => e.split('.').length == 3 && !subnets.contains(e))
                .toSet()
                .toList()
          : const [];

      // Hàng đợi phẳng tất cả IP cần quét (mọi subnet gộp chung).
      final List<String> targets = <String>[];
      for (var subnet in [...subnets, ...extra]) {
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
      // 48 (trước đây iOS 24): quét 2 lượt bên dưới nên mỗi lượt có thể nhanh hơn mà tổng thời
      // gian không tăng; 48 socket vẫn xa trần file descriptor của iOS (256).
      const int concurrency = 48;
      // IP không tồn tại thường bị firewall drop (không có RST) -> luôn phải chờ hết
      // timeout. Giữ ngắn vì máy in trong cùng LAN gần như luôn trả lời dưới 100ms.
      final connectTimeout =
          timeout ??
          (isIOS
              ? const Duration(milliseconds: 600)
              : const Duration(milliseconds: 400));

      // Một lượt quét [list]: mỗi worker bốc IP kế tiếp ngay khi xong IP trước.
      Future<void> sweep(
        List<String> list, {
        Duration? within,
        int workers = concurrency,
      }) async {
        final wait = within ?? connectTimeout;
        int next = 0;
        Future<void> worker() async {
          while (true) {
            if (controller.isClosed) return;
            final index = next++;
            if (index >= list.length) return;
            final targetIp = list[index];
            try {
              final socket = await Socket.connect(
                targetIp,
                port,
                timeout: wait,
              );
              socket.destroy();
              // Chặn phát trùng: lượt quét sau chạy lại cùng dải, và nhiều interface
              // có thể sinh cùng subnet.
              if (!controller.isClosed && emitted.add(targetIp)) {
                foundCount++;
                controller.add(targetIp);
              }
            } catch (e) {
              // Bỏ qua lỗi kết nối; nhưng nhớ máy "từ chối" để dò lại ([recheck]).
              if (e is SocketException && LanPrinterScanner.isRefused(e)) {
                refused.add(targetIp);
              }
            }
          }
        }

        await Future.wait(
          List.generate(
            workers < list.length ? workers : list.length,
            (_) => worker(),
          ),
        );
      }

      // Quét HAI lượt. Một máy in vẫn có lúc không đáp gói kết nối đầu (ARP chưa có trong bộ
      // nhớ, máy in bận nhịp đó): đo thật trên cùng một mạng, quét một lượt bỏ sót máy in đang
      // bật tới ~25% số lần ("lúc thấy lúc không"). Lượt hai chỉ dò các IP lượt một chưa thấy,
      // và RẺ hơn nhiều: lượt một đã kích hoạt ARP nên máy in thật đáp trong vài chục ms —
      // chờ 300ms, 96 kết nối cùng lúc (~0,8s), chạy song song với [recheck].
      // Máy đã biết (đã nhận ra ở lần quét trước / lần mở app trước) dò TRƯỚC, đồng thời: hiện ra
      // sau vài trăm ms thay vì phải chờ quét tới IP của nó giữa dải.
      final known = [
        for (final ip in _lanDeviceCache.keys)
          if (targets.contains(ip)) ip,
      ];
      if (known.isNotEmpty) {
        await Future.wait(
          known.map((ip) async {
            try {
              final socket = await Socket.connect(
                ip,
                port,
                timeout: const Duration(milliseconds: 800),
              );
              socket.destroy();
              if (!controller.isClosed && emitted.add(ip)) {
                foundCount++;
                controller.add(ip);
              }
            } catch (e) {
              if (e is SocketException && LanPrinterScanner.isRefused(e)) {
                refused.add(ip);
              }
            }
          }),
        );
      }
      await sweep([
        for (final ip in targets)
          if (!emitted.contains(ip)) ip,
      ]);
      await Future.wait([
        sweep(
          [
            for (final ip in targets)
              if (!emitted.contains(ip)) ip,
          ],
          within: const Duration(milliseconds: 300),
          workers: 96,
        ),
        recheck(targets.toSet()).then((n) => foundCount += n),
      ]);
      return foundCount;
    }

    Future<void> runScan() async {
      try {
        // Lần quét 1
        List<String> currentIps = await getLocalIps();
        int found = await scanPass(currentIps, includeExtra: true);

        // Nếu không tìm thấy máy in nào, có thể do OS đang cache IP cũ hoặc ARP chưa cập nhật
        if (found == 0 && !controller.isClosed) {
          await Future.delayed(
            const Duration(milliseconds: 500),
          ); // Chờ OS ổn định
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

  /// IPv4 nội bộ (192.168.x.x, 10.x.x.x, 172.16–31.x.x) của các interface đang bật
  /// trên thiết bị — tức các mạng LAN mà thiết bị có thể tới được máy in.
  static Future<List<String>> _localPrivateIpv4s() async {
    final List<String> ips = [];
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (var interface in interfaces) {
      // Đường hầm VPN (tun0, ppp0, ipsec, utun, wg0...) không phải mạng LAN có máy
      // in: quét vào chỉ chậm và lẫn thiết bị lạ của mạng công ty / nhà mạng.
      if (_isVpnInterface(interface.name)) continue;
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
          ips.add(ip);
        }
      }
    }
    return ips;
  }

  static bool _isVpnInterface(String name) {
    final n = name.toLowerCase();
    return n.startsWith('tun') ||
        n.startsWith('utun') ||
        n.startsWith('ppp') ||
        n.startsWith('ipsec') ||
        n.startsWith('wg') ||
        n.startsWith('tap');
  }

  /// Checks if a name is a generic clone emulation string rather than a true hardware model.
  static bool isGenericEmulation(String text) {
    final upper = text.toUpperCase();
    return upper.contains('CHINA GB18030') ||
        upper.contains('GB18030') ||
        upper.contains('EMULATION') ||
        upper == 'TM-T88III' ||
        upper == 'TM-T88' ||
        upper == 'POS-80' ||
        upper == 'POS58';
  }

  /// Checks if a string is a specific hardware model name.
  static bool isSpecificModel(String text) {
    final upper = text.toUpperCase();
    if (isGenericEmulation(upper)) return false;
    if (upper.contains('LOGIN') ||
        upper.contains('INDEX') ||
        upper.contains('CONFIGURATION') ||
        upper.contains('CONFIG') ||
        upper.contains('ETHERNET') ||
        upper.contains('PORT') ||
        upper.contains('SETTING') ||
        upper.contains('SETTINGS') ||
        upper.contains('NETWORK') ||
        upper.contains('STATUS') ||
        upper.contains('PRINTER SERVER') ||
        upper.contains('WEB SERVER') ||
        upper.contains('DEFAULT') ||
        upper.contains('PASSWORD') ||
        upper.contains('ADMIN') ||
        upper.contains('HOME') ||
        upper.contains('MAIN') ||
        upper.contains('PAGE') ||
        upper == 'PRINTER' ||
        upper == 'WORKGROUP' ||
        upper == 'UNKNOWN') {
      return false;
    }
    return true;
  }

  /// Bảng OUI (3 byte đầu của MAC) -> hãng máy in.
  ///
  /// Bản Dart của `LanPrinterProbe.getVendorFromMac` (Android). Cần ở tầng Dart vì iOS
  /// không có `get_lan_printer_info` native (iOS 11+ chặn đọc bảng ARP), nên bảng Kotlin
  /// không bao giờ chạy trên iPhone dù đã có MAC (lấy qua SNMP/HTTP/NetBIOS/SDK UDP).
  /// Sửa bảng nào thì PHẢI sửa cả hai. Chỉ thêm mã đã xác nhận (registry IEEE hoặc đo từ
  /// máy mẫu thật) — xem chú thích bên Kotlin.
  static const Map<String, String> _ouiVendors = {
    // Epson (Seiko Epson Corporation)
    '000048': 'Epson', '0026AB': 'Epson', '381A52': 'Epson', '389D92': 'Epson',
    '44D244': 'Epson', '50579C': 'Epson', '5805D9': 'Epson', '64C6D2': 'Epson',
    '64EB8C': 'Epson', '6855D4': 'Epson', '9CAED3': 'Epson', 'A4D73C': 'Epson',
    'A4EE57': 'Epson', 'AC1826': 'Epson', 'B0E892': 'Epson', 'BCC8CC': 'Epson',
    'D4808B': 'Epson', 'DC83BF': 'Epson', 'DCCD2F': 'Epson', 'E0BB9E': 'Epson',
    'F82551': 'Epson', 'F8D027': 'Epson',
    // HPRT (Xiamen Hanin Electronic Technology)
    '6CC147': 'HPRT',
    // Rongta — khối /28 nên 6 hex đầu không phân biệt tuyệt đối 100%
    '480BB2': 'Rongta',
    // Zebra Technologies
    '000512': 'Zebra', '00074D': 'Zebra', '001570': 'Zebra', '002368': 'Zebra',
    '00A0F8': 'Zebra', '4083DE': 'Zebra', '488EB7': 'Zebra', '609532': 'Zebra',
    '7493A4': 'Zebra', '78B8D6': 'Zebra', '84248D': 'Zebra', '88BCAC': 'Zebra',
    '9075DE': 'Zebra', '94FB29': 'Zebra', 'C47DCC': 'Zebra', 'C4BB4C': 'Zebra',
    'C81CFE': 'Zebra', 'FC597A': 'Zebra',
    // Bixolon
    '001594': 'Bixolon',
    // Star Micronics
    '001162': 'Star',
    // Citizen (Citizen Watch Co.)
    '000CAC': 'Citizen',
    // Brother Industries
    '001BA9': 'Brother', '008077': 'Brother', '30055C': 'Brother',
    '3C2AF4': 'Brother',
    '94DDF8': 'Brother', 'B07C8E': 'Brother', 'B42200': 'Brother',
    // SNBC (Shandong New Beiyang)
    '001341': 'SNBC',
    // Godex International
    '001D9A': 'Godex',
    // Sunmi (Shanghai Sunmi Technology)
    '1C1A1B': 'Sunmi', '68508C': 'Sunmi', '74F7F6': 'Sunmi', 'B81BCB': 'Sunmi',
    // PDIT — đo từ MAC máy mẫu thật (00:1A:EF:CB:2C:B0, 2026-09-29). Registry IEEE ghi
    // 00:1A:EF là "Loopcomm Technology, Inc." (hãng làm MODULE MẠNG, không phải PDIT):
    // máy in hãng khác dùng module Loopcomm cũng sẽ hiện "PDIT".
    '001AEF': 'PDIT',
    // KiotViet / Xprinter — bổ sung theo máy thực tế của khách (Xprinter đo từ
    // 00:61:7B:6B:4D:39, 2026-10-05; 00:61:1B / 00:61:1D theo máy thực tế, 2026-10-10).
    // Giữ khớp với `LanPrinterProbe.kt`.
    '00BACB': 'KiotViet',
    '00617B': 'Xprinter', '00611B': 'Xprinter', '00616D': 'Xprinter',
    // Gprinter — module mạng của máy thật tự khai MFC:GPRINTER qua gói `B[]G`
    // (00:47:50:3D:B4:A4, 00:47:50:25:CC:BC, 2026-11-21). Giữ khớp với `LanPrinterProbe.kt`.
    '004750': 'Gprinter',
  };

  /// Tra hãng máy in theo MAC (VD "00:1A:EF:CB:2C:B0" -> "PDIT"). Trả null nếu không biết.
  static String? vendorFromMac(String? mac) {
    if (mac == null) return null;
    final clean = mac.replaceAll(RegExp(r'[:\-.]'), '').toUpperCase();
    if (clean.length < 6) return null;
    return _ouiVendors[clean.substring(0, 6)];
  }

  /// Infers the printer manufacturer/brand from a model name, hostname, or raw string.
  static String? detectVendor(String modelOrText) {
    final upper = modelOrText.toUpperCase();

    if (upper.contains('HPRT') ||
        upper.contains('HANIN') ||
        upper.contains('XIAMEN HANIN') ||
        upper.startsWith('HT') ||
        upper.startsWith('HD') ||
        upper.startsWith('HM-') ||
        upper.startsWith('HM_') ||
        upper.startsWith('LPQ') ||
        upper.startsWith('SL4') ||
        upper.startsWith('SL3') ||
        upper.startsWith('TL2') ||
        upper.startsWith('TL3') ||
        upper.startsWith('HL7') ||
        upper.startsWith('N41') ||
        upper.startsWith('N31') ||
        upper.startsWith('PPT2') ||
        upper.startsWith('TP8') ||
        upper.startsWith('TP9') ||
        upper.startsWith('TP7') ||
        upper.startsWith('TP6') ||
        upper.startsWith('PRT')) {
      return 'HPRT';
    }
    if (upper.contains('XPRINTER') ||
        upper.startsWith('XP-') ||
        upper.startsWith('XP_') ||
        upper.startsWith('XP') ||
        upper.contains('Q807') ||
        upper.contains('Q800') ||
        upper.contains('Q200') ||
        upper.contains('Q300') ||
        upper.contains('C260') ||
        upper.contains('N160') ||
        upper.contains('CHINA GB18030') ||
        upper.contains('GB18030')) {
      return 'Xprinter';
    }
    if (upper.contains('GPRINTER') ||
        upper.startsWith('GP-') ||
        upper.startsWith('GP_') ||
        upper.startsWith('GP')) {
      return 'Gprinter';
    }
    if (upper.contains('TSC') ||
        upper.startsWith('TDP-') ||
        upper.startsWith('TTP-') ||
        upper.startsWith('TE2') ||
        upper.startsWith('TX-') ||
        upper.startsWith('DA2') ||
        upper.startsWith('MB2') ||
        upper.startsWith('ML2')) {
      return 'TSC';
    }
    if (upper.contains('RONGTA') ||
        upper.startsWith('RP-') ||
        upper.startsWith('RP3') ||
        upper.startsWith('RP4') ||
        upper.startsWith('RP8')) {
      return 'Rongta';
    }
    if (upper.contains('ZEBRA') ||
        upper.startsWith('ZD') ||
        upper.startsWith('GK') ||
        upper.startsWith('GX') ||
        upper.startsWith('ZT')) {
      return 'Zebra';
    }
    if (upper.contains('BIXOLON') ||
        upper.startsWith('SRP-') ||
        upper.startsWith('STP-') ||
        upper.startsWith('SPH-')) {
      return 'Bixolon';
    }
    if (upper.contains('CITIZEN') ||
        upper.startsWith('CT-S') ||
        upper.startsWith('CL-S') ||
        upper.startsWith('CMP-')) {
      return 'Citizen';
    }
    if (upper.contains('STAR') ||
        upper.startsWith('TSP') ||
        upper.startsWith('SM-')) {
      return 'Star';
    }
    if (upper.contains('BROTHER') ||
        upper.startsWith('QL-') ||
        upper.startsWith('TD-') ||
        upper.startsWith('PT-')) {
      return 'Brother';
    }
    if (upper.contains('SNBC') ||
        upper.startsWith('BTP-') ||
        upper.contains('BEIYANG')) {
      return 'SNBC';
    }
    if (upper.contains('SUNMI')) {
      return 'Sunmi';
    }
    if (upper.contains('4BARCODE')) {
      return '4Barcode';
    }
    if (upper.contains('EPSON') ||
        upper.startsWith('TM-') ||
        upper.startsWith('TM_') ||
        upper.startsWith('M30') ||
        upper.startsWith('M10')) {
      return 'Epson';
    }
    if (upper.contains('ZJIANG') ||
        upper.startsWith('POS-58') ||
        upper.startsWith('POS-80')) {
      return 'POS';
    }
    return null;
  }

  /// Formats the printer model name with its manufacturer brand using pattern [Brand]_[Model] (e.g. "HPRT_HT300" or "Xprinter_XP-420B" or "HPRT_TP805" or "Xprinter").
  static String formatPrinterName(String rawName) {
    var cleaned = rawName
        .replaceAll(RegExp(r'[\r\n\x00\x1F\x7F-\x9F]'), '')
        .replaceFirst(RegExp(r'^_+'), '')
        .trim();

    if (cleaned.isEmpty) return 'Máy in LAN';

    final vendor = detectVendor(cleaned);

    // Nếu là chuỗi giả lập Trung Quốc (như XP-Q807K trả về CHINA GB18030)
    if (isGenericEmulation(cleaned)) {
      return vendor ?? 'Xprinter';
    }

    // Nếu là mã model cụ thể (như HT300, HT100, LPQ80, XP-420B, TP805, TM-T82...)
    if (isSpecificModel(cleaned)) {
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), '_');

      if (vendor != null && vendor != 'Xprinter/POS' && vendor != 'POS') {
        final vendorUpper = vendor.toUpperCase();
        final cleanedUpper = cleaned.toUpperCase();

        if (!cleanedUpper.startsWith('${vendorUpper}_') &&
            !cleanedUpper.startsWith(vendorUpper)) {
          return '${vendor}_$cleaned';
        }
      }
      return cleaned;
    }

    // Nếu nhận diện được tên hãng (vd: HPRT, Epson, Xprinter, TSC, Rongta...)
    if (vendor != null && vendor != 'Xprinter/POS' && vendor != 'POS') {
      return vendor;
    }

    return 'Máy in LAN';
  }

  // ---------------------------------------------------------------------------
  // SNMP v1 helpers (Safe UDP 161 read-only queries)
  // ---------------------------------------------------------------------------

  /// Encodes an SNMP OID string (e.g. "1.3.6.1.2.1.1.1.0") into BER-encoded bytes.
  static List<int> _encodeSnmpOid(String oid) {
    final parts = oid.split('.').map(int.parse).toList();
    if (parts.length < 2) return [];
    // First two sub-identifiers are merged: X.Y → 40*X + Y
    final encoded = <int>[40 * parts[0] + parts[1]];
    for (int i = 2; i < parts.length; i++) {
      int val = parts[i];
      if (val == 0) {
        encoded.add(0);
      } else {
        final bytes = <int>[];
        bytes.add(val & 0x7F);
        val >>= 7;
        while (val > 0) {
          bytes.add((val & 0x7F) | 0x80);
          val >>= 7;
        }
        encoded.addAll(bytes.reversed);
      }
    }
    return encoded;
  }

  /// BER-encodes a length value (supports multi-byte for lengths > 127).
  static List<int> _berLength(int len) {
    if (len < 0x80) return [len];
    if (len < 0x100) return [0x81, len];
    return [0x82, (len >> 8) & 0xFF, len & 0xFF];
  }

  /// Builds a single-OID SNMP v1 GET request packet.
  static List<int> _buildSnmpGetRequest(
    String oid, {
    int requestId = 1,
    String community = 'public',
  }) {
    final oidBytes = _encodeSnmpOid(oid);
    final oidTlv = [
      0x06,
      ..._berLength(oidBytes.length),
      ...oidBytes,
    ]; // OID tag
    final nullTlv = [0x05, 0x00]; // NULL
    final vb = [...oidTlv, ...nullTlv];
    final vbSeq = [0x30, ..._berLength(vb.length), ...vb]; // SEQUENCE (VarBind)
    final vblSeq = [
      0x30,
      ..._berLength(vbSeq.length),
      ...vbSeq,
    ]; // SEQUENCE (VarBindList)

    final reqIdBytes = [
      0x02,
      0x04,
      (requestId >> 24) & 0xFF,
      (requestId >> 16) & 0xFF,
      (requestId >> 8) & 0xFF,
      requestId & 0xFF,
    ];
    final errorStatus = [0x02, 0x01, 0x00];
    final errorIndex = [0x02, 0x01, 0x00];
    final pduData = [...reqIdBytes, ...errorStatus, ...errorIndex, ...vblSeq];
    final pdu = [0xA0, ..._berLength(pduData.length), ...pduData];

    final commBytes = utf8.encode(community);
    final communityTlv = [0x04, ..._berLength(commBytes.length), ...commBytes];
    final version = [0x02, 0x01, 0x00]; // SNMPv1 = 0

    final msg = [...version, ...communityTlv, ...pdu];
    return [0x30, ..._berLength(msg.length), ...msg];
  }

  /// Parses an SNMP v1 GET Response and returns each VarBind's raw (tag, value bytes).
  static List<MapEntry<int, List<int>>> _parseSnmpVarBinds(List<int> data) {
    final results = <MapEntry<int, List<int>>>[];
    try {
      int i = 0;
      int readLength(List<int> d, int pos) {
        if (d[pos] < 0x80) return d[pos];
        final numBytes = d[pos] & 0x7F;
        int len = 0;
        for (int k = 1; k <= numBytes; k++) {
          len = (len << 8) | d[pos + k];
        }
        return len;
      }

      int lengthFieldSize(List<int> d, int pos) {
        if (d[pos] < 0x80) return 1;
        return 1 + (d[pos] & 0x7F);
      }

      // Outer SEQUENCE
      if (data[i++] != 0x30) return results;
      i += lengthFieldSize(data, i);

      // Version INTEGER
      if (data[i++] != 0x02) return results;
      final verLen = readLength(data, i);
      i += lengthFieldSize(data, i) + verLen;

      // Community OCTET STRING
      if (data[i++] != 0x04) return results;
      final comLen = readLength(data, i);
      i += lengthFieldSize(data, i) + comLen;

      // GetResponse PDU (0xA2)
      if (data[i++] != 0xA2) return results;
      i += lengthFieldSize(data, i);

      // Skip reqId, errorStatus, errorIndex
      for (int skip = 0; skip < 3; skip++) {
        i++;
        final sLen = readLength(data, i);
        i += lengthFieldSize(data, i) + sLen;
      }

      // VarBindList SEQUENCE
      if (data[i++] != 0x30) return results;
      i += lengthFieldSize(data, i);

      // Parse each VarBind SEQUENCE
      while (i < data.length) {
        if (data[i++] != 0x30) break;
        i += lengthFieldSize(data, i);

        // OID
        if (i >= data.length || data[i++] != 0x06) break;
        final oidLen = readLength(data, i);
        i += lengthFieldSize(data, i) + oidLen;

        // Value
        if (i >= data.length) break;
        final valTag = data[i++];
        final valLen = readLength(data, i);
        i += lengthFieldSize(data, i);
        if (i + valLen > data.length) break;

        results.add(MapEntry(valTag, data.sublist(i, i + valLen)));
        i += valLen;
      }
    } catch (_) {}
    return results;
  }

  /// Extracts non-empty printable string values (OCTET STRING VarBinds) from an SNMP response.
  static List<String> _parseSnmpResponse(List<int> data) {
    final results = <String>[];
    for (final entry in _parseSnmpVarBinds(data)) {
      if (entry.key != 0x04) continue;
      final str = String.fromCharCodes(
        entry.value.where((b) => b >= 0x20 && b < 0x7F),
      ).trim();
      if (str.isNotEmpty) results.add(str);
    }
    return results;
  }

  /// Extracts a hardware MAC address from an SNMP response, looking for a 6-byte
  /// OCTET STRING VarBind (the `ifPhysAddress` value is returned as raw binary, not text).
  static String? _parseSnmpMacResponse(List<int> data) {
    for (final entry in _parseSnmpVarBinds(data)) {
      if (entry.key != 0x04 || entry.value.length != 6) continue;
      final bytes = entry.value;
      if (bytes.every((b) => b == 0x00) || bytes.every((b) => b == 0xFF)) {
        continue;
      }
      return bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':');
    }
    return null;
  }

  /// Queries a printer's SNMP agent (UDP port 161) to retrieve
  /// its exact hardware model name as reported by the device itself.
  static Future<String?> querySnmpPrinterName(
    String ip, {
    Duration timeout = const Duration(milliseconds: 700),
  }) async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = false;

      final dest = InternetAddress(ip);
      final completer = Completer<String?>();

      sock.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final dg = sock?.receive();
            if (dg == null || completer.isCompleted) return;

            final values = _parseSnmpResponse(dg.data);
            for (final v in values) {
              final trimmed = v.trim();
              if (trimmed.isNotEmpty &&
                  !trimmed.toUpperCase().contains('LINUX') &&
                  !trimmed.toUpperCase().contains('UNKNOWN')) {
                completer.complete(trimmed);
                return;
              }
            }
          }
        },
        // Lỗi gửi / nhận UDP (VD "Host is down" khi IP không tới được) báo qua stream:
        // không bắt thì thành lỗi không xử lý ở toàn app.
        onError: (Object _) {},
      );

      // OIDs chuẩn MIB-2, Printer MIB và Enterprise MIB của HPRT / POS
      final oids = [
        '1.3.6.1.2.1.1.1.0', // sysDescr.0
        '1.3.6.1.2.1.1.5.0', // sysName.0
        '1.3.6.1.2.1.25.3.2.1.3.1', // hrDeviceDescr.1
        '1.3.6.1.2.1.43.5.1.1.16.1', // prtGeneralPrinterName.1
        '1.3.6.1.4.1.39165.1.1.0', // HPRT / Hanin private enterprise OID
      ];

      final communities = ['public', 'admin', 'HPRT'];

      int reqId = 0x200;
      for (final comm in communities) {
        for (final oid in oids) {
          final packet = _buildSnmpGetRequest(
            oid,
            requestId: reqId++,
            community: comm,
          );
          sock.send(packet, dest, 161);
        }
      }

      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      sock?.close();
    }
  }

  /// Queries a printer's SNMP agent (UDP port 161) for its hardware MAC address
  /// via the standard MIB-2 `ifPhysAddress` OID (`1.3.6.1.2.1.2.2.1.6.<ifIndex>`).
  static Future<String?> querySnmpMac(
    String ip, {
    Duration timeout = const Duration(milliseconds: 700),
  }) async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = false;

      final dest = InternetAddress(ip);
      final completer = Completer<String?>();

      sock.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final dg = sock?.receive();
            if (dg == null || completer.isCompleted) return;

            final mac = _parseSnmpMacResponse(dg.data);
            if (mac != null) completer.complete(mac);
          }
        },
        // Lỗi gửi / nhận UDP (VD "Host is down" khi IP không tới được) báo qua stream:
        // không bắt thì thành lỗi không xử lý ở toàn app.
        onError: (Object _) {},
      );

      // ifPhysAddress cho vài chỉ số interface phổ biến (hầu hết máy in chỉ có 1-2 card mạng)
      final oids = ['1.3.6.1.2.1.2.2.1.6.1', '1.3.6.1.2.1.2.2.1.6.2'];
      final communities = ['public', 'admin'];

      int reqId = 0x300;
      for (final comm in communities) {
        for (final oid in oids) {
          final packet = _buildSnmpGetRequest(
            oid,
            requestId: reqId++,
            community: comm,
          );
          sock.send(packet, dest, 161);
        }
      }

      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      sock?.close();
    }
  }

  // ---------------------------------------------------------------------------
  // HPRT / Hanin UDP Discovery (Port 3000 / Port 8888)
  // ---------------------------------------------------------------------------

  /// Queries HPRT printer discovery protocol over UDP ports 3000 and 8888.
  static Future<String?> queryHprtUdpPrinterName(
    String ip, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    // Gói tin truy vấn cấu hình mạng HPRT / Hanin
    final hprtPackets = <List<int>>[
      utf8.encode("HPRT_DISCOVER\r\n"),
      utf8.encode("PRINTER_SEARCH\r\n"),
      [0x00, 0x01, 0x00, 0x00, 0x48, 0x50, 0x52, 0x54], // Binary HPRT header
    ];
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      final completer = Completer<String?>();
      socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final dg = socket?.receive();
            if (dg == null || completer.isCompleted) return;

            final text = String.fromCharCodes(
              dg.data.where((b) => b >= 0x20 && b < 0x7F),
            );
            // Gói DỘI LẠI chính gói hỏi (module mạng Gprinter dội mọi gói UDP tới cổng
            // 3000): trước đây chữ "HPRT" trong gói hỏi làm mọi máy Gprinter bị đặt tên
            // "HPRT". Bỏ qua.
            if (text.contains('HPRT_DISCOVER') ||
                text.contains('PRINTER_SEARCH') ||
                _isEcho(dg.data, hprtPackets)) {
              return;
            }
            final vendor = detectVendor(text);
            if (vendor != null) {
              final modelMatch = RegExp(
                r'\b(HT[0-9]+[A-Za-z0-9_-]*|HD[0-9]+[A-Za-z0-9_-]*|HM-[A-Za-z0-9_-]+|SL[0-9]+[A-Za-z0-9_-]*|TL[0-9]+[A-Za-z0-9_-]*|HL[0-9]+[A-Za-z0-9_-]*|N[0-9]+[A-Za-z0-9_-]*|LPQ[0-9]+[A-Za-z0-9_-]*|PPT[0-9]+[A-Za-z0-9_-]*|TP[0-9]+[A-Za-z0-9_-]*)\b',
                caseSensitive: false,
              ).firstMatch(text);
              if (modelMatch != null) {
                completer.complete('HPRT_${modelMatch.group(1)}');
                return;
              }
              completer.complete('HPRT');
              return;
            }
          }
        },
        // Lỗi gửi / nhận UDP (VD "Host is down" khi IP không tới được) báo qua stream:
        // không bắt thì thành lỗi không xử lý ở toàn app.
        onError: (Object _) {},
      );

      final dest = InternetAddress(ip);
      // Máy đã biết là Gprinter: KHÔNG gửi gói lạ tới cổng 3000 (module dội lại mọi gói,
      // hai máy có thể dội qua lại hàng nghìn gói — xem docs/PRINTER_NETWORK_CONFIG_GUIDE.md).
      final ports = _isKnownGprinter(ip)
          ? const [8888, 50000]
          : const [3000, 8888, 50000];
      for (final p in hprtPackets) {
        for (final port in ports) {
          socket.send(p, dest, port);
        }
      }

      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  // ---------------------------------------------------------------------------
  // SSDP / UPnP Discovery (UDP 1900)
  // ---------------------------------------------------------------------------

  /// Queries SSDP / UPnP (UDP 1900) for printer device descriptions.
  static Future<String?> querySsdpPrinterName(
    String ip, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      final completer = Completer<String?>();
      socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final dg = socket?.receive();
            if (dg == null || completer.isCompleted) return;

            final text = String.fromCharCodes(
              dg.data.where((b) => b >= 0x20 && b < 0x7F),
            );
            final vendor = detectVendor(text);
            if (vendor != null && vendor != 'POS' && vendor != 'Xprinter/POS') {
              final modelMatch = RegExp(
                r'\b(HT[0-9]+[A-Za-z0-9_-]*|HD[0-9]+[A-Za-z0-9_-]*|HM-[A-Za-z0-9_-]+|SL[0-9]+[A-Za-z0-9_-]*|TL[0-9]+[A-Za-z0-9_-]*|HL[0-9]+[A-Za-z0-9_-]*|N[0-9]+[A-Za-z0-9_-]*|LPQ[0-9]+[A-Za-z0-9_-]*|PPT[0-9]+[A-Za-z0-9_-]*|TP[0-9]+[A-Za-z0-9_-]*|XP-[A-Za-z0-9_-]+|GP-[A-Za-z0-9_-]+|TDP-[A-Za-z0-9_-]+|TTP-[A-Za-z0-9_-]+|RP[0-9]+[A-Za-z0-9_-]*|TM-[A-Za-z0-9_-]+|ZD[0-9]+|SRP-[A-Za-z0-9_-]+|BTP-[A-Za-z0-9_-]+)\b',
                caseSensitive: false,
              ).firstMatch(text);
              if (modelMatch != null) {
                completer.complete('${vendor}_${modelMatch.group(1)}');
                return;
              }
              completer.complete(vendor);
              return;
            }
          }
        },
        // Lỗi gửi / nhận UDP (VD "Host is down" khi IP không tới được) báo qua stream:
        // không bắt thì thành lỗi không xử lý ở toàn app.
        onError: (Object _) {},
      );

      final ssdpMsg = utf8.encode(
        "M-SEARCH * HTTP/1.1\r\n"
        "HOST: 239.255.255.250:1900\r\n"
        "MAN: \"ssdp:discover\"\r\n"
        "MX: 1\r\n"
        "ST: ssdp:all\r\n\r\n",
      );

      socket.send(ssdpMsg, InternetAddress(ip), 1900);

      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  // ---------------------------------------------------------------------------
  // mDNS (Multicast DNS / Bonjour - UDP 5353)
  // ---------------------------------------------------------------------------

  /// Queries mDNS (UDP 5353) to discover printer model from TXT and SRV records.
  static Future<String?> queryMdnsPrinterName(
    String ip, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      final completer = Completer<String?>();
      socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final dg = socket?.receive();
            if (dg == null || completer.isCompleted) return;

            // Parse raw bytes in mDNS response for printer information
            final text = String.fromCharCodes(
              dg.data.where((b) => b >= 0x20 && b < 0x7F),
            );

            // 1. Tìm TXT record `ty=...` hoặc `product=...` hoặc `mdl=...`
            final match = RegExp(
              r'(ty|product|mdl|model|mfg)=([^\x00\r\n;]+)',
              caseSensitive: false,
            ).firstMatch(text);
            if (match != null) {
              final modelStr = match.group(2)?.trim();
              if (modelStr != null && modelStr.isNotEmpty) {
                completer.complete(modelStr);
                return;
              }
            }

            // 2. Tìm model match thông thường từ toàn bộ text
            final vendor = detectVendor(text);
            if (vendor != null && vendor != 'POS' && vendor != 'Xprinter/POS') {
              final modelMatch = RegExp(
                r'\b(HT[0-9]+[A-Za-z0-9_-]*|HD[0-9]+[A-Za-z0-9_-]*|HM-[A-Za-z0-9_-]+|SL[0-9]+[A-Za-z0-9_-]*|TL[0-9]+[A-Za-z0-9_-]*|HL[0-9]+[A-Za-z0-9_-]*|N[0-9]+[A-Za-z0-9_-]*|LPQ[0-9]+[A-Za-z0-9_-]*|PPT[0-9]+[A-Za-z0-9_-]*|TP[0-9]+[A-Za-z0-9_-]*|XP-[A-Za-z0-9_-]+|GP-[A-Za-z0-9_-]+|TDP-[A-Za-z0-9_-]+|TTP-[A-Za-z0-9_-]+|RP[0-9]+[A-Za-z0-9_-]*|TM-[A-Za-z0-9_-]+|ZD[0-9]+|SRP-[A-Za-z0-9_-]+|BTP-[A-Za-z0-9_-]+)\b',
                caseSensitive: false,
              ).firstMatch(text);
              if (modelMatch != null) {
                completer.complete(modelMatch.group(1));
                return;
              }
              completer.complete(vendor);
              return;
            }
          }
        },
        // Lỗi gửi / nhận UDP (VD "Host is down" khi IP không tới được) báo qua stream:
        // không bắt thì thành lỗi không xử lý ở toàn app.
        onError: (Object _) {},
      );

      // DNS Query Header (Transaction ID: 0x0001, Standard Query)
      // Query for _printer._tcp.local (PTR)
      final mdnsQuery = <int>[
        0x00, 0x01, // ID
        0x00, 0x00, // Flags (Standard query)
        0x00, 0x01, // QDCOUNT: 1
        0x00, 0x00, // ANCOUNT
        0x00, 0x00, // NSCOUNT
        0x00, 0x00, // ARCOUNT
        // QNAME: _printer._tcp.local
        0x08, 0x5F, 0x70, 0x72, 0x69, 0x6E, 0x74, 0x65, 0x72, // _printer
        0x04, 0x5F, 0x74, 0x63, 0x70, // _tcp
        0x05, 0x6C, 0x6F, 0x63, 0x61, 0x6C, // local
        0x00, // Null terminator
        0x00, 0x0C, // QTYPE: PTR (12)
        0x00, 0x01, // QCLASS: IN (1)
      ];

      socket.send(mdnsQuery, InternetAddress(ip), 5353);

      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  // ---------------------------------------------------------------------------
  // NetBIOS (UDP 137)
  // ---------------------------------------------------------------------------

  /// Queries the NetBIOS name of a host (UDP port 137).
  /// Network thermal printers (HPRT, Xprinter, Rongta, etc.) almost always return their burned-in model name (e.g. "HT300" or "XP-Q807K_UL").
  static Future<String?> queryNetBiosName(
    String ip, {
    Duration timeout = const Duration(milliseconds: 400),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      final completer = Completer<String?>();
      socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket?.receive();
            if (datagram != null &&
                datagram.data.length > 40 &&
                !completer.isCompleted) {
              final data = datagram.data;
              final text = String.fromCharCodes(
                data.where((b) => (b >= 0x20 && b < 0x7F) || b == 0x00),
              );
              final tokens = text
                  .split(RegExp(r'[\x00\s]+'))
                  .map((s) => s.trim())
                  .where(
                    (s) =>
                        s.length >= 3 &&
                        s.length <= 20 &&
                        !s.contains('WORKGROUP') &&
                        !s.contains('MSBROWSE'),
                  )
                  .toList();

              for (final token in tokens) {
                if (isSpecificModel(token)) {
                  completer.complete(token);
                  return;
                }
                final vendor = detectVendor(token);
                if (vendor != null &&
                    vendor != 'POS' &&
                    vendor != 'Xprinter/POS') {
                  completer.complete(token);
                  return;
                }
              }

              if (tokens.isNotEmpty) {
                completer.complete(tokens.first);
                return;
              }
            }
          }
        },
        // Lỗi gửi / nhận UDP (VD "Host is down" khi IP không tới được) báo qua stream:
        // không bắt thì thành lỗi không xử lý ở toàn app.
        onError: (Object _) {},
      );

      socket.send(_nbstatPacket, InternetAddress(ip), 137);

      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  /// NetBIOS Node Status Request Packet (RFC 1002) for wildcard "*".
  static const List<int> _nbstatPacket = <int>[
    0x13, 0x37, // Transaction ID
    0x00, 0x00, // Flags (Query)
    0x00, 0x01, // Questions: 1
    0x00, 0x00, // Answer RRs
    0x00, 0x00, // Authority RRs
    0x00, 0x00, // Additional RRs
    // Question Name: "*" encoded in NetBIOS format (CKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA)
    0x20, // Length 32
    0x43, 0x4B, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
    0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
    0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
    0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
    0x00, // Zero byte
    0x00, 0x21, // Type: NBSTAT (33)
    0x00, 0x01, // Class: IN (1)
  ];

  /// Queries the NetBIOS Node Status (UDP port 137) and extracts the hardware
  /// MAC address from the response's Unit ID field (RFC 1002 NODE STATUS RESPONSE,
  /// the 6 bytes immediately following the NUM_NAMES name table in STATISTICS).
  static Future<String?> queryNetBiosMac(
    String ip, {
    Duration timeout = const Duration(milliseconds: 400),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      final completer = Completer<String?>();
      socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket?.receive();
            if (datagram == null || completer.isCompleted) return;
            final mac = _parseNetBiosMac(datagram.data);
            if (mac != null) completer.complete(mac);
          }
        },
        // Lỗi gửi / nhận UDP (VD "Host is down" khi IP không tới được) báo qua stream:
        // không bắt thì thành lỗi không xử lý ở toàn app.
        onError: (Object _) {},
      );

      socket.send(_nbstatPacket, InternetAddress(ip), 137);

      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  /// Parses an RFC 1002 NODE STATUS RESPONSE and returns the Unit ID (MAC address).
  static String? _parseNetBiosMac(List<int> data) {
    try {
      if (data.length < 12) return null;

      // Skip the 12-byte header, then the answer's NAME field (either a
      // length-prefixed label or a 2-byte compression pointer).
      int i = 12;
      while (i < data.length) {
        final len = data[i];
        if (len == 0) {
          i += 1;
          break;
        }
        if ((len & 0xC0) == 0xC0) {
          i += 2;
          break;
        }
        i += 1 + len;
      }

      // TYPE(2) + CLASS(2) + TTL(4) + RDLENGTH(2)
      i += 10;
      if (i > data.length) return null;

      // RDATA: NUM_NAMES(1) + NUM_NAMES * 18-byte name entries, then STATISTICS.
      if (i >= data.length) return null;
      final numNames = data[i];
      i += 1 + numNames * 18;

      if (i + 6 > data.length) return null;
      final macBytes = data.sublist(i, i + 6);
      if (macBytes.every((b) => b == 0x00) ||
          macBytes.every((b) => b == 0xFF)) {
        return null;
      }
      return macBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':');
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP Web Config (Port 80)
  // ---------------------------------------------------------------------------

  /// Queries the embedded web server on port 80 to extract the printer model and brand.
  static Future<String?> queryHttpPrinterName(
    String ip, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    Future<String?> fetchPath(String path) async {
      Socket? socket;
      try {
        socket = await Socket.connect(ip, 80, timeout: timeout);
        socket.write(
          "GET $path HTTP/1.1\r\nHost: $ip\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n",
        );
        await socket.flush();

        final completer = Completer<String?>();
        final buffer = <int>[];

        socket.listen(
          (data) => buffer.addAll(data),
          onDone: () {
            if (!completer.isCompleted) {
              final text = String.fromCharCodes(buffer);

              // 1. Tìm trong <title>...</title> (ví dụ: <title>HT300 Web Server</title> hoặc <title>HPRT Printer</title>)
              final titleMatch = RegExp(
                r'<title[^>]*>(.*?)</title>',
                caseSensitive: false,
              ).firstMatch(text);
              if (titleMatch != null) {
                final titleText = titleMatch.group(1)?.trim();
                if (titleText != null &&
                    titleText.isNotEmpty &&
                    isSpecificModel(titleText)) {
                  completer.complete(formatPrinterName(titleText));
                  return;
                }
              }

              // 2. Tìm chính xác mã model từ HTML (vd: HT300, HT100, HD100, LPQ80, SL42, TP805, XP-420B...)
              final modelMatch = RegExp(
                r'\b(HT[0-9]+[A-Za-z0-9_-]*|HD[0-9]+[A-Za-z0-9_-]*|HM-[A-Za-z0-9_-]+|SL[0-9]+[A-Za-z0-9_-]*|TL[0-9]+[A-Za-z0-9_-]*|HL[0-9]+[A-Za-z0-9_-]*|N[0-9]+[A-Za-z0-9_-]*|LPQ[0-9]+[A-Za-z0-9_-]*|PPT[0-9]+[A-Za-z0-9_-]*|TP[0-9]+[A-Za-z0-9_-]*|XP-[A-Za-z0-9_-]+|GP-[A-Za-z0-9_-]+|TDP-[A-Za-z0-9_-]+|TTP-[A-Za-z0-9_-]+|RP[0-9]+[A-Za-z0-9_-]*|TM-[A-Za-z0-9_-]+|ZD[0-9]+|SRP-[A-Za-z0-9_-]+|BTP-[A-Za-z0-9_-]+)\b',
                caseSensitive: false,
              ).firstMatch(text);
              final model = modelMatch?.group(1)?.trim();

              final vendor = detectVendor(text);

              if (model != null && isSpecificModel(model)) {
                if (vendor != null &&
                    vendor != 'Xprinter/POS' &&
                    vendor != 'POS') {
                  completer.complete('${vendor}_$model');
                } else {
                  completer.complete(formatPrinterName(model));
                }
                return;
              }

              if (vendor != null &&
                  vendor != 'Xprinter/POS' &&
                  vendor != 'POS') {
                completer.complete(vendor);
                return;
              }

              completer.complete(null);
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete(null);
          },
        );

        return await completer.future.timeout(timeout, onTimeout: () => null);
      } catch (_) {
        return null;
      } finally {
        socket?.destroy();
      }
    }

    // Thử trang chủ `/`, nếu không ra model thì thử các trang con phổ biến của HPRT/POS
    final rootResult = await fetchPath('/');
    if (rootResult != null && rootResult != 'Máy in LAN') return rootResult;

    final indexResult = await fetchPath('/index.html');
    if (indexResult != null && indexResult != 'Máy in LAN') return indexResult;

    return await fetchPath('/status.html');
  }

  /// Queries the embedded web server (TCP port 80) and extracts a hardware MAC
  /// address from the raw HTML/headers via regex (e.g. "MAC Address: AA:BB:...").
  static Future<String?> queryHttpMac(
    String ip, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    Future<String?> fetchPath(String path) async {
      Socket? socket;
      try {
        socket = await Socket.connect(ip, 80, timeout: timeout);
        socket.write(
          "GET $path HTTP/1.1\r\nHost: $ip\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n",
        );
        await socket.flush();

        final completer = Completer<String?>();
        final buffer = <int>[];

        socket.listen(
          (data) => buffer.addAll(data),
          onDone: () {
            if (!completer.isCompleted) {
              final text = String.fromCharCodes(buffer);
              final macMatch = RegExp(
                r'([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}',
              ).firstMatch(text);
              final raw = macMatch?.group(0);
              if (raw == null) {
                completer.complete(null);
              } else {
                final mac = raw.replaceAll('-', ':').toUpperCase();
                final octets = mac.split(':');
                final invalid =
                    octets.every((o) => o == '00') ||
                    octets.every((o) => o == 'FF');
                completer.complete(invalid ? null : mac);
              }
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete(null);
          },
        );

        return await completer.future.timeout(timeout, onTimeout: () => null);
      } catch (_) {
        return null;
      } finally {
        socket?.destroy();
      }
    }

    final root = await fetchPath('/');
    if (root != null) return root;
    final index = await fetchPath('/index.html');
    if (index != null) return index;
    final status = await fetchPath('/status.html');
    if (status != null) return status;
    // Máy in dùng module Ethernet có trang cấu hình riêng (HPRT...): trang chủ chỉ là khung, MAC
    // nằm ở /port_stat.htm dạng số thập phân `0-71-80-61-180-164` (không khớp mẫu hex ở trên).
    return (await queryHttpNetInfo(ip, timeout: timeout))?.mac;
  }

  /// Đọc cấu hình mạng (MAC, IP, mặt nạ, cổng ra, DHCP bật hay tắt) từ trang web của máy in
  /// (`/port_stat.htm`, cổng 80) — máy in HPRT và các máy dùng cùng module Ethernet. Chỉ ĐỌC,
  /// không đổi gì trên máy in. `null` khi máy không có trang này / không trả lời.
  static Future<LanPrinterNetInfo?> queryHttpNetInfo(
    String ip, {
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .getUrl(Uri.parse('http://$ip/port_stat.htm'))
          .timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(timeout);
      return parseWebNetInfo(body);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Tách cấu hình mạng từ nội dung trang `/port_stat.htm` ([html] thô hoặc đã bỏ thẻ).
  /// `null` khi không đủ MAC + IP. Công khai để test với trang thật.
  static LanPrinterNetInfo? parseWebNetInfo(String html) {
    final text = html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    String? after(String label) => RegExp(
      '$label\\s+([^ ]+)',
      caseSensitive: false,
    ).firstMatch(text)?.group(1);

    // MAC: 6 số thập phân phân cách bằng '-' (VD 0-71-80-61-180-164) hoặc hex AA-BB-... / AA:BB:...
    final rawMac = after(r'Mac\s*Address');
    String? mac;
    if (rawMac != null) {
      final parts = rawMac.split(RegExp('[-:]'));
      if (parts.length == 6) {
        final isHex = parts.every(
          (p) => RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(p),
        );
        final isDec = parts.every((p) {
          final n = int.tryParse(p);
          return n != null && n >= 0 && n <= 255;
        });
        // "10-20-30-40-50-60" khớp cả hai: trang HPRT luôn ghi thập phân, nên ưu tiên thập phân
        // khi có phần tử không phải 2 chữ số hex, còn lại coi là thập phân nếu có ký tự > 99.
        final decimal =
            isDec &&
            (!isHex || parts.any((p) => p.length != 2 || int.parse(p) > 99));
        final bytes = [
          for (final p in parts)
            decimal ? int.parse(p) : int.parse(p, radix: 16),
        ];
        mac = bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(':');
        if (mac == '00:00:00:00:00:00' || mac == 'FF:FF:FF:FF:FF:FF') {
          mac = null;
        }
      }
    }
    final ip = after(r'IP\s*Address');
    if (mac == null ||
        ip == null ||
        !RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip)) {
      return null;
    }
    final dhcp = after('DHCP')?.toLowerCase();
    return LanPrinterNetInfo(
      mac: mac,
      ip: ip,
      mask: after(r'Subnet\s*Mask') ?? '',
      gateway: after(r'Gate\s*Way') ?? '',
      dhcp: dhcp == 'enabled',
    );
  }

  /// Bật DHCP cho máy in qua trang cấu hình web (`/tcpip_cfg.htm`, HPRT và máy cùng module).
  /// ĐỔI cấu hình mạng của máy in: máy chuyển sang nhận IP từ router (IP có thể đổi) nên chỉ gọi khi
  /// người dùng đã đồng ý. Trả `true` khi máy xác nhận "DHCP Enabled" sau khi lưu.
  static Future<bool> enableLanDhcpViaWeb(
    String ip, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final before = await queryHttpNetInfo(ip, timeout: timeout);
    if (before == null) return false;
    if (before.dhcp) return true; // đã bật
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      // Cùng form của trang: dhcp_mode=1 (DHCP Client), DHCP_time=30 (giây chờ cấp IP), nút Save.
      final req = await client
          .getUrl(
            Uri.parse(
              'http://$ip/tcpip_cfg.htm?dhcp_mode=1&DHCP_time=30&save=+Save+',
            ),
          )
          .timeout(timeout);
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
    } catch (_) {
      // Máy đổi mạng ngay khi lưu nên có thể không kịp trả lời: xác nhận bên dưới.
    } finally {
      client.close(force: true);
    }
    // Xác nhận: máy phải đang ở chế độ DHCP (có thể đã đổi IP) — hỏi lại theo MAC trên cùng IP.
    await Future<void>.delayed(const Duration(seconds: 2));
    final after = await queryHttpNetInfo(ip, timeout: timeout);
    return after?.dhcp ?? false;
  }

  // ---------------------------------------------------------------------------

  /// Standalone query port 9100 for printer ID over socket using ESC/POS and TSPL/ZPL.
  /// NOTE: This function sends raw print command payloads to port 9100 and should ONLY
  /// be invoked explicitly on a specific connected printer, NEVER automatically during a network scan.
  static Future<String?> querySocketPrinterName(
    String ip, {
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    Socket? socket;
    StreamSubscription<List<int>>? sub;
    try {
      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 400),
      );

      final rawBytes = <int>[];

      sub = socket.listen(
        (data) {
          rawBytes.addAll(data);
        },
        onError: (_) {},
        onDone: () {},
      );

      // Gửi tập lệnh ESC/POS
      socket.add([
        0x1D, 0x49, 67, // GS I 67 - Model ID
        0x1D, 0x49, 69, // GS I 69 - Manufacturer Name
        0x1D, 0x49, 66, // GS I 66 - Maker Name
        0x1D, 0x49, 2, // GS I 2  - Type ID
      ]);
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 250));

      if (rawBytes.isEmpty) {
        // Gửi tập lệnh TSPL
        socket.add([
          0x7E, 0x21, 0x54, 0x0D, 0x0A, // ~!T
        ]);
        await socket.flush();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (rawBytes.isNotEmpty) {
        final rawText = String.fromCharCodes(rawBytes);
        final tokens = rawText
            .split(RegExp(r'[\x00\r\n\x1F]'))
            .map(
              (s) => s
                  .replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '')
                  .replaceFirst(RegExp(r'^_+'), '')
                  .trim(),
            )
            .where((s) => s.isNotEmpty)
            .toList();

        for (final token in tokens) {
          final formatted = formatPrinterName(token);
          if (formatted != 'Máy in LAN') return formatted;
        }
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      await sub?.cancel();
      socket?.destroy();
    }
  }

  /// Resolves a LAN printer's hardware MAC address using safe, read-only network
  /// queries — trying `XP0001FIND` unicast, SNMP (`ifPhysAddress`), HTTP web config,
  /// and NetBIOS (Unit ID) in parallel, then falling back to the native ARP / neighbor
  /// table (Android only). Returns the first channel to yield a real (non-broadcast,
  /// non-zero) MAC, in that priority order.
  static Future<String?> resolveLanPrinterMac(
    String ip, {
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    // Trả MAC ĐẦU TIÊN có được, không chờ đủ 4 nguồn: nguồn im lặng luôn chờ hết [timeout]
    // (800ms) trong khi máy tự khai MAC (UDP) trả lời trong vài chục ms. Trước đây Future.wait
    // làm máy chỉ nhận ra qua MAC (VD Xprinter) hiện tên chậm ~0,8s. MAC từ nguồn nào cũng là
    // MAC của máy đó nên không cần chờ nguồn "ưu tiên" hơn.
    final sources = <Future<String?>>[
      // MAC do chính firmware máy in tự khai báo — đáng tin nhất, và gửi unicast nên
      // chạy được trên iPhone thật mà không cần entitlement multicast.
      queryXpUdpInfo(ip, timeout: timeout).then((v) => v?.mac),
      querySnmpMac(ip, timeout: timeout),
      queryHttpMac(ip, timeout: timeout),
      queryNetBiosMac(ip, timeout: timeout),
    ];
    final first = Completer<String?>();
    var left = sources.length;
    for (final f in sources) {
      f
          .then<void>((mac) {
            if (mac != null && mac.isNotEmpty && !first.isCompleted) {
              first.complete(mac);
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            if (--left == 0 && !first.isCompleted) first.complete(null);
          });
    }
    final fastMac = await first.future;
    if (fastMac != null) return fastMac;

    try {
      final nativeInfo = await _platform.getLanPrinterInfo(ip: ip);
      final mac = nativeInfo?['mac'] as String?;
      if (mac != null && mac.isNotEmpty) return mac;
    } catch (_) {}

    return null;
  }

  /// Đã có tên hợp lệ từ nguồn ưu tiên thấp thì chờ thêm tối đa ngần này cho
  /// nguồn ưu tiên cao hơn (SNMP) trước khi chốt — xem [getLanPrinterName].
  static const Duration _nameGrace = Duration(milliseconds: 150);

  /// Queries a LAN printer to retrieve its true hardware model and brand name.
  ///
  /// Combines safe, read-only network queries in parallel:
  /// 1. SNMP v1 (UDP 161) — Universal MIB-2, Printer MIB & HPRT Private Enterprise MIB
  /// 2. HPRT UDP Discovery (UDP 3000 / 8888) — Dedicated HPRT / Hanin probe
  /// 3. SSDP / UPnP (UDP 1900) — Universal Plug & Play discovery
  /// 4. mDNS / Bonjour (UDP 5353) — Multicast DNS TXT & PTR records
  /// 5. NetBIOS (UDP 137) — NetBIOS Node Status name query
  /// 6. HTTP Web server (TCP 80) — Title, Headers, and Multi-page inspection
  /// 7. Reverse DNS — PTR lookup
  /// 8. Native Android ARP / Neighbor table — Hardware MAC OUI vendor matching
  ///
  /// All methods are strictly **read-only** and do NOT send any print commands to port 9100,
  /// ensuring 100% safety against unintended printing or paper feed during discovery.
  static Future<String?> getLanPrinterName(
    String ip, {
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    // Máy Gprinter đã tự khai tên model qua gói dò `B[]G`: dùng luôn, khỏi hỏi các nguồn
    // khác (nhanh hơn và đúng tên — các nguồn khác không trả lời với module Gprinter).
    final gprinterName = _gprinterNameByIp[ip.trim()];
    if (gprinterName != null) return gprinterName;
    // Chạy song song tất cả các phương thức an toàn (HOÀN TOÀN KHÔNG GỬI DỮ LIỆU
    // TỚI PORT 9100), xếp theo thứ tự ưu tiên: SNMP trả đúng tên model ghi trên
    // nhãn máy -> HPRT UDP -> SSDP/UPnP -> mDNS -> NetBIOS -> HTTP -> DNS ngược.
    final sources = <Future<String?>>[
      querySnmpPrinterName(
        ip,
        timeout: const Duration(milliseconds: 700),
      ), // [0] SNMP
      queryHprtUdpPrinterName(
        ip,
        timeout: const Duration(milliseconds: 500),
      ), // [1] HPRT UDP
      querySsdpPrinterName(
        ip,
        timeout: const Duration(milliseconds: 500),
      ), // [2] SSDP/UPnP
      queryMdnsPrinterName(
        ip,
        timeout: const Duration(milliseconds: 500),
      ), // [3] mDNS
      queryNetBiosName(
        ip,
        timeout: const Duration(milliseconds: 400),
      ), // [4] NetBIOS
      queryHttpPrinterName(
        ip,
        timeout: const Duration(milliseconds: 500),
      ), // [5] HTTP
      InternetAddress(ip)
          .reverse()
          .timeout(const Duration(milliseconds: 300))
          .then((addr) => addr.host != ip ? addr.host : null), // [6] DNS
      // [7] Native (Android): bảng ARP + tra hãng theo MAC — chỉ đọc bảng của
      // hệ điều hành, trả lời ngay. Trước đây chỉ chạy SAU KHI 7 nguồn trên hết
      // timeout -> máy không trả lời SNMP/mDNS/HTTP (VD PDIT) luôn chờ ~0.8s.
      _platform.getLanPrinterInfo(ip: ip, port: port).then((info) {
        final rawName = info?['rawName'] as String?;
        if (rawName != null && rawName.isNotEmpty) return rawName;
        return info?['vendor'] as String?;
      }),
    ];
    const dnsIndex = 6;
    const nativeIndex = 7;

    // KHÔNG chờ cả 7 nguồn xong: nguồn không trả lời luôn phải chờ hết timeout
    // (SNMP 700ms) trong khi máy in cùng LAN trả lời trong vài chục ms. Trước
    // đây Future.wait làm tên luôn hiện sau ~0.5–1s dù đã có câu trả lời sớm.
    // Quy tắc chọn: lấy nguồn ưu tiên cao nhất ĐÃ có tên hợp lệ, khi mọi nguồn
    // ưu tiên cao hơn nó đã xong; hoặc khi đã có tên hợp lệ được [_nameGrace]
    // mà nguồn cao hơn vẫn im (thường là máy không bật SNMP) -> lấy tên tốt
    // nhất đang có, không chờ hết timeout.
    final formatted = List<String?>.filled(sources.length, null);
    final done = List<bool>.filled(sources.length, false);
    final completer = Completer<String?>();
    Timer? graceTimer;

    String? bestReady({required bool requireHigherDone}) {
      for (var i = 0; i < sources.length; i++) {
        if (formatted[i] != null) return formatted[i];
        if (requireHigherDone && !done[i]) return null;
      }
      return null;
    }

    void decide() {
      if (completer.isCompleted) return;
      final strict = bestReady(requireHigherDone: true);
      if (strict != null) {
        graceTimer?.cancel();
        completer.complete(strict);
        return;
      }
      if (done.every((d) => d)) {
        graceTimer?.cancel();
        completer.complete(null);
        return;
      }
      if (graceTimer == null && formatted.any((n) => n != null)) {
        graceTimer = Timer(_nameGrace, () {
          if (!completer.isCompleted) {
            completer.complete(bestReady(requireHigherDone: false));
          }
        });
      }
    }

    for (var i = 0; i < sources.length; i++) {
      final index = i;
      sources[i]
          .then((raw) {
            if (raw != null && raw.isNotEmpty) {
              final cleaned = index == dnsIndex
                  ? raw.replaceFirst(
                      RegExp(
                        r'\.(local|lan|home|internal)$',
                        caseSensitive: false,
                      ),
                      '',
                    )
                  : raw;
              // Hãng tra theo MAC (native) giữ nguyên, không qua formatPrinterName.
              final name = index == nativeIndex
                  ? cleaned
                  : formatPrinterName(cleaned);
              if (name != 'Máy in LAN') formatted[index] = name;
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            done[index] = true;
            decide();
          });
    }

    return completer.future;
  }

  /// Đo chất lượng mạng từ thiết bị này tới máy in LAN [ip] (🟢 tốt / 🟡 yếu / 🟠 rất yếu /
  /// 🔴 mất kết nối) bằng vài lần bắt tay TCP tới [port] — không gửi byte nào nên máy in
  /// không in gì. Dùng để cảnh báo người dùng trước khi in khi Wi-Fi quán quá tải.
  ///
  /// Chỉ gọi khi cần (mở màn hình in / ngay trước khi in), không đo liên tục: máy in LAN
  /// chỉ nhận một kết nối tại một thời điểm. Xem [LanQuality.measure].
  static Future<LanQuality> checkLanQuality(
    String ip, {
    int port = 9100,
    int samples = 5,
    Duration cacheFor = const Duration(seconds: 10),
  }) =>
      LanQuality.measure(ip, port: port, samples: samples, cacheFor: cacheFor);

  /// Tên/hãng/MAC đã nhận diện theo IP trong phiên chạy app: quét lại (mở lại
  /// màn thêm máy in) hiện tên ngay thay vì chờ hỏi lại máy in.
  static final Map<String, LanDeviceModel> _lanDeviceCache = {};

  /// Discovers LAN printers on the local network and queries their hardware/model names.
  ///
  /// [extraSubnets]: dải khác cần quét thêm, xem [discoverLanPrinters].
  ///
  /// [nameWait]: có giá trị thì máy mới (chưa nhớ tên) không phát ngay bản chỉ có
  /// IP mà chờ tối đa chừng ấy để có tên / hãng — UI hiện máy in là có tên luôn,
  /// không nháy "Máy in LAN 143" rồi mới đổi. Hết giờ (hoặc không nhận diện được)
  /// thì phát bản theo IP. Máy đã nhớ tên ([rememberLanDevices]) phát ngay.
  static const Duration _resolveDetailsCap = Duration(seconds: 4);

  static _SharedLanDiscovery? _activeDiscovery;

  static Stream<LanDeviceModel> discoverLanDevices({
    int port = 9100,
    Duration? timeout,
    bool queryDeviceName = true,
    List<String> extraSubnets = const [],
    Duration? nameWait,
  }) {
    // Đang có lượt dò: dùng CHUNG lượt đó (nhận lại máy đã thấy + máy thấy tiếp). Hai lượt chạy
    // song song (VD hai màn cùng quét) tranh nhau kết nối tới máy in — máy in nhiệt chỉ nhận một
    // kết nối nên mỗi lượt sót một nửa, có lượt treo tới hết hạn mà không thấy máy nào (log
    // 27/11 14:20: 0 máy sau 30s).
    final _SharedLanDiscovery? active = _activeDiscovery;
    if (active != null) return active.join();
    final shared = _SharedLanDiscovery();
    _activeDiscovery = shared;
    _discoverLanDevicesOnce(
      port: port,
      timeout: timeout,
      queryDeviceName: queryDeviceName,
      extraSubnets: extraSubnets,
      nameWait: nameWait,
    ).listen(
      shared.add,
      onError: shared.addError,
      onDone: () {
        if (identical(_activeDiscovery, shared)) _activeDiscovery = null;
        shared.close();
      },
    );
    return shared.join();
  }

  static Stream<LanDeviceModel> _discoverLanDevicesOnce({
    required int port,
    Duration? timeout,
    required bool queryDeviceName,
    required List<String> extraSubnets,
    Duration? nameWait,
  }) {
    // ignore: close_sinks
    final controller = StreamController<LanDeviceModel>();
    final Set<String> emitted = <String>{};

    // Máy đang chờ tên (xem [nameWait]): hết giờ thì phát bản theo IP.
    final Map<String, Timer> waitingName = {};
    void emitIpOnly(String ip) {
      waitingName.remove(ip)?.cancel();
      if (!controller.isClosed) {
        controller.add(LanDeviceModel.fromIp(ip, port: port));
      }
    }

    // Quét song song qua SDK độc quyền (Xprinter/POS UDP broadcast) — nguồn MAC
    // đáng tin cậy nhất hiện có cho các máy in đó, dùng làm fallback cho từng IP bên dưới.
    final Map<String, String> sdkMacByIp = {};
    // Máy trả lời broadcast (UDP) — cả khi cổng in đang bận với thiết bị khác.
    final Set<String> sdkIps = <String>{};
    // Có hạn: bản quét SDK đôi khi không trả về (log 27/11: cả lượt dò treo tới 30s).
    final Future<void> sdkScanDone = scanNetPrinters()
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () => const <Map<String, String>>[],
        )
        .then((list) {
          for (final item in list) {
            final ip = item['ip'];
            final mac = item['mac'];
            if (ip == null || ip.isEmpty) continue;
            sdkIps.add(ip);
            if (mac != null && mac.isNotEmpty) sdkMacByIp[ip] = mac;
          }
        })
        .catchError((_) {});

    // Truy vấn tên/MAC còn đang chạy: quét IP xong vẫn phải chờ chúng rồi mới
    // đóng stream, không thì máy tìm thấy cuối dải (VD .254) mất tên.
    final pending = <Future<void>>[];

    Future<void> resolveDetails(String ip) async {
      String? modelName;
      String? mac;
      LanDeviceModel? last = _lanDeviceCache[ip];
      bool? dhcp;

      // Phát lại mỗi khi có thêm thông tin (tên trước, MAC sau) — UI cập nhật
      // theo IP nên hiện tên ngay khi có, không chờ MAC / bản quét SDK.
      void emit() {
        // Không đoán được hãng từ tên model (hoặc không có tên) -> tra theo MAC.
        // Trên iOS đây là đường DUY NHẤT nhận ra các máy không trả tên qua
        // SNMP/mDNS/HTTP (VD PDIT), vì iOS không có bảng OUI native như Android.
        final vendor =
            (modelName != null ? detectVendor(modelName!) : null) ??
            vendorFromMac(mac);
        final displayName = (vendor != null && vendor.isNotEmpty)
            ? vendor
            : modelName;
        if (controller.isClosed ||
            (displayName == null && mac == null && dhcp == null)) {
          return;
        }
        final device = LanDeviceModel.fromIp(
          ip,
          // Chưa nhận ra tên lần này thì giữ tên đã nhớ từ lần quét trước.
          name: displayName ?? last?.name,
          vendor: vendor ?? last?.vendor,
          port: port,
          mac: mac ?? last?.mac,
          dhcp: dhcp ?? last?.dhcp,
        );
        final prev = last;
        if (prev != null &&
            prev.name == device.name &&
            prev.vendor == device.vendor &&
            prev.mac == device.mac &&
            prev.dhcp == device.dhcp) {
          return;
        }
        last = device;
        _lanDeviceCache[ip] = device;
        waitingName.remove(ip)?.cancel();
        controller.add(device);
      }

      try {
        await Future.wait([
          getLanPrinterName(ip, port: port).then((v) {
            modelName = v;
            emit();
          }),
          // Cấu hình mạng qua trang web của máy in (HPRT...): biết máy đang TẮT DHCP (IP tĩnh) và
          // thêm MAC cho máy không trả lời các nguồn khác. Chỉ đọc, một lần GET nhỏ.
          queryHttpNetInfo(ip, timeout: const Duration(milliseconds: 600)).then(
            (info) {
              if (info == null) return;
              dhcp = info.dhcp;
              mac ??= info.mac;
              emit();
            },
          ),
          Future.wait([
            resolveLanPrinterMac(ip).then((v) => mac = v ?? mac),
            sdkScanDone,
          ]).then((_) {
            mac ??= sdkMacByIp[ip];
            emit();
          }),
        ]);
      } catch (_) {}
    }

    void onIp(String ip) {
      if (!emitted.add(ip) || controller.isClosed) return;

      // 1. Máy đã gặp (nhớ tên) thì hiện ngay tên đã nhớ, vẫn hỏi lại bên dưới để
      // cập nhật nếu đổi máy. Máy mới: phát ngay với IP (< 100ms), hoặc chờ có
      // tên nếu đặt [nameWait].
      final cached = _lanDeviceCache[ip];
      if (cached != null) {
        controller.add(cached);
      } else if (nameWait == null || !queryDeviceName) {
        controller.add(LanDeviceModel.fromIp(ip, port: port));
      } else {
        waitingName[ip] = Timer(nameWait, () => emitIpOnly(ip));
      }

      if (!queryDeviceName) return;

      // 2. Tự động truy vấn tên model, hãng và MAC ở chế độ nền. Mỗi máy tối đa
      // [_resolveDetailsCap]: một máy không trả lời (VD máy in tem bỏ qua SNMP/HTTP) không
      // được giữ cả lượt dò — trước đây stream chỉ đóng khi MỌI máy hỏi xong (đã gặp 30s).
      // Thông tin về muộn vẫn được phát nếu stream còn mở, và vẫn vào bộ nhớ tên đã biết.
      pending.add(
        resolveDetails(ip).timeout(_resolveDetailsCap, onTimeout: () {}),
      );
    }

    // Máy in trả lời broadcast mà CÙNG dải với thiết bị: là máy in dùng được, kể cả khi lượt dò
    // cổng 9100 bỏ sót (máy in nhiệt chỉ nhận một kết nối — đang in / đang bị thiết bị khác giữ
    // thì từ chối, kết quả quét "lúc thấy lúc không": log 27/11 14:19–14:20 cùng một máy lần thấy
    // 3, lần 1, lần 2 máy). Máy khác dải là việc của mục "máy lệch dải", không thêm ở đây.
    final Future<void> sdkFeed = sdkScanDone
        .then((_) async {
          if (sdkIps.isEmpty) return;
          final Set<String> mySubnets = {
            for (final ip in await _localPrivateIpv4s())
              ip.split('.').take(3).join('.'),
          };
          for (final ip in sdkIps) {
            if (mySubnets.contains(ip.split('.').take(3).join('.'))) onIp(ip);
          }
        })
        .catchError((_) {});

    discoverLanPrinters(
      port: port,
      timeout: timeout,
      extraSubnets: extraSubnets,
    ).listen(
      onIp,
      onError: (err) {
        if (!controller.isClosed) controller.addError(err);
      },
      onDone: () async {
        await sdkFeed;
        await Future.wait(pending);
        // Máy không nhận diện được tên vẫn phải hiện ra.
        for (final ip in waitingName.keys.toList()) {
          emitIpOnly(ip);
        }
        if (!controller.isClosed) await controller.close();
      },
    );

    return controller.stream;
  }

  /// Tên / hãng / MAC đã nhận diện được (theo IP) — để app lưu lại qua các lần mở
  /// và nạp lại bằng [rememberLanDevices].
  static List<LanDeviceModel> get knownLanDevices =>
      List.unmodifiable(_lanDeviceCache.values);

  /// Nạp tên máy in đã biết (VD lưu từ lần mở app trước, xem [knownLanDevices]):
  /// lần quét sau hiện đúng tên ngay khi vừa thấy máy.
  static void rememberLanDevices(Iterable<LanDeviceModel> devices) {
    for (final device in devices) {
      _lanDeviceCache.putIfAbsent(device.ip, () => device);
    }
  }

  /// Android only. Signals a connected USB printer (e.g. right after the user
  /// granted USB permission) so the user can tell which physical printer it is.
  ///
  /// The app cannot know whether the printer has a buzzer or speaks ESC/POS or
  /// TSPL, so everything is sent at once: the [identifyLanPrinter] beep, a TSPL
  /// `FEED` (label printers nudge the paper ~3mm instead of wasting a label) and,
  /// when [slipText] is given, a short ESC/POS slip that is then cut (label
  /// printers ignore it). TSPL text lines are sent BEFORE the slip so receipt
  /// printers print them on the slip, not on top of the next receipt.
  /// [slipText] should be plain ASCII (no diacritics).
  /// Returns `false` if nothing was sent.
  static Future<bool> identifyUsbPrinter({
    required String deviceId,
    bool beep = true,
    bool feed = true,
    String? slipText,
  }) async {
    final payload = _identifyPayload(beep: beep, feed: feed);
    if (slipText != null && slipText.isNotEmpty) {
      payload.addAll([
        0x1B, 0x40, // ESC @ - Initialize
        0x1B, 0x61, 0x01, // Center align
        ...utf8.encode("\n$slipText\n\n\n\n"),
        0x1D, 0x56, 0x42, 0x00, // Cut paper
      ]);
    }
    if (payload.isEmpty) return true;
    return _platform.sendRawBytes(deviceId: deviceId, bytes: payload);
  }

  /// Lệnh còi / nhích giấy dùng chung cho mọi loại máy (ESC/POS + TSPL/CPCL/ZPL).
  ///
  /// [escpos] / [tspl]: chỉ gồm mã của loại máy tương ứng. Máy in hoá đơn KHÔNG hiểu lệnh tem
  /// dạng chữ (`SOUND`, `! U1 BEEP`, `FEED`...) nên in nguyên văn ra giấy thành ký tự lạ.
  static List<int> _identifyPayload({
    required bool beep,
    required bool feed,
    bool escpos = true,
    bool tspl = true,
    String? vendor,
  }) {
    final payload = <int>[];

    if (beep && escpos) {
      // --- 1. ESC/POS: mã còi theo HÃNG ---
      // Trước đây gửi cả loạt mã của mọi hãng. Máy không hiểu mã nào thì in tham số của mã đó ra
      // giấy (`ESC ( A`, `GS ( A`, `1F 1B 1F 53`...) hoặc hiểu NHẦM thành lệnh khác: `ESC C n` đặt
      // chiều dài trang = n dòng nên máy đẩy giấy dài sau mỗi dòng (cả các lần in sau, vì không có
      // lệnh nào hủy), `ESC p` mở két. Bấm loa nhiều lần ra "đống giấy". Nay chỉ gửi mã chung (BEL +
      // `ESC B n t`, còi chuẩn của máy POS) cộng mã riêng của đúng hãng nếu nhận ra hãng.
      payload.addAll([0x07, 0x1B, 0x42, 0x01, 0x01]);
      switch ((vendor ?? '').toLowerCase()) {
        case 'xprinter':
          payload.addAll([0x1F, 0x1B, 0x1F, 0x53, 0x01]);
        case 'rongta' || 'gprinter':
          payload.addAll([0x1B, 0x43, 0x01, 0x01]);
        case 'epson':
          payload.addAll([
            0x1B,
            0x28,
            0x41,
            0x02,
            0x00,
            0x30,
            0x01,
            0x1D,
            0x28,
            0x41,
            0x02,
            0x00,
            0x30,
            0x01,
            0x1B,
            0x28,
            0x41,
            0x04,
            0x00,
            0x30,
            0x01,
            0x01,
            0x01,
            0x1D,
            0x28,
            0x41,
            0x04,
            0x00,
            0x30,
            0x01,
            0x01,
            0x01,
          ]);
        case 'citizen':
          payload.addAll([0x1B, 0x1E]);
        case 'star':
          payload.addAll([0x1B, 0x07]);
      }
      // Hủy mọi trạng thái còn lại (kiểu chữ, chiều dài trang...) để lần in sau không bị ảnh hưởng.
      payload.addAll([0x1B, 0x40]);
    }

    if (beep && tspl) {
      // --- 2. TSPL / CPCL / ZPL Buzzer (Máy in tem: Kêu 1 tiếng ngắn) ---
      payload.addAll(
        utf8.encode(
          "\r\n\r\n"
          "SOUND 1,200\r\n"
          "! U1 BEEP 1\r\n"
          "~JB\r\n",
        ),
      );
    }

    if (feed) {
      // Nhích nhẹ 1 nhịp giấy (~3mm) để vừa nghe tiếng motor vừa thấy giấy nhích
      if (tspl) {
        payload.addAll(utf8.encode("\r\nFEED 24\r\n")); // TSPL: feed 24 dots
      }
      if (escpos) payload.addAll([0x1B, 0x4A, 0x18]); // ESC/POS: ESC J 24 dots
    }

    return payload;
  }

  static final Map<String, (PrinterLanguage, DateTime)> _identifyLanguage = {};

  /// Sends an identify signal (audio beep, paper feed, or test slip) to a LAN printer to help
  /// the user physically determine which printer on their desk matches [ipAddress].
  static Future<bool> identifyLanPrinter({
    required String ipAddress,
    int port = 9100,
    bool beep = true,
    bool feed = true,
    bool printSlip = false,
    Duration timeout = const Duration(seconds: 2),

    /// Hỏi máy in là hoá đơn hay tem trước rồi chỉ gửi mã của loại đó (mất thêm ~1,5s). Tắt
    /// = gửi mã của cả hai loại như trước (máy in hoá đơn có thể in ký tự lạ).
    bool detectType = true,
  }) async {
    var escpos = true;
    var tspl = true;
    if (detectType) {
      // Loại máy nhớ vài phút theo IP: bấm kêu lại nhiều lần không phải hỏi máy (~1,5s) mỗi lần.
      final key = '$ipAddress:$port';
      final cached = _identifyLanguage[key];
      PrinterLanguage language;
      if (cached != null &&
          DateTime.now().difference(cached.$2) < const Duration(minutes: 5)) {
        language = cached.$1;
      } else {
        try {
          language = await PrinterLanguageProbe.probeLan(ipAddress, port: port);
        } catch (_) {
          language = PrinterLanguage.unknown;
        }
        // Chỉ nhớ khi máy đã trả lời (unknown có thể do máy đang bận).
        if (language != PrinterLanguage.unknown) {
          _identifyLanguage[key] = (language, DateTime.now());
        }
      }
      // Máy tem chỉ nhận lệnh tem; máy hoá đơn (và máy không trả lời — phần lớn là máy hoá đơn)
      // chỉ nhận lệnh ESC/POS; máy hai chế độ nhận cả hai.
      escpos = language != PrinterLanguage.label;
      tspl =
          language == PrinterLanguage.label || language == PrinterLanguage.both;
    }
    // Hãng (nhận ra khi quét: theo tên model / MAC): chọn mã còi đúng hãng, xem [_identifyPayload].
    final vendor =
        _lanDeviceCache[ipAddress]?.vendor ??
        detectVendor(_lanDeviceCache[ipAddress]?.name ?? '');
    final payload = _identifyPayload(
      beep: beep,
      feed: feed,
      escpos: escpos,
      tspl: tspl,
      vendor: vendor,
    );

    if (printSlip) {
      // ESC/POS Test Slip
      payload.addAll([
        0x1B, 0x40, // ESC @ - Initialize
        0x1B, 0x61, 0x01, // Center align
        ...utf8.encode("\n=== XAC DINH MAY IN ===\n"),
        ...utf8.encode("IP: $ipAddress\n"),
        ...utf8.encode("Port: $port\n"),
        ...utf8.encode("=======================\n\n\n"),
        0x1D, 0x56, 0x42, 0x00, // Cut paper
      ]);
    }

    if (payload.isEmpty) return true;

    // 1. Thử gửi qua Native Platform Channel (Sử dụng Apple NWConnection trên iOS)
    try {
      final nativeOk = await _platform.identifyLanPrinter(
        ipAddress: ipAddress,
        bytes: payload,
        port: port,
      );
      if (nativeOk) return true;
    } catch (_) {}

    // 2. Dự phòng: Gửi trực tiếp qua Socket Dart nếu native không hỗ trợ
    Socket? socket;
    try {
      socket = await Socket.connect(ipAddress, port, timeout: timeout);
      socket.add(payload);
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 350));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// Prints labels using TSPL commands from [labelModel].
  ///
  /// Specify [deviceId] and [connectionType] to print to a specific target printer.
  static Future<void> printLabel({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required LabelModel labelModel,
  }) async {
    await _guardTsplTarget(deviceId);
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
    await _guardTsplTarget(deviceId);
    return await _platform.printImage(
      deviceId: deviceId,
      connectionType: connectionType,
      imageModel: imageModel,
    );
  }

  /// Prints a thermal receipt using ESC/POS commands from [printThermalModel].
  /// In hóa đơn nhiệt bằng lệnh ESC/POS.
  ///
  /// Đặt [openDrawer] = true khi thanh toán TIỀN MẶT để mở két cùng lúc. Két được mở
  /// TRƯỚC khi gửi bill nên bật gần như tức thì: lệnh mở két chỉ vài byte, còn bill có
  /// thể 70–85KB và cả hai đi chung một hàng đợi tuần tự tới máy in — nếu mở sau thì thu
  /// ngân phải đợi hết cuộn giấy (qua Bluetooth là vài chục giây).
  ///
  /// Chỉ bật cho tiền mặt. Thẻ/QR/chuyển khoản, in tạm tính, in lại hóa đơn cũ, in
  /// bếp/bar đều để mặc định false — mở két thừa là rủi ro kiểm soát tiền.
  ///
  /// Lỗi mở két KHÔNG chặn việc in (khách cần hóa đơn hơn cần két), nên hàm này không
  /// cho biết két có mở được không. Cần biết kết quả thì gọi [openDrawer] riêng trước.
  /// [quantity] số bản in. Truyền vào đây thay vì tự lặp `printESC` nhiều lần: native sẽ
  /// in hết các bản trong MỘT lời gọi, giữ socket liên tục từ bản đầu tới bản cuối.
  ///
  /// Lặp ở tầng Dart tạo khoảng trống giữa hai bản mà không job nào giữ socket — với máy
  /// in LAN dùng chung, socket bị nhả ngay ở đó và bản kế phải mở lại, đụng socket chưa
  /// giải phóng hẳn ("Máy in đang bận, thử lại sau 400ms...") -> in chậm, có bản không ra.
  static Future<void> printESC({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required PrintThermalModel printThermalModel,
    bool openDrawer = false,
    int quantity = 1,
  }) async {
    _guardEscTarget(deviceId);
    if (openDrawer) {
      try {
        // Gửi ESC p tới ĐÚNG MÁY ĐANG IN lượt này (deviceId ở trên), không phát tràn.
        //
        // Không có trường nào cho biết máy in nào gắn két, nhưng KHÔNG cần biết: chỉ cần
        // giới hạn vào tập máy đang in. Máy có két và đang in -> mở; máy đang in mà không
        // có két -> ESC p vô hại, bỏ qua; máy có két nhưng KHÔNG in lượt này -> không đụng
        // tới, nên in bếp/bar hay in ở quầy khác không làm bật két thu ngân.
        //
        // Phát tới MỌI máy đang kết nối thì két luôn mở được, nhưng mở cả khi in ở máy
        // khác — sai nghiệp vụ. Còn để native tự chọn "máy đầu danh sách" thì kết quả phụ
        // thuộc THỨ TỰ KẾT NỐI (nối máy không két trước là hỏng).
        await PrinterLabel.openDrawer(
          deviceId: deviceId,
          connectionType: connectionType,
        );
      } catch (_) {
        // Nuốt lỗi có chủ đích — xem doc ở trên.
      }
    }
    return await _platform.printESC(
      deviceId: deviceId,
      connectionType: connectionType,
      printThermalModel: printThermalModel,
      quantity: quantity,
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
  static Future<List<BluetoothDeviceModel>> getBluetoothDevices({
    bool filterPrinterOnly = true,
  }) async {
    return await _platform.getBluetoothDevices(
      filterPrinterOnly: filterPrinterOnly,
    );
  }

  /// Stream emitting discover.                       ed Bluetooth devices during active scans.
  ///
  /// If [filterPrinterOnly] is true (default), only devices recognized as printers are emitted.
  /// Call [startBluetoothScan] before listening to this stream on iOS.
  static Stream<BluetoothDeviceModel> bluetoothScanStream({
    bool filterPrinterOnly = true,
  }) => _platform.bluetoothScanStream(filterPrinterOnly: filterPrinterOnly);

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

  /// Scans the local network for printers returning their MAC and IP.
  /// This uses the proprietary UDP broadcast (Xprinter SDK) on Android
  /// and `PTDispatcher.scanDeviceAtLAN` on iOS.
  /// Thu ảnh một hàng tem (thường chụp ở pixelRatio 3, VD 1470px cho hàng 2 tem
  /// 35mm) về đúng số chấm máy in in được trên chiều ngang hàng tem
  /// (`stampWidth × count × dotsPerMm`, VD 560 chấm ở 203dpi) — nhỏ hơn nhiều lần
  /// để gửi qua mạng, máy in cũng không in mịn hơn được. Ảnh đã nhỏ hơn thì giữ
  /// nguyên; lỗi thì trả ảnh gốc.
  static Future<Uint8List> shrinkLabelImage(
    Uint8List image,
    LabelPerRow size, {
    double dotsPerMm = 8,
  }) async {
    try {
      final targetWidth = (size.stampWidth * size.count * dotsPerMm).round();
      final codec = await ui.instantiateImageCodec(image);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      frame.image.dispose();
      if (targetWidth <= 0 || width <= targetWidth) return image;
      final scaled = await ui.instantiateImageCodec(
        image,
        targetWidth: targetWidth,
      );
      final scaledFrame = await scaled.getNextFrame();
      final data = await scaledFrame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      scaledFrame.image.dispose();
      return data == null ? image : data.buffer.asUint8List();
    } catch (_) {
      return image;
    }
  }

  // ---------------------------------------------------------------------------
  // Chạy nền (Android)
  // ---------------------------------------------------------------------------

  /// Android only. Bật dịch vụ chạy nền để app vẫn in được khi tắt màn hình (VD
  /// máy làm "trạm in" nhận lệnh in từ máy khác): thông báo cố định [title] /
  /// [text] (gọi lại để cập nhật nội dung), giữ CPU và Wi-Fi thức. [channelName]
  /// là tên nhóm thông báo trong cài đặt hệ thống. Có [stopLabel] thì thông báo có
  /// nút dừng — người dùng bấm thì [keepAliveStoppedByUser] phát.
  ///
  /// Trả `false` khi không bật được: không phải Android, hoặc Android 12+ không cho
  /// bật lúc app đang ở nền (hãy gọi khi app đang mở). Android 13+ cần quyền
  /// thông báo để thông báo hiện ra (dịch vụ vẫn chạy nếu bị từ chối) —
  /// [requestPermission] để plugin tự xin trước khi bật.
  static Future<bool> startKeepAlive({
    required String title,
    required String text,
    String? channelName,
    String? stopLabel,
    bool requestPermission = false,
  }) => _platform.startKeepAlive(
    title: title,
    text: text,
    channelName: channelName ?? title,
    stopLabel: stopLabel,
    requestPermission: requestPermission,
  );

  /// Nhận chữ trong ảnh [imagePath] (chạy trên máy, không gửi ảnh đi): iOS dùng
  /// Vision của Apple (chạy cả Simulator), Android dùng ML Kit. Mỗi dòng chữ một
  /// hàng; `null` khi không đọc được.
  static Future<String?> recognizeText(String imagePath) =>
      _platform.recognizeText(imagePath);

  /// Android only. Mã phần cứng ổn định của máy — giống nhau giữa các bản build /
  /// app trên cùng máy (Android ≤ 7.1: số serial; 8+: ANDROID_ID). `null` khi
  /// không đọc được. App băm ra trước khi dùng, không gửi mã gốc đi.
  static Future<String?> deviceId() => _platform.deviceId();

  /// Android only. Tên máy người dùng đặt trong Cài đặt (Android 7.1+: tên thiết
  /// bị; máy cũ như Android 6: tên Bluetooth). `null` khi không đọc được.
  static Future<String?> deviceName() => _platform.deviceName();

  /// Android only. Máy Agent tự khởi động lại được không: khi bật máy / app bị hệ
  /// thống tắt, plugin mở lại app (đang bật [startKeepAlive]). Android 10+ cần quyền
  /// "Hiển thị trên ứng dụng khác" ([requestAutoRestart]); Android 6–9 luôn được.
  static Future<bool> canAutoRestart() => _platform.canAutoRestart();

  /// Android only. Mở màn cấp quyền "Hiển thị trên ứng dụng khác" để máy Agent tự
  /// mở lại app sau khi khởi động máy / bị hệ thống tắt.
  static Future<bool> requestAutoRestart() => _platform.requestAutoRestart();

  /// Android only. Dừng dịch vụ chạy nền.
  static Future<void> stopKeepAlive() => _platform.stopKeepAlive();

  /// iOS only. Giữ màn hình sáng ([on]) cho máy làm trạm in (iOS khoá màn hình là treo
  /// kết nối nền). Nơi khác `false`.
  static Future<bool> setKeepScreenOn(bool on) => _platform.setKeepScreenOn(on);

  /// Android only. Ứng dụng đã được miễn "tối ưu hoá pin" chưa (nơi khác `true`).
  static Future<bool> isIgnoringBatteryOptimizations() =>
      _platform.isIgnoringBatteryOptimizations();

  /// Android only. Mở danh sách "Tối ưu hoá pin" của hệ thống.
  static Future<bool> openBatteryOptimizationSettings() =>
      _platform.openBatteryOptimizationSettings();

  /// Android only. Dịch vụ chạy nền đang chạy không.
  static Future<bool> isKeepAliveRunning() => _platform.isKeepAliveRunning();

  /// Android only. Máy in USB [deviceId] (dạng `USB:...`, xem [DeviceId.usb]) có
  /// đang cắm vào máy này không — chỉ đọc danh sách thiết bị USB, không kết nối và
  /// không hỏi quyền. Nơi khác luôn `false` (iOS không in USB).
  static Future<bool> isUsbAttached(String deviceId) =>
      _platform.isUsbAttached(deviceId);

  /// Wi-Fi thiết bị đang kết nối (để nhớ máy in nằm ở Wi-Fi nào và gợi ý chuyển
  /// đúng Wi-Fi khi in lỗi). `null` khi không bắt Wi-Fi. Tên Wi-Fi cần quyền vị
  /// trí (Android: đã cấp + bật định vị; iOS: thêm entitlement "Access WiFi
  /// Information") — thiếu thì [WifiNetworkInfo.ssid] là `null`.
  static Future<WifiNetworkInfo?> currentWifi() async {
    final m = await _platform.currentWifi();
    if (m == null) return null;
    return WifiNetworkInfo(
      ssid: m['ssid']?.toString(),
      bssid: m['bssid']?.toString(),
    );
  }

  /// Android only. Tên các Wi-Fi đang có sóng xung quanh (mạnh trước) — để biết
  /// Wi-Fi của máy in có ở gần không. iOS luôn rỗng (Apple không cho quét).
  static Future<List<String>> nearbyWifi() => _platform.nearbyWifi();

  /// Android only. Wi-Fi xung quanh kèm BSSID (MAC bộ phát — giữ nguyên khi Wi-Fi
  /// đổi tên / mật khẩu), sóng mạnh trước; mỗi điểm phát một dòng (router 2 băng
  /// tần / mesh có nhiều BSSID cùng tên). iOS trả rỗng (không cho quét Wi-Fi).
  static Future<List<WifiNetworkInfo>> nearbyWifiNetworks() async => [
    for (final m in await _platform.nearbyWifiNetworks())
      WifiNetworkInfo(
        ssid: m['ssid']?.toString(),
        bssid: m['bssid']?.toString().toLowerCase(),
      ),
  ];

  /// Android only. Mở bảng chọn Wi-Fi (Android 10+: bảng nổi ngay trong app).
  /// iOS trả `false` — hãy hướng dẫn người dùng vào Cài đặt → Wi-Fi.
  static Future<bool> openWifiSettings() => _platform.openWifiSettings();

  /// Nối TẠM sang Wi-Fi [ssid] của máy in để in khi thiết bị đang ở Wi-Fi khác,
  /// in xong gọi [leavePrinterWifi] để về như cũ.
  ///
  /// - Android 10+: hệ điều hành nối riêng cho app (lần đầu hỏi người dùng xác
  ///   nhận), socket tới máy in tự đi qua mạng này; máy rời Wi-Fi cũ trong lúc in.
  /// - Android 6–9: chuyển hẳn Wi-Fi rồi chuyển lại khi [leavePrinterWifi].
  /// - iOS: `NEHotspotConfiguration` (cần entitlement "Hotspot Configuration").
  ///
  /// Trả `true` khi đã nối được. [password] rỗng = Wi-Fi không mật khẩu.
  ///
  /// [stay] = `true`: ở lại Wi-Fi máy in sau khi in (không gọi
  /// [leavePrinterWifi]) — Android 10+: app giữ mạng này tới khi app tắt hoặc nối
  /// Wi-Fi máy in khác; Android 6–9: không chuyển lại Wi-Fi cũ; iOS: lưu mạng.
  static Future<bool> joinPrinterWifi({
    required String ssid,
    String password = '',
    Duration timeout = const Duration(seconds: 15),
    bool stay = false,
  }) => _platform.joinPrinterWifi(
    ssid: ssid,
    password: password,
    timeout: timeout,
    stay: stay,
  );

  /// Trả Wi-Fi đã nối bằng [joinPrinterWifi], thiết bị về Wi-Fi trước đó.
  static Future<void> leavePrinterWifi() => _platform.leavePrinterWifi();

  /// Phát khi người dùng bấm nút dừng trên thông báo chạy nền.
  static Stream<void> get keepAliveStoppedByUser =>
      _platform.keepAliveStoppedByUser;

  static Future<List<Map<String, String>>> scanNetPrinters() {
    // Dùng chung kết quả broadcast trong vài giây: [discoverLanDevices] và
    // [findLanPrinterIssues] chạy cùng lúc không phải broadcast hai lần.
    final recent = _recentNetScan;
    if (recent != null &&
        DateTime.now().difference(_recentNetScanAt) < _netScanShare) {
      return recent;
    }
    _recentNetScanAt = DateTime.now();
    // SDK (XP0001FIND: Xprinter, PDIT...) và broadcast theo giao thức hãng (Epson,
    // Star) chạy song song; gộp theo IP, ưu tiên bản SDK (có sẵn MAC).
    final future = Future.wait([_sdkScanShared(), scanVendorBroadcast()]).then((
      lists,
    ) {
      final byIp = <String, Map<String, String>>{};
      for (final item in [...lists[0], ...lists[1]]) {
        final ip = item['ip'];
        if (ip != null && ip.isNotEmpty) byIp.putIfAbsent(ip, () => item);
      }
      return byIp.values.toList();
    });
    _recentNetScan = future;
    future.catchError((_) {
      _recentNetScan = null;
      return <Map<String, String>>[];
    });
    return future;
  }

  /// Tìm máy in Epson / Star bằng gói broadcast của chính hãng — trả lời được cả khi
  /// máy in nằm khác dải IP (chung switch / mạng dây), giống `XP0001FIND` của Xprinter:
  /// - Epson (EpsonNet / ENPC): UDP 3289, gói `EPSONQ...`, máy in trả `EPSONq...`.
  /// - Star (StarIO): UDP 22222, gói `STR_BCAST...RQ1.0.0`.
  /// - Gói chung `FIND_POS_PRINTER` tới UDP 3000 / 4000 / 1460 / 5000.
  ///
  /// Trả `[{ip, mac?, vendor}]`. MAC lấy từ gói trả lời nếu đọc được, không thì để
  /// trống (nơi gọi hỏi tiếp qua [resolveLanPrinterMac]).
  ///
  /// Chưa thử trên máy Epson / Star thật — định dạng gói theo tài liệu hãng và các
  /// bộ thư viện mở; máy không trả lời thì danh sách rỗng, không ảnh hưởng luồng cũ.
  static Future<List<Map<String, String>>> scanVendorBroadcast({
    Duration wait = const Duration(milliseconds: 1500),
  }) async {
    final found = <String, Map<String, String>>{};
    final locals = (await _localPrivateIpv4s()).toSet();
    final sockets = <RawDatagramSocket>[];

    Future<void> probe({
      required int port,
      required List<List<int>> payloads,
      required String vendor,
      required bool Function(List<int> data) matches,
      String? Function(List<int> data)? macOf,
      bool bindSamePort = true,
    }) async {
      RawDatagramSocket socket;
      try {
        // Star trả lời về đúng cổng 22222: cố bind cổng đó, bận thì dùng cổng bất kỳ.
        socket = bindSamePort
            ? await RawDatagramSocket.bind(
                InternetAddress.anyIPv4,
                port,
              ).catchError(
                (_) => RawDatagramSocket.bind(InternetAddress.anyIPv4, 0),
              )
            : await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      } catch (_) {
        return;
      }
      sockets.add(socket);
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;
        final ip = dg.address.address;
        if (locals.contains(ip) || !matches(dg.data)) return;
        final mac = macOf?.call(dg.data);
        found.putIfAbsent(
          ip,
          () => {'ip': ip, 'vendor': vendor, if (mac != null) 'mac': mac},
        );
        // Mạng chặn broadcast ("No route to host"): lỗi gửi báo qua stream — bỏ qua.
      }, onError: (Object _) {});
      final targets = {
        InternetAddress('255.255.255.255'),
        for (final ip in locals)
          InternetAddress('${ip.split('.').take(3).join('.')}.255'),
      };
      for (final payload in payloads) {
        for (final target in targets) {
          try {
            socket.send(payload, target, port);
          } catch (_) {}
        }
      }
    }

    bool startsWith(List<int> data, String prefix) =>
        data.length >= prefix.length &&
        String.fromCharCodes(data.take(prefix.length)) == prefix;

    await Future.wait([
      probe(
        port: 3289,
        vendor: 'Epson',
        payloads: [
          [
            ...ascii.encode('EPSONQ'),
            0x03,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
          ],
        ],
        matches: (d) => startsWith(d, 'EPSONq') || startsWith(d, 'EPSON'),
      ),
      probe(
        port: 22222,
        vendor: 'Star',
        payloads: [
          [
            ...ascii.encode('STR_BCAST'),
            ...List.filled(7, 0),
            ...ascii.encode('RQ1.0.0'),
            0x00,
            0x00,
            0x1C,
            0x64,
            0x31,
          ],
        ],
        // Bỏ chính gói hỏi bị dội lại (bắt đầu `STR_BCAST` + `RQ`).
        matches: (d) =>
            startsWith(d, 'STR_BCAST') &&
            !String.fromCharCodes(d).contains('RQ1.0.0'),
        macOf: _starMacOf,
      ),
      // Gói dò chung `FIND_POS_PRINTER` (cổng 3000 / 4000 / 1460 / 5000) theo tài
      // liệu kỹ thuật POS: máy in / hộp mạng nào trả lời thì ghi nhận IP.
      for (final genericPort in _genericFindPorts)
        probe(
          port: genericPort,
          vendor: 'POS',
          bindSamePort: false,
          payloads: [ascii.encode(_genericFindPayload)],
          // Nhiều hộp mạng ESC/POS trả lời bằng CHÍNH chuỗi dò (dội lại, nguồn là IP máy in).
          // Socket này bind cổng ngẫu nhiên nên chỉ nhận được gói trả lời gửi riêng cho nó,
          // còn gói dội của chính máy này đã bị loại ở trên (theo IP máy).
          matches: (_) => true,
        ),
    ]);
    await Future.delayed(wait);
    for (final s in sockets) {
      s.close();
    }
    return found.values.toList();
  }

  /// Máy in ESC/POS trả lời gói dò chung nhưng đang ở dải IP KHÁC thiết bị (điện thoại không
  /// tới được, và không có giao thức đổi IP): trả danh sách IP để báo người dùng. Máy đã có
  /// MAC (Xprinter...) do [findLanPrinterIssues] xử lý nên không lặp lại ở đây.
  static Future<List<String>> findOtherSubnetPosPrinters() async {
    final localPrefixes = (await _localPrivateIpv4s())
        .map((ip) => ip.split('.').take(3).join('.'))
        .toSet();
    if (localPrefixes.isEmpty) return const [];
    final xpIps = {
      for (final item in await _sdkScanShared())
        if (item['ip'] != null) item['ip']!,
    };
    final found = await scanVendorBroadcast();
    return [
      for (final item in found)
        if (item['ip'] != null &&
            !xpIps.contains(item['ip']) &&
            !localPrefixes.contains(item['ip']!.split('.').take(3).join('.')))
          item['ip']!,
    ];
  }

  static const String _genericFindPayload = 'FIND_POS_PRINTER';
  static const List<int> _genericFindPorts = [3000, 4000, 1460, 5000];

  /// MAC trong gói trả lời Star: chuỗi dạng `00:11:62:xx:xx:xx` (OUI của Star).
  static String? _starMacOf(List<int> data) {
    final text = String.fromCharCodes(
      data.map((b) => b >= 0x20 && b < 0x7F ? b : 0x20),
    );
    final m = RegExp(r'([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}').firstMatch(text);
    return m == null ? null : normalizeMac(m.group(0));
  }

  /// [data] là một trong các gói đã gửi bị dội lại nguyên vẹn.
  static bool _isEcho(List<int> data, List<List<int>> sent) => sent.any(
    (p) =>
        p.length == data.length &&
        Iterable<int>.generate(p.length).every((i) => p[i] == data[i]),
  );

  /// Máy [ip] đã biết là Gprinter (trả lời gói dò `B[]G`, hoặc MAC module Gprinter).
  static bool _isKnownGprinter(String ip) {
    if (_gprinterNameByIp.containsKey(ip)) return true;
    final mac = normalizeMac(_lanDeviceCache[ip]?.mac);
    return mac != null &&
        (_gprinterMacs.contains(mac) || mac.startsWith('00:47:50'));
  }

  /// MAC các máy in nói giao thức Gprinter (UDP `B[]G`), điền sau mỗi lần dò.
  static final Set<String> _gprinterMacs = <String>{};

  /// Tên model module mạng Gprinter tự khai (`DEVICENAME`), theo MAC / IP — điền
  /// sau mỗi lần dò, dùng để nhận ra máy hoá đơn (xem [detectLanPrinterLanguage]).
  static final Map<String, String> _gprinterNameByMac = <String, String>{};
  static final Map<String, String> _gprinterNameByIp = <String, String>{};

  /// Ngôn ngữ máy in đã CHẮC CHẮN (máy trả lời, model tự khai, hoặc người dùng xác
  /// nhận qua tem thử), theo MAC (ưu tiên) hoặc `ip:<ip>`.
  static final Map<String, PrinterLanguage> _knownLanguages =
      <String, PrinterLanguage>{};

  /// Lần hỏi máy gần nhất KHÔNG có kết quả, theo IP: không hỏi lại trong
  /// [_unknownLanguageTtl] (mỗi lần hỏi máy không trả lời mất ~1,4s).
  static final Map<String, DateTime> _unknownLanguageAt = <String, DateTime>{};
  static const Duration _unknownLanguageTtl = Duration(seconds: 60);

  static String? _languageKey({String? mac, String? ip}) {
    final m = normalizeMac(mac);
    if (m != null) return m;
    final i = ip?.trim();
    return (i == null || i.isEmpty) ? null : 'ip:$i';
  }

  /// Ghi nhận ngôn ngữ của máy in LAN mà app đã biết chắc (VD người dùng xác nhận qua
  /// tem thử, đọc lại từ bộ nhớ của app). [PrinterLanguage.unknown] = quên.
  ///
  /// Máy đã ghi nhận là máy hoá đơn thì [printLabel] / [printImage] tới nó báo lỗi
  /// `PRINTER_NOT_LABEL` thay vì gửi TSPL — trên mọi nền tảng.
  static void rememberPrinterLanguage({
    String? mac,
    String? ip,
    required PrinterLanguage language,
  }) {
    final keys = {
      _languageKey(mac: mac),
      _languageKey(ip: ip),
    }.whereType<String>();
    for (final key in keys) {
      if (language == PrinterLanguage.unknown) {
        _knownLanguages.remove(key);
      } else {
        _knownLanguages[key] = language;
      }
    }
  }

  /// Máy in LAN [ip] là máy tem hay máy hoá đơn — chạy bằng Dart nên dùng được cả
  /// Android lẫn iOS. Xét lần lượt, gặp kết luận chắc chắn thì dừng:
  /// 1. đã ghi nhận ([rememberPrinterLanguage] / lần dò trước);
  /// 2. thông tin dò mạng: hãng chỉ làm máy hoá đơn (theo MAC), hoặc model module mạng
  ///    tự khai là máy hoá đơn (Gprinter `DEVICENAME`, VD "GP 80 Printer") — dùng được cả
  ///    với máy KHÔNG trả lời câu hỏi trạng thái (module mạng chỉ nhận lệnh một chiều);
  /// 3. hỏi máy in qua cổng in ([askPrinter]): `<ESC>!?` rồi `DLE EOT 4`.
  ///
  /// [PrinterLanguage.unknown]: không đủ bằng chứng — nơi gọi nên hỏi người dùng (in tem
  /// thử chỉ có chữ, [PrinterLanguageProbe.sendLanTestLabel]) rồi
  /// [rememberPrinterLanguage]. Đừng tự đoán: đoán "máy tem" là in ra rác + chạy hết cuộn
  /// trên máy hoá đơn. Máy in HAI CHẾ ĐỘ (hiểu cả hai) trả [PrinterLanguage.both].
  static Future<PrinterLanguage> detectLanPrinterLanguage({
    required String ip,
    String? mac,
    int port = 9100,
    bool askPrinter = true,
  }) async {
    final known = _knownLanguageOf(mac: mac, ip: ip);
    if (known != null) return known;

    PrinterLanguage remember(PrinterLanguage language) {
      if (language != PrinterLanguage.unknown) {
        rememberPrinterLanguage(mac: mac, ip: ip, language: language);
      }
      return language;
    }

    var fromScan = _languageFromDiscovery(mac: mac, ip: ip);
    if (fromScan == PrinterLanguage.unknown &&
        _gprinterModelOf(mac, ip) == null) {
      // Chưa có tên model: dò Gprinter / Xprinter (dùng chung kết quả vài giây).
      try {
        await _sdkScanShared();
      } catch (_) {}
      fromScan = _languageFromDiscovery(mac: mac, ip: ip);
    }
    if (fromScan != PrinterLanguage.unknown) return remember(fromScan);

    if (!askPrinter) return PrinterLanguage.unknown;
    final asked = _unknownLanguageAt[ip];
    if (asked != null &&
        DateTime.now().difference(asked) < _unknownLanguageTtl) {
      return PrinterLanguage.unknown;
    }
    PrinterLanguage answer;
    try {
      answer = await PrinterLanguageProbe.probeLan(ip, port: port);
    } catch (_) {
      answer = PrinterLanguage.unknown;
    }
    if (answer == PrinterLanguage.unknown) {
      _unknownLanguageAt[ip] = DateTime.now();
      return answer;
    }
    _unknownLanguageAt.remove(ip);
    return remember(answer);
  }

  static PrinterLanguage? _knownLanguageOf({String? mac, String? ip}) {
    final byMac = _languageKey(mac: mac);
    final known = byMac == null ? null : _knownLanguages[byMac];
    if (known != null) return known;
    final byIp = _languageKey(ip: ip);
    return byIp == null ? null : _knownLanguages[byIp];
  }

  static String? _gprinterModelOf(String? mac, String? ip) {
    final m = normalizeMac(mac);
    return (m == null ? null : _gprinterNameByMac[m]) ??
        (ip == null ? null : _gprinterNameByIp[ip.trim()]);
  }

  static PrinterLanguage _languageFromDiscovery({String? mac, String? ip}) =>
      PrinterLanguageProbe.fromDiscovery(
        vendor:
            vendorFromMac(mac) ??
            (ip == null ? null : _lanDeviceCache[ip.trim()]?.vendor),
        model: _gprinterModelOf(mac, ip),
      );

  /// Chốt chặn trước khi gửi HOÁ ĐƠN (ESC/POS) tới máy in LAN [deviceId]: máy đã biết
  /// chắc là máy in TEM (hiểu lệnh tem — kể cả máy tem trả lời thêm câu hỏi trạng thái
  /// hoá đơn như PDIT; máy hoá đơn không bao giờ hiểu lệnh tem) -> lỗi
  /// `PRINTER_NOT_RECEIPT`, nơi gọi in hoá đơn dạng ảnh bằng lệnh tem. Chỉ dùng điều đã
  /// biết (không hỏi máy).
  static void _guardEscTarget(String? deviceId) {
    if (deviceId == null ||
        DeviceId.typeOf(deviceId) != PrinterConnectionType.lan) {
      return;
    }
    final ip = deviceId.substring('LAN:'.length).split(':').first.trim();
    if (ip.isEmpty) return;
    final language = _knownLanguageOf(mac: _lanDeviceCache[ip]?.mac, ip: ip);
    if (language == PrinterLanguage.label || language == PrinterLanguage.both) {
      throw PlatformException(
        code: 'PRINTER_NOT_RECEIPT',
        message: 'Máy in tem không in được hoá đơn (ESC/POS)',
        details: {'deviceId': deviceId},
      );
    }
  }

  /// Chốt chặn trước khi gửi lệnh tem TSPL tới máy in LAN [deviceId] (`LAN:<ip>[:port]`):
  /// máy đã biết là máy hoá đơn -> lỗi `PRINTER_NOT_LABEL` (nơi gọi in tem dạng ảnh
  /// ESC/POS), giống chốt chặn native trên Android nhưng chạy trên mọi nền tảng.
  ///
  /// Không dò mạng ở đây (để in nhanh): chỉ dùng điều đã biết. Riêng iOS (không có chốt
  /// chặn native) hỏi máy in, nhớ kết quả. Không rõ thì đi tiếp như trước.
  static Future<void> _guardTsplTarget(String? deviceId) async {
    if (deviceId == null ||
        DeviceId.typeOf(deviceId) != PrinterConnectionType.lan) {
      return;
    }
    final parts = deviceId.substring('LAN:'.length).split(':');
    final ip = parts.first.trim();
    if (ip.isEmpty) return;
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 9100 : 9100;
    final mac = _lanDeviceCache[ip]?.mac;
    var language =
        _knownLanguageOf(mac: mac, ip: ip) ??
        _languageFromDiscovery(mac: mac, ip: ip);
    if (language == PrinterLanguage.unknown && Platform.isIOS) {
      language = await detectLanPrinterLanguage(ip: ip, mac: mac, port: port);
    }
    if (language == PrinterLanguage.receipt) {
      throw PlatformException(
        code: 'PRINTER_NOT_LABEL',
        message: 'Máy in hoá đơn không in được lệnh tem (TSPL)',
        details: {'deviceId': deviceId},
      );
    }
  }

  static Future<List<Map<String, String>>>? _recentSdkScan;
  static DateTime _recentSdkScanAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Quét SDK (`XP0001FIND`) dùng chung trong [_netScanShare]: [scanNetPrinters],
  /// [findLanPrinterIssues] và tìm lại theo MAC chạy gần nhau chỉ broadcast một lần.
  /// Quét máy in `XP0001FIND` (Xprinter, PDIT...) bằng broadcast — nhanh (không chờ
  /// broadcast hãng Epson / Star như [scanNetPrinters]) và dùng chung kết quả trong
  /// vài giây. Trả `[{mac, ip, mask, gateway, dhcp}]` của MỌI máy trả lời, kể cả máy
  /// đang ở dải IP khác thiết bị. Dùng để biết một máy (theo MAC) đang ở IP nào ngay
  /// khi kết nối tới IP đã lưu thất bại, thay vì chờ kết nối hết hạn.
  ///
  /// [fresh]: bỏ kết quả dùng chung vài giây trước, quét mới (dùng khi vừa có thay đổi
  /// — VD in lỗi vì máy đổi IP — kết quả cũ có thể chưa có máy).
  static Future<List<Map<String, String>>> scanXpPrinters({
    bool fresh = false,
  }) {
    if (fresh) _recentSdkScan = null;
    return _sdkScanShared();
  }

  static Future<List<Map<String, String>>> _sdkScanShared() {
    final recent = _recentSdkScan;
    if (recent != null &&
        DateTime.now().difference(_recentSdkScanAt) < _netScanShare) {
      return recent;
    }
    _recentSdkScanAt = DateTime.now();
    // Máy Xprinter (XP0001FIND, native) và Gprinter (UDP `B[]G`, Dart) dò song song; máy
    // Gprinter được đánh dấu để [changeLanPrinterIp] dùng đúng giao thức.
    final future =
        Future.wait([
          _platform.scanNetPrinters().catchError(
            (_) => <Map<String, String>>[],
          ),
          GprinterUdp.search().catchError((_) => <GprinterNetInfo>[]),
        ]).then((r) {
          final xp = r[0] as List<Map<String, String>>;
          final gp = r[1] as List<GprinterNetInfo>;
          // Bỏ dòng Gprinter trùng theo MAC (cùng máy trả lời cả hai giao thức). KHÔNG bỏ theo IP:
          // hai máy in KHÁC nhau bị đặt trùng một IP thì cả hai phải có mặt — app mới nhận ra trùng
          // IP (trước đây máy Gprinter bị bỏ, coi như "mất" máy).
          final xpMacs = {for (final i in xp) ?normalizeMac(i['mac'])};
          final xpIpsNoMac = {
            for (final i in xp)
              if (i['ip'] != null && normalizeMac(i['mac']) == null) i['ip']!,
          };
          for (final g in gp) {
            final name = g.name?.trim();
            if (name == null || name.isEmpty) continue;
            _gprinterNameByIp[g.ip] = name;
            final mac = normalizeMac(g.mac);
            if (mac != null) _gprinterNameByMac[mac] = name;
          }
          return [
            ...xp,
            for (final g in gp)
              if (!xpMacs.contains(normalizeMac(g.mac)) &&
                  !xpIpsNoMac.contains(g.ip))
                {
                  'ip': g.ip,
                  'mac': g.mac,
                  'mask': g.mask,
                  'gateway': g.gateway,
                  'dhcp': '${g.dhcp}',
                  'proto': 'gprinter',
                  if (g.name != null) 'name': g.name!,
                },
          ];
        });
    _recentSdkScan = future;
    future
        .then((list) {
          for (final i in list) {
            final mac = normalizeMac(i['mac']);
            if (mac == null) continue;
            if (i['proto'] == 'gprinter') {
              _gprinterMacs.add(mac);
            } else {
              _gprinterMacs.remove(mac);
            }
          }
        })
        .catchError((_) {});
    return future;
  }

  static const Duration _netScanShare = Duration(seconds: 5);
  static Future<List<Map<String, String>>>? _recentNetScan;
  static DateTime _recentNetScanAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Máy in cấu hình mạng sai, tìm qua broadcast `XP0001FIND` (Xprinter, PDIT và máy
  /// cùng firmware; đi qua mọi dải IP miễn chung switch / mạng dây):
  /// - [LanPrinterNetIssueType.otherSubnet]: IP ngoài dải của thiết bị (VD máy mới
  ///   mua để IP tĩnh 192.168.123.100) — không in tới được, phải đổi IP
  ///   ([changeLanPrinterIp], nên dùng `dhcp: true`).
  /// - [LanPrinterNetIssueType.wrongGateway]: cùng dải nhưng IP tĩnh và gateway sai
  ///   — in được từ thiết bị cùng dải nhưng không trả lời thiết bị ở dải khác.
  ///   [LanPrinterNetIssue.suggestedGateway] là gateway router cấp cho máy in DHCP
  ///   cùng dải (nếu có); không có thì chỉ bắt được gateway trống / ngoài dải.
  ///
  /// Có thể bị chặn trên iPhone thật nếu app thiếu entitlement multicast.
  static Future<List<LanPrinterNetIssue>> findLanPrinterIssues() async {
    final localPrefixes = (await _localPrivateIpv4s())
        .map((ip) => ip.split('.').take(3).join('.'))
        .toSet();
    if (localPrefixes.isEmpty) return const [];
    String prefix(String ip) => ip.split('.').take(3).join('.');

    final printers = <String, LanPrinterNetInfo>{};
    // Chỉ cần kết quả SDK (`XP0001FIND`): máy tìm qua broadcast hãng (Epson / Star) bị bỏ
    // ở dưới nên không chờ chúng (`scanNetPrinters` chờ cả hai, ~1,5s) — hiện sớm hơn.
    final sdkScan = await _sdkScanShared();
    for (final item in sdkScan) {
      final ip = item['ip']?.trim() ?? '';
      final mac = normalizeMac(item['mac']);
      if (mac == null || _ipv4ToInt(ip) == null) continue;
      // Máy tìm qua broadcast hãng (Epson / Star) không báo gateway / DHCP và không
      // đổi IP được bằng [changeLanPrinterIp]: không xét ở đây.
      if (item['vendor'] != null) continue;
      printers.putIfAbsent(
        mac,
        () => LanPrinterNetInfo(
          mac: mac,
          ip: ip,
          mask: item['mask'] ?? '',
          gateway: item['gateway']?.trim() ?? '',
          dhcp: item['dhcp'] == 'true',
        ),
      );
    }

    // Gateway router cấp cho máy in DHCP, theo dải — làm chuẩn cho máy IP tĩnh.
    final reference = <String, String>{
      for (final p in printers.values)
        if (p.dhcp && prefix(p.gateway) == prefix(p.ip))
          prefix(p.ip): p.gateway,
    };

    final issues = <LanPrinterNetIssue>[];
    for (final p in printers.values) {
      if (!localPrefixes.contains(prefix(p.ip))) {
        issues.add(
          LanPrinterNetIssue(
            printer: p,
            type: LanPrinterNetIssueType.otherSubnet,
          ),
        );
        continue;
      }
      if (p.dhcp) continue;
      final correct = reference[prefix(p.ip)];
      final outOfSubnet =
          _ipv4ToInt(p.gateway) == null || prefix(p.gateway) != prefix(p.ip);
      if (!outOfSubnet && (correct == null || correct == p.gateway)) continue;
      issues.add(
        LanPrinterNetIssue(
          printer: p,
          type: LanPrinterNetIssueType.wrongGateway,
          suggestedGateway: correct,
        ),
      );
    }
    return issues;
  }

  // ---------------------------------------------------------------------------
  // Đổi IP cài trong máy in
  // ---------------------------------------------------------------------------

  /// Chuẩn hoá MAC về dạng `AA:BB:CC:DD:EE:FF` để so khớp giữa các nguồn (ARP Android
  /// trả chữ thường, macOS bỏ số 0 đầu như `0:1a:ef`, SDK có thể dùng `-` hoặc không
  /// có dấu phân cách). Trả `null` nếu không phải MAC hợp lệ, hoặc toàn 00 / toàn FF.
  static String? normalizeMac(String? mac) {
    if (mac == null) return null;
    final trimmed = mac.trim();
    final parts = trimmed.split(RegExp(r'[:\-]'));
    final List<String> octets;
    if (parts.length == 6) {
      octets = parts.map((p) => p.padLeft(2, '0')).toList();
    } else {
      final hex = trimmed.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      if (hex.length != 12) return null;
      octets = [for (int i = 0; i < 6; i++) hex.substring(i * 2, i * 2 + 2)];
    }
    final valid = RegExp(r'^[0-9A-Fa-f]{2}$');
    if (!octets.every(valid.hasMatch)) return null;
    final upper = octets.map((o) => o.toUpperCase()).toList();
    if (upper.every((o) => o == '00') || upper.every((o) => o == 'FF')) {
      return null;
    }
    return upper.join(':');
  }

  /// Hỏi cấu hình mạng của máy in tại [ip] bằng gói `XP0001FIND` gửi **unicast** tới
  /// `ip:9000`. Máy in (Xprinter, PDIT và các máy cùng firmware) trả lời `XP0001FOUND`
  /// kèm MAC, IP, mask, gateway và cờ DHCP. Trả `null` nếu máy in không trả lời.
  ///
  /// Gửi unicast (không broadcast) nên chạy được trên iPhone thật mà không cần
  /// entitlement `com.apple.developer.networking.multicast`. Không gửi gì vào cổng in
  /// 9100 nên không thể làm máy in in ra giấy.
  static Future<LanPrinterNetInfo?> queryXpUdpInfo(
    String ip, {
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    final dest = InternetAddress.tryParse(ip.trim());
    if (dest == null || dest.type != InternetAddressType.IPv4) return null;

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final completer = Completer<LanPrinterNetInfo?>();

      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final dg = socket?.receive();
          if (dg == null || completer.isCompleted) return;
          // Chỉ nhận trả lời từ đúng IP được hỏi.
          if (dg.address.address != dest.address) return;
          final info = _parseXpFoundPacket(dg.data);
          if (info != null) completer.complete(info);
        },
        // Lỗi gửi / nhận UDP (VD "Host is down" khi IP không tới được) báo qua stream:
        // không bắt thì thành lỗi không xử lý ở toàn app.
        onError: (Object _) {},
      );

      final packet = ascii.encode('XP0001FIND');
      socket.send(packet, dest, 9000);
      // Gửi lặp một lần phòng mất gói UDP trên Wi-Fi yếu.
      Future.delayed(const Duration(milliseconds: 250), () {
        if (completer.isCompleted) return;
        try {
          socket?.send(packet, dest, 9000);
        } catch (_) {}
      });

      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      socket?.close();
      socket = null;
    }
  }

  /// Parse gói `XP0001FOUND` (34 byte, đo từ máy PDIT thật):
  /// `[0..10]` "XP0001FOUND" · `[11..16]` MAC · `[17..18]` 0x22 0x00 · `[19..22]` IP ·
  /// `[23..26]` mask · `[27..30]` gateway · `[31..32]` port (LE) · `[33]` DHCP (1 = bật).
  static LanPrinterNetInfo? _parseXpFoundPacket(List<int> d) {
    if (d.length < 31) return null;
    if (String.fromCharCodes(d.sublist(0, 11)) != 'XP0001FOUND') return null;
    final mac = normalizeMac(
      d
          .sublist(11, 17)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':'),
    );
    if (mac == null) return null;
    String ipAt(int i) => d.sublist(i, i + 4).join('.');
    return LanPrinterNetInfo(
      mac: mac,
      ip: ipAt(19),
      mask: ipAt(23),
      gateway: ipAt(27),
      dhcp: d.length >= 34 && d[33] == 1,
    );
  }

  static int? _ipv4ToInt(String? ip) {
    if (ip == null) return null;
    final parts = ip.trim().split('.');
    if (parts.length != 4) return null;
    int value = 0;
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) return null;
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return null;
      value = (value << 8) | n;
    }
    return value;
  }

  static String _intToIpv4(int v) =>
      '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';

  /// Mask hợp lệ: dãy bit 1 liên tục từ trái, khác 0.
  static bool _isValidMask(int mask) {
    if (mask == 0) return false;
    final inverted = (~mask) & 0xFFFFFFFF;
    return (inverted & (inverted + 1)) == 0;
  }

  /// `true` nếu kết nối TCP được tới `ip:port`.
  static Future<bool> _tcpOpen(
    String ip,
    int port, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// `true` nếu có máy trả lời ở `ip:port`: kết nối được, hoặc bị từ chối / RST ngay
  /// (máy tồn tại nhưng cổng đóng). Hết giờ hoặc không tới được thì `false`.
  ///
  /// Mặc định chờ 2.5s: điện thoại ở chế độ tiết kiệm pin trả lời ARP chậm, chờ
  /// 600ms chỉ bắt được khoảng một nửa số máy chờ 5s bắt được (đo 2026-10-05).
  static Future<bool> _tcpPortAnswers(
    String ip,
    int port, {
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.destroy();
      return true;
    } on SocketException catch (e) {
      final code = e.osError?.errorCode;
      // ECONNREFUSED: 61 (iOS/macOS), 111 (Android/Linux). ECONNRESET: 54 / 104.
      return code == 61 || code == 111 || code == 54 || code == 104;
    } catch (_) {
      return false;
    }
  }

  /// Ping [ip] bằng lệnh `ping` của hệ thống — chỉ có trên Android (iOS không cho
  /// app chạy tiến trình con). Trả `false` trên nền tảng khác hoặc khi lỗi.
  static Future<bool> _systemPing(String ip) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await Process.run('ping', [
        '-c',
        '2',
        '-i',
        '0.3',
        '-W',
        '1',
        ip,
      ]).timeout(const Duration(seconds: 4));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Có thiết bị nào đang dùng [ip] không — **chỉ là dò tốt nhất có thể**.
  ///
  /// App không đọc được bảng ARP (Android 10+, iOS), mà ARP là cách duy nhất mọi thiết
  /// bị đều buộc phải trả lời. Vì vậy hàm dò gián tiếp: hỏi máy in qua UDP, gõ cửa vài
  /// cổng TCP phổ biến (máy in, web, iPhone 62078) và ping (Android). Đo trên mạng thật
  /// 96 thiết bị (2026-10-05): TCP + ping chỉ phát hiện khoảng 55–60% — điện thoại bật
  /// riêng tư / tường lửa không trả lời gì. `false` KHÔNG có nghĩa IP chắc chắn trống,
  /// và router vẫn có thể cấp IP này cho thiết bị khác về sau.
  static Future<bool> isLanIpInUse(String ip) async {
    final checks = <Future<bool>>[
      queryXpUdpInfo(ip).then((v) => v != null),
      _systemPing(ip),
      for (final port in const [9100, 80, 443, 515, 631, 8080, 62078])
        _tcpPortAnswers(ip, port),
    ];
    final results = await Future.wait(checks);
    return results.any((v) => v);
  }

  /// Máy in (đúng [mac] nếu biết) có đang trả lời ở [ip] và in được không.
  static Future<bool> _printerAnswersAt(String ip, String? mac) async {
    final xp = await queryXpUdpInfo(ip);
    // Máy trả lời `XP0001FIND` ở [ip] với ĐÚNG MAC là đủ chứng minh cấu hình mới đã áp
    // dụng. KHÔNG mở thêm cổng in 9100: máy in nhiệt chỉ nhận một kết nối — nếu app còn
    // giữ kết nối cũ tới IP này (hoặc vừa mở / đóng dồn dập) thì lần thử TCP thất bại và
    // báo "chưa xác minh" dù máy in đã đổi IP.
    if (xp != null && mac != null) return xp.mac == mac;
    if (xp == null && mac != null) {
      final found = normalizeMac(await resolveLanPrinterMac(ip));
      // Đọc được MAC mà khác → máy khác. Không đọc được MAC → chỉ dựa vào cổng in.
      if (found != null && found != mac) return false;
    }
    return _tcpOpen(ip, 9100);
  }

  /// Máy họ Xprinter ([mac]) đã trả lời broadcast `XP0001FIND` ở đúng [ip] chưa. Dùng để
  /// xác minh sau khi đổi IP: nhiều máy chỉ trả lời broadcast chứ KHÔNG trả lời gói gửi
  /// riêng (unicast) tới nó, nên hỏi unicast thì vòng nào cũng thất bại. Quét mới mỗi vòng
  /// (không dùng kết quả chung).
  static Future<bool> _xpAnswersViaBroadcast(String ip, String mac) async {
    final list = await scanXpPrinters(fresh: true);
    return list.any((i) => normalizeMac(i['mac']) == mac && i['ip'] == ip);
  }

  /// Tìm IP hiện tại của máy in theo [mac] sau khi chuyển sang DHCP.
  static Future<String?> _findPrinterIpByMac(
    String mac,
    String oldIp,
    DateTime deadline,
  ) async {
    while (DateTime.now().isBefore(deadline)) {
      // Router thường cấp lại đúng IP cũ. Chỉ nhận khi máy in đã báo DHCP bật, để
      // không nhầm với lúc máy in chưa kịp áp dụng cấu hình mới.
      final atOld = await queryXpUdpInfo(oldIp);
      if (atOld != null && atOld.mac == mac && atOld.dhcp) {
        if (await _tcpOpen(oldIp, 9100)) return oldIp;
      }

      try {
        final list = await scanNetPrinters();
        for (final item in list) {
          final ip = item['ip'];
          if (ip == null || ip.isEmpty || ip == oldIp) continue;
          if (normalizeMac(item['mac']) != mac) continue;
          if (await _printerAnswersAt(ip, mac)) return ip;
        }
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 1500));
    }

    return findLanPrinterIpByMac(mac);
  }

  /// Tìm IP hiện tại của máy in LAN theo [mac] — dùng khi máy in đã đổi IP (DHCP)
  /// và app chỉ còn IP cũ đã lưu.
  ///
  /// Thứ tự, từ nhanh tới chậm:
  /// 1. [lastIp] (nếu có): máy ở IP cũ trả đúng MAC thì dùng luôn.
  /// 2. Broadcast `XP0001FIND` / SDK (`scanNetPrinters`, ~1.5s): gói trả lời có sẵn
  ///    cả MAC lẫn IP. Có thể bị chặn trên iPhone thật nếu thiếu entitlement multicast.
  /// 3. Quét dải /24 tìm máy mở cổng 9100, hỏi MAC từng máy (unicast `XP0001FIND`,
  ///    SNMP, HTTP, NetBIOS, ARP) song song; gặp máy đúng MAC là dừng.
  ///
  /// Không mở thêm kết nối thử vào cổng in 9100 ở IP tìm được: máy in nhiệt thường chỉ
  /// nhận một kết nối, mở/đóng dồn dập ngay trước khi in làm máy in tưởng đang bận và bỏ
  /// lệnh in kế tiếp. MAC khớp đã đủ chứng minh đúng máy. Trả `null` khi không tìm thấy,
  /// hoặc khi máy in không trả lời MAC qua kênh nào — lúc đó hãy cho người dùng chọn
  /// lại máy in từ danh sách `discoverLanDevices`.
  static Future<String?> findLanPrinterIpByMac(
    String mac, {
    String? lastIp,
  }) async {
    final target = normalizeMac(mac);
    if (target == null) return null;

    // 1. IP cũ.
    final old = lastIp?.trim();
    if (old != null && _ipv4ToInt(old) != null) {
      final atOld =
          (await queryXpUdpInfo(old))?.mac ??
          normalizeMac(await resolveLanPrinterMac(old));
      // Chỉ nhận khi đọc được đúng MAC — cổng 9100 mở thôi có thể là máy in khác.
      if (atOld == target) return old;
    }

    // 2. Broadcast.
    try {
      final list = await scanNetPrinters();
      for (final item in list) {
        final ip = item['ip'];
        if (ip == null || ip.isEmpty) continue;
        if (normalizeMac(item['mac']) == target) return ip;
      }
    } catch (_) {}

    // 3. Quét /24, hỏi MAC từng máy ngay khi tìm thấy (không chờ quét xong).
    final completer = Completer<String?>();
    final pending = <Future<void>>[];
    StreamSubscription<String>? sub;
    sub = discoverLanPrinters().listen(
      (ip) {
        pending.add(() async {
          if (completer.isCompleted) return;
          final found =
              (await queryXpUdpInfo(ip))?.mac ??
              normalizeMac(await resolveLanPrinterMac(ip));
          if (found == target && !completer.isCompleted) {
            completer.complete(ip);
            await sub?.cancel();
          }
        }());
      },
      onError: (_) {},
      onDone: () async {
        await Future.wait(pending);
        if (!completer.isCompleted) completer.complete(null);
      },
      cancelOnError: false,
    );
    return completer.future;
  }

  /// Gửi một lệnh cấu hình dạng văn bản (TSPL / ZPL) vào cổng in 9100.
  static Future<bool> _sendRawNetCommand(String ip, String command) async {
    try {
      final socket = await Socket.connect(
        ip,
        9100,
        timeout: const Duration(seconds: 3),
      );
      socket.add(utf8.encode(command));
      await socket.flush();
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Đổi IP cài trong máy in LAN: đặt IP tĩnh ([newIp]) hoặc chuyển về DHCP ([dhcp]).
  ///
  /// Phía gọi không cần biết hãng máy in — plugin tự chọn cách gửi lệnh:
  /// - Máy trả lời `XP0001FIND` (Xprinter, PDIT...) hoặc đã biết MAC: gói UDP
  ///   `XP0001SAVE` theo MAC tới cổng 9000 (không đi vào cổng in, không in rác).
  /// - Máy TSC / Godex (TSPL) hoặc Zebra (ZPL) do plugin tự nhận ra: lệnh văn bản
  ///   vào cổng 9100. Chỉ gửi khi nhận ra hãng, vì máy ESC/POS sẽ in lệnh này ra giấy.
  ///
  /// Trình tự: lấy cấu hình hiện tại của máy in → kiểm tra IP mới (định dạng, cùng
  /// subnet với thiết bị, không phải IP của gateway / thiết bị) → kiểm tra trùng IP
  /// ([checkConflict]) → gửi lệnh → chờ xác minh máy in (đúng MAC) trả lời ở IP mới.
  ///
  /// [mask] / [gateway] để trống thì lấy theo cấu hình hiện tại của máy in (qua UDP),
  /// nếu không có thì dùng `255.255.255.0` và `x.y.z.1` của subnet.
  ///
  /// Lưu ý: IP tĩnh đặt từ app **router không biết**. Khi máy in tắt, router có thể
  /// cấp IP đó cho thiết bị khác và gây trùng IP. Cách an toàn nhất là đặt DHCP
  /// reservation (giữ IP theo MAC) trên router.
  static Future<LanIpChangeResult> changeLanPrinterIp({
    required String currentIp,
    String? mac,
    String? newIp,
    bool dhcp = false,
    String? mask,
    String? gateway,
    bool checkConflict = true,
    Duration verifyTimeout = const Duration(seconds: 15),

    /// Máy ĐÃ trả lời tin broadcast `XP0001FIND` (Xprinter, PDIT... — nhờ vậy mới có [mac]
    /// và [currentIp]) nên chắc chắn nhận `XP0001SAVE` theo MAC: bỏ qua bước đọc cấu hình
    /// unicast tới [currentIp] và dò hãng qua cổng in. Máy ở DẢI KHÁC thì unicast tới
    /// [currentIp] không tới được — mỗi bước đó chỉ chờ hết hạn (vài giây) rồi vẫn đi
    /// đúng đường UDP theo MAC. Cần truyền [mac] (và nên truyền [mask] / [gateway]).
    bool knownXpPrinter = false,
  }) async {
    final oldIp = currentIp.trim();
    if (_ipv4ToInt(oldIp) == null) {
      return LanIpChangeResult(
        status: LanIpChangeStatus.invalidIp,
        message: 'IP hiện tại của máy in không hợp lệ: "$currentIp"',
      );
    }

    // 1. Cấu hình hiện tại và MAC của máy in.
    final skipProbe = knownXpPrinter && normalizeMac(mac) != null;
    final info = skipProbe ? null : await queryXpUdpInfo(oldIp);
    String? printerMac = normalizeMac(mac) ?? info?.mac;
    printerMac ??= normalizeMac(await resolveLanPrinterMac(oldIp));
    final isGprinter = printerMac != null && _gprinterMacs.contains(printerMac);

    // Cách gửi lệnh: máy trả lời XP0001FIND -> UDP XP0001SAVE; TSC/Godex/Zebra do
    // plugin tự nhận ra -> lệnh văn bản qua 9100.
    final vendor =
        vendorFromMac(printerMac) ??
        (info == null && !skipProbe
            ? detectVendor(await getLanPrinterName(oldIp) ?? '')
            : null);
    final lowerVendor = (vendor ?? '').toLowerCase();
    final isTspl =
        info == null &&
        (lowerVendor.contains('tsc') || lowerVendor.contains('godex'));
    final isZpl = info == null && lowerVendor.contains('zebra');

    // Chỉ chặn sớm với hãng chắc chắn không hiểu XP0001SAVE (Epson, Star). Các máy
    // khác (VD PDIT/Xprinter) có thể không trả lời XP0001FIND nhưng vẫn nhận SAVE,
    // nên vẫn gửi rồi xác minh ở bước 5.
    final isKnownUnsupported =
        lowerVendor.contains('epson') || lowerVendor.contains('star');
    if (info == null && !isTspl && !isZpl && isKnownUnsupported) {
      return LanIpChangeResult(
        status: LanIpChangeStatus.notSupported,
        mac: printerMac,
        message:
            'Máy in ${vendor != null ? '$vendor ' : ''}($oldIp) không hỗ trợ '
            'đổi IP từ app. '
            'Hãy đổi IP trên trang cấu hình của máy in (gõ $oldIp vào trình '
            'duyệt; Epson tự chuyển sang https), hoặc đặt DHCP reservation '
            'trên router.',
      );
    }

    String? pick(String? value) =>
        (value != null && value.trim().isNotEmpty) ? value.trim() : null;

    final effMask =
        pick(mask) ??
        ((info != null && _isValidMask(_ipv4ToInt(info.mask) ?? 0))
            ? info.mask
            : '255.255.255.0');
    final maskInt = _ipv4ToInt(effMask);
    if (maskInt == null || !_isValidMask(maskInt)) {
      return LanIpChangeResult(
        status: LanIpChangeStatus.invalidIp,
        mac: printerMac,
        message: 'Subnet mask không hợp lệ: "$effMask"',
      );
    }

    // 2. Kiểm tra IP mới (chỉ khi đặt IP tĩnh).
    String? targetIp;
    String effGateway = pick(gateway) ?? '';
    if (!dhcp) {
      targetIp = newIp?.trim();
      final targetInt = _ipv4ToInt(targetIp);
      if (targetIp == null || targetInt == null) {
        return LanIpChangeResult(
          status: LanIpChangeStatus.invalidIp,
          mac: printerMac,
          message: 'IP mới không hợp lệ: "${newIp ?? ''}"',
        );
      }
      final network = targetInt & maskInt;
      final broadcast = network | ((~maskInt) & 0xFFFFFFFF);
      if (targetInt == network || targetInt == broadcast) {
        return LanIpChangeResult(
          status: LanIpChangeStatus.invalidIp,
          mac: printerMac,
          message:
              '$targetIp là địa chỉ mạng/broadcast, không đặt cho máy in được',
        );
      }

      final localIps = await _localPrivateIpv4s();
      if (localIps.contains(targetIp)) {
        return LanIpChangeResult(
          status: LanIpChangeStatus.invalidIp,
          mac: printerMac,
          message: '$targetIp đang là IP của chính thiết bị này',
        );
      }
      final sameSubnet = localIps.any((ip) {
        final v = _ipv4ToInt(ip);
        return v != null && (v & maskInt) == network;
      });
      if (localIps.isNotEmpty && !sameSubnet) {
        return LanIpChangeResult(
          status: LanIpChangeStatus.invalidIp,
          mac: printerMac,
          message:
              '$targetIp không cùng mạng với thiết bị '
              '(${localIps.join(', ')}). Đặt IP này thì thiết bị sẽ không tới được máy in.',
        );
      }

      if (effGateway.isEmpty) {
        final printerGw = _ipv4ToInt(info?.gateway);
        effGateway = (printerGw != null && (printerGw & maskInt) == network)
            ? info!.gateway
            : _intToIpv4(network | 1);
      }
      if (effGateway == targetIp) {
        return LanIpChangeResult(
          status: LanIpChangeStatus.invalidIp,
          mac: printerMac,
          message: '$targetIp là IP của router (gateway)',
        );
      }

      // 3. Kiểm tra trùng IP.
      if (checkConflict && targetIp != oldIp && await isLanIpInUse(targetIp)) {
        return LanIpChangeResult(
          status: LanIpChangeStatus.conflict,
          mac: printerMac,
          message: '$targetIp đang có thiết bị khác dùng. Hãy chọn IP khác.',
        );
      }
    } else if (effGateway.isEmpty) {
      effGateway = info?.gateway ?? '';
    }

    // 4. Gửi lệnh — plugin tự chọn cách theo những gì máy in trả lời được.
    String? method;

    if (isTspl || isZpl) {
      // Giữ nguyên cú pháp lệnh của bản trước — chưa kiểm trên máy TSC/Zebra thật.
      final command = isTspl
          ? (dhcp
                ? 'SET DHCP\r\n'
                : 'SET IP "$targetIp","$effMask","$effGateway"\r\n')
          : (dhcp
                ? '^XA^ND2,D^NRE^XZ'
                : '^XA^ND2,Z,$targetIp,$effMask,$effGateway^NRE^XZ');
      if (await _sendRawNetCommand(oldIp, command)) {
        method = isTspl ? 'tspl' : 'zpl';
      }
    } else if (isGprinter) {
      // Máy in Gprinter: lệnh UDP theo SDK của hãng (tắt DHCP → IP → gateway → netmask →
      // khởi động lại mạng), không phải XP0001SAVE.
      final sent = dhcp
          ? await GprinterUdp.setDhcp(mac: printerMac)
          : await GprinterUdp.setStatic(
              mac: printerMac,
              ip: targetIp ?? oldIp,
              mask: effMask,
              gateway: effGateway.isEmpty ? (info?.gateway ?? '') : effGateway,
            );
      if (sent) method = 'gprinter';
    } else {
      // Có MAC: XP0001SAVE qua UDP. Không có MAC: native thử SDK riêng của nền tảng.
      final sent = await _platform.setNetIp(
        mac: printerMac ?? '',
        ip: targetIp ?? oldIp,
        mask: effMask,
        gateway: effGateway,
        dhcp: dhcp,
        currentIp: oldIp,
      );
      if (sent) method = printerMac != null ? 'udp' : 'native';
    }

    if (method == null) {
      return LanIpChangeResult(
        status: printerMac == null && vendor == null
            ? LanIpChangeStatus.notSupported
            : LanIpChangeStatus.failed,
        mac: printerMac,
        message: printerMac == null && vendor == null
            ? 'Máy in không trả lời MAC và không nhận ra hãng nên không gửi được lệnh '
                  'đổi IP. Hãy đổi IP trên trang cấu hình của máy in, hoặc đặt DHCP '
                  'reservation trên router.'
            : 'Gửi lệnh đổi IP tới máy in $oldIp thất bại',
      );
    }

    // 5. Xác minh máy in đã nhận cấu hình mới.
    final deadline = DateTime.now().add(verifyTimeout);
    // Máy in cần một nhịp để áp cấu hình mạng mới; hỏi sớm hơn (1s) và dày hơn (0,7s)
    // để biết ngay khi máy trả lời — trước đây chờ cứng 2s rồi mỗi 1,5s.
    await Future.delayed(const Duration(seconds: 1));
    String? verifiedIp;
    if (!dhcp) {
      while (true) {
        if (isGprinter
            ? await _gprinterAnswersAt(targetIp!, printerMac)
            : skipProbe && printerMac != null
            ? await _xpAnswersViaBroadcast(targetIp!, printerMac)
            : await _printerAnswersAt(targetIp!, printerMac)) {
          verifiedIp = targetIp;
          break;
        }
        if (!DateTime.now().isBefore(deadline)) break;
        await Future.delayed(const Duration(milliseconds: 700));
      }
    } else if (printerMac != null) {
      verifiedIp = await _findPrinterIpByMac(printerMac, oldIp, deadline);
    }

    if (verifiedIp == null) {
      return LanIpChangeResult(
        status: LanIpChangeStatus.unverified,
        ip: targetIp,
        mac: printerMac,
        method: method,
        message: dhcp
            ? 'Đã gửi lệnh chuyển máy in sang DHCP nhưng chưa tìm thấy IP mới. '
                  'Hãy quét lại máy in sau vài giây.'
            : 'Đã gửi lệnh nhưng chưa thấy máy in trả lời ở $targetIp. '
                  'Hãy chờ máy in khởi động lại mạng rồi quét lại.',
      );
    }

    // 6. Dọn kết nối tới IP cũ.
    if (verifiedIp != oldIp) {
      try {
        await _platform.disconnectPrinter(deviceId: DeviceId.lan(oldIp));
      } catch (_) {}
    }

    return LanIpChangeResult(
      status: LanIpChangeStatus.success,
      ip: verifiedIp,
      mac: printerMac,
      method: method,
      message: dhcp
          ? 'Máy in đã chuyển sang DHCP, IP hiện tại: $verifiedIp'
          : 'Đã đổi IP máy in sang $verifiedIp. Lưu ý: router vẫn có thể cấp IP này '
                'cho thiết bị khác khi máy in tắt — nên đặt DHCP reservation (giữ IP '
                'theo MAC) trên router.',
    );
  }

  /// Máy Gprinter [mac] đang trả lời ở [ip] (dò lại bằng UDP broadcast, đúng MAC và IP).
  static Future<bool> _gprinterAnswersAt(String ip, String mac) async {
    final found = await GprinterUdp.search(
      wait: const Duration(milliseconds: 900),
    );
    return found.any((g) => g.mac == mac && g.ip == ip);
  }

  /// Đổi IP máy in (API cũ, giữ để tương thích).
  ///
  /// Có [currentIp] thì chạy [changeLanPrinterIp] (không kiểm tra trùng IP, chờ xác
  /// minh tối đa 8s) và trả `true` khi đã gửi được lệnh. Không có [currentIp] thì chỉ
  /// gửi gói UDP `XP0001SAVE` theo [mac] như trước. [vendor] không còn dùng — plugin
  /// tự nhận ra hãng. Code mới nên gọi [changeLanPrinterIp] để biết kết quả chi tiết.
  static Future<bool> setNetIp({
    required String mac,
    required String ip,
    String mask = "255.255.255.0",
    String gateway = "",
    bool dhcp = false,
    String? currentIp,
    String? vendor,
  }) async {
    if (currentIp == null || currentIp.trim().isEmpty) {
      if (mac.isEmpty) return false;
      return _platform.setNetIp(
        mac: mac,
        ip: ip,
        mask: mask,
        gateway: gateway,
        dhcp: dhcp,
      );
    }
    final result = await changeLanPrinterIp(
      currentIp: currentIp,
      mac: mac.isEmpty ? null : mac,
      newIp: ip,
      dhcp: dhcp,
      mask: mask,
      gateway: gateway.isEmpty ? null : gateway,
      checkConflict: false,
      verifyTimeout: const Duration(seconds: 8),
    );
    return result.status == LanIpChangeStatus.success ||
        result.status == LanIpChangeStatus.unverified;
  }

  /// Attempts to configure IP on printers supporting Web Config (Epson, Brother, generic web interfaces).
  ///
  /// Endpoint và tham số được đoán theo mẫu chung, không theo tài liệu hãng nào; mọi
  /// mã 2xx/3xx đều bị coi là thành công nên kết quả không đáng tin.
  @Deprecated(
    'Endpoint đoán mò, kết quả không đáng tin. Dùng changeLanPrinterIp.',
  )
  static Future<bool> configureWebPrinterIp({
    required String currentIp,
    required String newIp,
    String mask = "255.255.255.0",
    String gateway = "192.168.1.1",
    bool dhcp = false,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final endpoints = [
        '/set_ip.cgi',
        '/form.cgi',
        '/PRESENTATION/ADVANCED/NETWORKING/IP/TOP',
      ];
      for (final endpoint in endpoints) {
        try {
          final uri = Uri.parse('http://$currentIp$endpoint');
          final request = await client.postUrl(uri);
          request.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
          );
          final body = dhcp
              ? 'ip_get_method=1&dhcp=1'
              : 'ip_get_method=0&ip_address=$newIp&subnet_mask=$mask&default_gateway=$gateway';
          request.write(body);
          final response = await request.close();
          if (response.statusCode >= 200 && response.statusCode < 400) {
            client.close();
            return true;
          }
        } catch (_) {}
      }
      client.close();
    } catch (_) {}
    return false;
  }
}

/// Một lượt [PrinterLabel.discoverLanDevices] dùng chung cho mọi nơi gọi trong lúc nó chạy: người
/// vào sau nhận lại các máy đã thấy rồi theo tiếp.
class _SharedLanDiscovery {
  final List<LanDeviceModel> _seen = [];
  final StreamController<LanDeviceModel> _live =
      StreamController<LanDeviceModel>.broadcast();
  bool _done = false;

  void add(LanDeviceModel d) {
    _seen.add(d);
    _live.add(d);
  }

  void addError(Object e) => _live.addError(e);

  void close() {
    _done = true;
    unawaited(_live.close());
  }

  Stream<LanDeviceModel> join() {
    // Phát lại + nghe tiếp ĐỒNG BỘ (không có khoảng hở nào để sót máy thấy giữa hai bước).
    final out = StreamController<LanDeviceModel>();
    _seen.forEach(out.add);
    if (_done) {
      unawaited(out.close());
      return out.stream;
    }
    final StreamSubscription<LanDeviceModel> sub = _live.stream.listen(
      out.add,
      onError: out.addError,
      onDone: out.close,
    );
    out.onCancel = sub.cancel;
    return out.stream;
  }
}
