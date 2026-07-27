import '../enums/printer_connection_type.dart';

class DeviceId {
  DeviceId._();

  /// Sentinel đại diện cho máy in tích hợp sẵn của thiết bị (Sunmi, iMin, Urovo...).
  /// Truyền deviceId này khi in để chủ đích in ra máy in tích hợp.
  static const String builtIn = 'BUILT_IN';

  static String lan(String ip) => 'LAN:$ip';
  static String bluetooth(String mac) => 'BT:$mac';
  static String usb(String path) => 'USB:$path';

  /// Trả về loại kết nối dựa vào prefix của deviceId.
  static PrinterConnectionType? typeOf(String deviceId) {
    if (deviceId.startsWith('LAN:')) return PrinterConnectionType.lan;
    if (deviceId.startsWith('BT:')) return PrinterConnectionType.bt;
    if (deviceId.startsWith('USB:')) return PrinterConnectionType.usb;
    return null;
  }
}
