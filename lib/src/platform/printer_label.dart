import 'dart:async';
import 'dart:convert';
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
  static List<int> _buildSnmpGetRequest(String oid, {int requestId = 1, String community = 'public'}) {
    final oidBytes = _encodeSnmpOid(oid);
    final oidTlv = [0x06, ..._berLength(oidBytes.length), ...oidBytes]; // OID tag
    final nullTlv = [0x05, 0x00]; // NULL
    final vb = [...oidTlv, ...nullTlv];
    final vbSeq = [0x30, ..._berLength(vb.length), ...vb]; // SEQUENCE (VarBind)
    final vblSeq = [0x30, ..._berLength(vbSeq.length), ...vbSeq]; // SEQUENCE (VarBindList)

    final reqIdBytes = [
      0x02, 0x04,
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
      final verLen = readLength(data, i); i += lengthFieldSize(data, i) + verLen;

      // Community OCTET STRING
      if (data[i++] != 0x04) return results;
      final comLen = readLength(data, i); i += lengthFieldSize(data, i) + comLen;

      // GetResponse PDU (0xA2)
      if (data[i++] != 0xA2) return results;
      i += lengthFieldSize(data, i);

      // Skip reqId, errorStatus, errorIndex
      for (int skip = 0; skip < 3; skip++) {
        i++;
        final sLen = readLength(data, i); i += lengthFieldSize(data, i) + sLen;
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
        final oidLen = readLength(data, i); i += lengthFieldSize(data, i) + oidLen;

        // Value
        if (i >= data.length) break;
        final valTag = data[i++];
        final valLen = readLength(data, i); i += lengthFieldSize(data, i);
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
      final str = String.fromCharCodes(entry.value.where((b) => b >= 0x20 && b < 0x7F)).trim();
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
      if (bytes.every((b) => b == 0x00) || bytes.every((b) => b == 0xFF)) continue;
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
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

      sock.listen((event) {
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
      });

      // OIDs chuẩn MIB-2, Printer MIB và Enterprise MIB của HPRT / POS
      final oids = [
        '1.3.6.1.2.1.1.1.0',          // sysDescr.0
        '1.3.6.1.2.1.1.5.0',          // sysName.0
        '1.3.6.1.2.1.25.3.2.1.3.1',  // hrDeviceDescr.1
        '1.3.6.1.2.1.43.5.1.1.16.1', // prtGeneralPrinterName.1
        '1.3.6.1.4.1.39165.1.1.0',    // HPRT / Hanin private enterprise OID
      ];

      final communities = ['public', 'admin', 'HPRT'];

      int reqId = 0x200;
      for (final comm in communities) {
        for (final oid in oids) {
          final packet = _buildSnmpGetRequest(oid, requestId: reqId++, community: comm);
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

      sock.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = sock?.receive();
          if (dg == null || completer.isCompleted) return;

          final mac = _parseSnmpMacResponse(dg.data);
          if (mac != null) completer.complete(mac);
        }
      });

      // ifPhysAddress cho vài chỉ số interface phổ biến (hầu hết máy in chỉ có 1-2 card mạng)
      final oids = [
        '1.3.6.1.2.1.2.2.1.6.1',
        '1.3.6.1.2.1.2.2.1.6.2',
      ];
      final communities = ['public', 'admin'];

      int reqId = 0x300;
      for (final comm in communities) {
        for (final oid in oids) {
          final packet = _buildSnmpGetRequest(oid, requestId: reqId++, community: comm);
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
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      final completer = Completer<String?>();
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg == null || completer.isCompleted) return;

          final text = String.fromCharCodes(dg.data.where((b) => b >= 0x20 && b < 0x7F));
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
      });

      final dest = InternetAddress(ip);
      // Gói tin truy vấn cấu hình mạng HPRT / Hanin
      final hprtPackets = [
        utf8.encode("HPRT_DISCOVER\r\n"),
        utf8.encode("PRINTER_SEARCH\r\n"),
        [0x00, 0x01, 0x00, 0x00, 0x48, 0x50, 0x52, 0x54], // Binary HPRT header
      ];

      for (final p in hprtPackets) {
        socket.send(p, dest, 3000);
        socket.send(p, dest, 8888);
        socket.send(p, dest, 50000);
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
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg == null || completer.isCompleted) return;

          final text = String.fromCharCodes(dg.data.where((b) => b >= 0x20 && b < 0x7F));
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
      });

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
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg == null || completer.isCompleted) return;

          // Parse raw bytes in mDNS response for printer information
          final text = String.fromCharCodes(dg.data.where((b) => b >= 0x20 && b < 0x7F));

          // 1. Tìm TXT record `ty=...` hoặc `product=...` hoặc `mdl=...`
          final match = RegExp(r'(ty|product|mdl|model|mfg)=([^\x00\r\n;]+)', caseSensitive: false).firstMatch(text);
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
      });

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
        0x04, 0x5F, 0x74, 0x63, 0x70,                         // _tcp
        0x05, 0x6C, 0x6F, 0x63, 0x61, 0x6C,                   // local
        0x00,                                                 // Null terminator
        0x00, 0x0C,                                           // QTYPE: PTR (12)
        0x00, 0x01,                                           // QCLASS: IN (1)
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
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null && datagram.data.length > 40 && !completer.isCompleted) {
            final data = datagram.data;
            final text = String.fromCharCodes(data.where((b) => (b >= 0x20 && b < 0x7F) || b == 0x00));
            final tokens = text
                .split(RegExp(r'[\x00\s]+'))
                .map((s) => s.trim())
                .where((s) => s.length >= 3 && s.length <= 20 && !s.contains('WORKGROUP') && !s.contains('MSBROWSE'))
                .toList();

            for (final token in tokens) {
              if (isSpecificModel(token)) {
                completer.complete(token);
                return;
              }
              final vendor = detectVendor(token);
              if (vendor != null && vendor != 'POS' && vendor != 'Xprinter/POS') {
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
      });

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
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram == null || completer.isCompleted) return;
          final mac = _parseNetBiosMac(datagram.data);
          if (mac != null) completer.complete(mac);
        }
      });

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
        if (len == 0) { i += 1; break; }
        if ((len & 0xC0) == 0xC0) { i += 2; break; }
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
      if (macBytes.every((b) => b == 0x00) || macBytes.every((b) => b == 0xFF)) return null;
      return macBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
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
        socket.write("GET $path HTTP/1.1\r\nHost: $ip\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n");
        await socket.flush();

        final completer = Completer<String?>();
        final buffer = <int>[];

        socket.listen(
          (data) => buffer.addAll(data),
          onDone: () {
            if (!completer.isCompleted) {
              final text = String.fromCharCodes(buffer);

              // 1. Tìm trong <title>...</title> (ví dụ: <title>HT300 Web Server</title> hoặc <title>HPRT Printer</title>)
              final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false).firstMatch(text);
              if (titleMatch != null) {
                final titleText = titleMatch.group(1)?.trim();
                if (titleText != null && titleText.isNotEmpty && isSpecificModel(titleText)) {
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
                if (vendor != null && vendor != 'Xprinter/POS' && vendor != 'POS') {
                  completer.complete('${vendor}_$model');
                } else {
                  completer.complete(formatPrinterName(model));
                }
                return;
              }

              if (vendor != null && vendor != 'Xprinter/POS' && vendor != 'POS') {
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
        socket.write("GET $path HTTP/1.1\r\nHost: $ip\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n");
        await socket.flush();

        final completer = Completer<String?>();
        final buffer = <int>[];

        socket.listen(
          (data) => buffer.addAll(data),
          onDone: () {
            if (!completer.isCompleted) {
              final text = String.fromCharCodes(buffer);
              final macMatch =
                  RegExp(r'([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}').firstMatch(text);
              final raw = macMatch?.group(0);
              if (raw == null) {
                completer.complete(null);
              } else {
                final mac = raw.replaceAll('-', ':').toUpperCase();
                final octets = mac.split(':');
                final invalid = octets.every((o) => o == '00') || octets.every((o) => o == 'FF');
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
    return await fetchPath('/status.html');
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
      socket = await Socket.connect(ip, port,
          timeout: const Duration(milliseconds: 400));

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
        0x1D, 0x49, 2,  // GS I 2  - Type ID
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
            .map((s) => s
                .replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '')
                .replaceFirst(RegExp(r'^_+'), '')
                .trim())
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
  /// queries — trying SNMP (`ifPhysAddress`), HTTP web config, and NetBIOS (Unit ID)
  /// in parallel, then falling back to the native ARP / neighbor table (Android only).
  /// Returns the first channel to yield a real (non-broadcast, non-zero) MAC, in that
  /// priority order.
  static Future<String?> resolveLanPrinterMac(
    String ip, {
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    final results = await Future.wait([
      querySnmpMac(ip, timeout: timeout),
      queryHttpMac(ip, timeout: timeout),
      queryNetBiosMac(ip, timeout: timeout),
    ]);

    for (final mac in results) {
      if (mac != null && mac.isNotEmpty) return mac;
    }

    try {
      final nativeInfo = await _platform.getLanPrinterInfo(ip: ip);
      final mac = nativeInfo?['mac'] as String?;
      if (mac != null && mac.isNotEmpty) return mac;
    } catch (_) {}

    return null;
  }

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
    // Chạy song song tất cả các phương thức an toàn (HOÀN TOÀN KHÔNG GỬI DỮ LIỆU TỚI PORT 9100)
    final results = await Future.wait([
      querySnmpPrinterName(ip, timeout: const Duration(milliseconds: 700)),    // [0] SNMP
      queryHprtUdpPrinterName(ip, timeout: const Duration(milliseconds: 500)), // [1] HPRT UDP
      querySsdpPrinterName(ip, timeout: const Duration(milliseconds: 500)),    // [2] SSDP/UPnP
      queryMdnsPrinterName(ip, timeout: const Duration(milliseconds: 500)),    // [3] mDNS
      queryNetBiosName(ip, timeout: const Duration(milliseconds: 400)),        // [4] NetBIOS
      queryHttpPrinterName(ip, timeout: const Duration(milliseconds: 500)),    // [5] HTTP
      InternetAddress(ip)
          .reverse()
          .timeout(const Duration(milliseconds: 300))
          .then((addr) => addr.host != ip ? addr.host : null)
          .catchError((_) => null),                                             // [6] DNS
    ]);

    final snmpName    = results[0];
    final hprtUdpName = results[1];
    final ssdpName    = results[2];
    final mdnsName    = results[3];
    final netBiosName = results[4];
    final httpName    = results[5];
    final dnsName     = results[6];

    // Ưu tiên 1: SNMP — trả về đúng tên model ghi trên nhãn máy
    if (snmpName != null && snmpName.isNotEmpty) {
      final formatted = formatPrinterName(snmpName);
      if (formatted != 'Máy in LAN') return formatted;
    }

    // Ưu tiên 2: HPRT UDP discovery chuyên dụng
    if (hprtUdpName != null && hprtUdpName.isNotEmpty) {
      final formatted = formatPrinterName(hprtUdpName);
      if (formatted != 'Máy in LAN') return formatted;
    }

    // Ưu tiên 3: SSDP / UPnP
    if (ssdpName != null && ssdpName.isNotEmpty) {
      final formatted = formatPrinterName(ssdpName);
      if (formatted != 'Máy in LAN') return formatted;
    }

    // Ưu tiên 4: mDNS / Bonjour
    if (mdnsName != null && mdnsName.isNotEmpty) {
      final formatted = formatPrinterName(mdnsName);
      if (formatted != 'Máy in LAN') return formatted;
    }

    // Ưu tiên 5: Tên từ NetBIOS
    if (netBiosName != null && netBiosName.isNotEmpty) {
      final formatted = formatPrinterName(netBiosName);
      if (formatted != 'Máy in LAN') return formatted;
    }

    // Ưu tiên 6: Tên từ HTTP web config
    if (httpName != null && httpName.isNotEmpty) {
      final formatted = formatPrinterName(httpName);
      if (formatted != 'Máy in LAN') return formatted;
    }

    // Ưu tiên 7: Tên từ Reverse DNS
    if (dnsName != null && dnsName.isNotEmpty) {
      final cleanDns = dnsName.replaceFirst(
          RegExp(r'\.(local|lan|home|internal)$', caseSensitive: false), '');
      final formatted = formatPrinterName(cleanDns);
      if (formatted != 'Máy in LAN') return formatted;
    }

    // Ưu tiên 8: Native Android ARP cache & `ip neigh` table
    try {
      final nativeInfo = await _platform.getLanPrinterInfo(ip: ip, port: port);
      if (nativeInfo != null) {
        final rawName = nativeInfo['rawName'] as String?;
        final vendor = nativeInfo['vendor'] as String?;
        if (rawName != null && rawName.isNotEmpty) {
          final formatted = formatPrinterName(rawName);
          if (formatted != 'Máy in LAN') return formatted;
        }
        if (vendor != null && vendor.isNotEmpty) {
          return vendor;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Discovers LAN printers on the local network and queries their hardware/model names.
  static Stream<LanDeviceModel> discoverLanDevices({
    int port = 9100,
    Duration? timeout,
    bool queryDeviceName = true,
  }) {
    // ignore: close_sinks
    final controller = StreamController<LanDeviceModel>();
    final Set<String> emitted = <String>{};

    // Quét song song qua SDK độc quyền (Xprinter/POS UDP broadcast) — nguồn MAC
    // đáng tin cậy nhất hiện có cho các máy in đó, dùng làm fallback cho từng IP bên dưới.
    final Map<String, String> sdkMacByIp = {};
    final Future<void> sdkScanDone = scanNetPrinters().then((list) {
      for (final item in list) {
        final ip = item['ip'];
        final mac = item['mac'];
        if (ip != null && ip.isNotEmpty && mac != null && mac.isNotEmpty) {
          sdkMacByIp[ip] = mac;
        }
      }
    }).catchError((_) {});

    discoverLanPrinters(port: port, timeout: timeout).listen(
      (ip) async {
        if (!emitted.add(ip) || controller.isClosed) return;

        // 1. Phát ra ngay lập tức với IP để UI hiển thị máy in ngay trong < 100ms
        controller.add(LanDeviceModel.fromIp(ip, port: port));

        if (!queryDeviceName) return;

        // 2. Tự động truy vấn tên model, hãng và MAC ở chế độ nền
        try {
          String? modelName;
          String? mac;
          await Future.wait([
            getLanPrinterName(ip, port: port).then((v) => modelName = v),
            resolveLanPrinterMac(ip).then((v) => mac = v),
            sdkScanDone,
          ]);
          mac ??= sdkMacByIp[ip];

          final vendor = modelName != null ? detectVendor(modelName!) : null;
          final displayName = (vendor != null && vendor.isNotEmpty) ? vendor : modelName;
          if (!controller.isClosed && (displayName != null || mac != null)) {
            controller.add(LanDeviceModel.fromIp(
              ip,
              name: displayName,
              vendor: vendor,
              port: port,
              mac: mac,
            ));
          }
        } catch (_) {}
      },
      onError: (err) {
        if (!controller.isClosed) controller.addError(err);
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
    );

    return controller.stream;
  }

  /// Sends an identify signal (audio beep, paper feed, or test slip) to a LAN printer to help
  /// the user physically determine which printer on their desk matches [ipAddress].
  static Future<bool> identifyLanPrinter({
    required String ipAddress,
    int port = 9100,
    bool beep = true,
    bool feed = true,
    bool printSlip = false,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final payload = <int>[];

    if (beep) {
      // --- 1. ESC/POS & Hardware Real-Time Buzzer (Kêu 1 tiếng ngắn) ---
      payload.addAll([
        // Real-time hardware pulse pin 2 & pin 5 (DLE DC4 1 1 t) - Kích hoạt còi ngay lập tức
        0x10, 0x14, 0x01, 0x01, 0x05,
        0x10, 0x14, 0x02, 0x01, 0x05,

        // ASCII Bell (BEL)
        0x07,

        // ESC B 1 1 (Xprinter, HPRT, POS-80 buzzer: 1 beep)
        0x1B, 0x42, 0x01, 0x01,

        // ESC C 1 1 (Rongta, Gprinter buzzer: 1 beep)
        0x1B, 0x43, 0x01, 0x01,

        // ESC s 1 (Generic POS buzzer: 1 beep)
        0x1B, 0x73, 0x01,

        // Xprinter Extended Beeper: 1 beep
        0x1F, 0x1B, 0x1F, 0x53, 0x01,

        // Epson Standard Buzzer: ESC ( A và GS ( A (1 beep)
        0x1B, 0x28, 0x41, 0x02, 0x00, 0x30, 0x01,
        0x1D, 0x28, 0x41, 0x02, 0x00, 0x30, 0x01,
        0x1B, 0x28, 0x41, 0x04, 0x00, 0x30, 0x01, 0x01, 0x01,
        0x1D, 0x28, 0x41, 0x04, 0x00, 0x30, 0x01, 0x01, 0x01,

        // Citizen (ESC RS) & Star (ESC BEL)
        0x1B, 0x1E,
        0x1B, 0x07,

        // Kích xung cổng RJ11 (còi ngoài / chuông báo bếp qua cả pin 2 và pin 5)
        0x1B, 0x70, 0x00, 0x20, 0x20,
        0x1B, 0x70, 0x01, 0x20, 0x20,
        0x1B, 0x70, 0x30, 0x20, 0x20,
        0x1B, 0x70, 0x31, 0x20, 0x20,
      ]);

      // --- 2. TSPL / CPCL / ZPL Buzzer (Máy in tem: Kêu 1 tiếng ngắn) ---
      payload.addAll(utf8.encode(
        "\r\n\r\n"
        "SOUND 1,200\r\n"
        "! U1 BEEP 1\r\n"
        "~JB\r\n",
      ));
    }

    if (feed) {
      // Nhích nhẹ 1 nhịp giấy (~3mm) để vừa nghe tiếng motor vừa thấy giấy nhích
      payload.addAll(utf8.encode("\r\nFEED 24\r\n")); // TSPL: feed 24 dots
      payload.addAll([0x1B, 0x4A, 0x18]);            // ESC/POS: ESC J 24 dots
    }

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

  /// Scans the local network for printers returning their MAC and IP.
  /// This uses the proprietary UDP broadcast (Xprinter SDK) on Android
  /// and `PTDispatcher.scanDeviceAtLAN` on iOS.
  static Future<List<Map<String, String>>> scanNetPrinters() {
    return _platform.scanNetPrinters();
  }

  /// Sets the IP address of a printer on the network.
  /// - POS / Xprinter printers: uses UDP Broadcast XP0001SAVE by MAC address.
  /// - TSC / TSPL printers: sends TSPL `SET IP` / `SET DHCP` via TCP port 9100.
  /// - Zebra / ZPL printers: sends ZPL `^ND` commands via TCP port 9100.
  static Future<bool> setNetIp({
    required String mac,
    required String ip,
    String mask = "255.255.255.0",
    String gateway = "",
    bool dhcp = false,
    String? currentIp,
    String? vendor,
  }) async {
    bool directCommandOk = false;
    final lowerVendor = (vendor ?? '').toLowerCase();

    // 1. TSC / TSPL (máy in mã vạch/tem nhãn TSC, Godex, Gprinter TSPL)
    if ((lowerVendor.contains('tsc') || lowerVendor.contains('godex')) &&
        currentIp != null &&
        currentIp.isNotEmpty) {
      try {
        final socket = await Socket.connect(
          currentIp,
          9100,
          timeout: const Duration(seconds: 2),
        );
        final cmd = dhcp
            ? 'SET DHCP\r\n'
            : 'SET IP "$ip","$mask","${gateway.isNotEmpty ? gateway : '192.168.1.1'}"\r\n';
        socket.add(utf8.encode(cmd));
        await socket.flush();
        socket.destroy();
        directCommandOk = true;
      } catch (_) {}
    }

    // 2. Zebra / ZPL (máy in Zebra ZD, ZT series)
    if (lowerVendor.contains('zebra') && currentIp != null && currentIp.isNotEmpty) {
      try {
        final socket = await Socket.connect(
          currentIp,
          9100,
          timeout: const Duration(seconds: 2),
        );
        final gw = gateway.isNotEmpty ? gateway : '192.168.1.1';
        final cmd = dhcp ? '^XA^ND2,D^NRE^XZ' : '^XA^ND2,Z,$ip,$mask,$gw^NRE^XZ';
        socket.add(utf8.encode(cmd));
        await socket.flush();
        socket.destroy();
        directCommandOk = true;
      } catch (_) {}
    }

    // 3. UDP Broadcast (XP0001SAVE) qua native SDK cho Xprinter, POS, Sunmi, Rongta, HPRT
    final platformOk = await _platform.setNetIp(
      mac: mac,
      ip: ip,
      mask: mask,
      gateway: gateway,
      dhcp: dhcp,
      currentIp: currentIp,
    );

    return directCommandOk || platformOk;
  }

  /// Attempts to configure IP on printers supporting Web Config (Epson, Brother, generic web interfaces).
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
          request.headers.contentType =
              ContentType('application', 'x-www-form-urlencoded');
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
