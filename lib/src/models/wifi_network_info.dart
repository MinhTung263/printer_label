/// Wi-Fi thiết bị đang kết nối ([PrinterLabel.currentWifi]).
class WifiNetworkInfo {
  const WifiNetworkInfo({this.ssid, this.bssid});

  /// Tên Wi-Fi; `null` khi hệ điều hành không cho đọc (thiếu quyền vị trí, iOS
  /// thiếu entitlement "Access WiFi Information").
  final String? ssid;
  final String? bssid;

  @override
  String toString() => 'WifiNetworkInfo(ssid: $ssid, bssid: $bssid)';
}

/// Tên + mật khẩu Wi-Fi đọc từ mã QR Wi-Fi (mã dán trên router, hoặc "Chia sẻ
/// Wi-Fi" trên điện thoại): `WIFI:T:WPA;S:<tên>;P:<mật khẩu>;H:false;;`.
class WifiQrInfo {
  const WifiQrInfo({required this.ssid, this.password = '', this.security});

  final String ssid;
  final String password;

  /// `WPA`, `WEP`, `nopass`... (`null` khi mã không ghi).
  final String? security;

  /// Đọc mã QR Wi-Fi; `null` khi không phải mã Wi-Fi hợp lệ. Hỗ trợ ký tự thoát
  /// `\;` `\,` `\:` `\\` `\"` và giá trị bọc ngoặc kép.
  static WifiQrInfo? parse(String raw) {
    final text = raw.trim();
    if (!text.toUpperCase().startsWith('WIFI:')) return null;
    final fields = <String, String>{};
    final body = text.substring(5);
    final buf = StringBuffer();
    String? key;
    var escaped = false;
    for (var i = 0; i < body.length; i++) {
      final ch = body[i];
      if (escaped) {
        buf.write(ch);
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (key == null && ch == ':') {
        key = buf.toString().trim().toUpperCase();
        buf.clear();
      } else if (ch == ';') {
        if (key != null) fields[key] = buf.toString();
        key = null;
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    if (key != null) fields[key] = buf.toString();
    String unquote(String? v) {
      final s = v ?? '';
      return s.length >= 2 && s.startsWith('"') && s.endsWith('"')
          ? s.substring(1, s.length - 1)
          : s;
    }

    final ssid = unquote(fields['S']);
    if (ssid.isEmpty) return null;
    return WifiQrInfo(
      ssid: ssid,
      password: unquote(fields['P']),
      security: fields['T'],
    );
  }
}
