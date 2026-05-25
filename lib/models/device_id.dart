import '../enums/printer_connection_type.dart';

class DeviceId {
  DeviceId._();

  static String lan(String ip) => 'LAN:$ip';
  static String bluetooth(String mac) => 'BT:$mac';
  static String usb(String path) => 'USB:$path';

  /// Trả về loại kết nối dựa vào prefix của deviceId.
  static PrinterConnectionType? typeOf(String deviceId) {
    if (deviceId.startsWith('LAN:')) return PrinterConnectionType.LAN;
    if (deviceId.startsWith('BT:')) return PrinterConnectionType.BT;
    if (deviceId.startsWith('USB:')) return PrinterConnectionType.USB;
    return null;
  }
}
