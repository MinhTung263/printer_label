import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

/// Máy in LAN giả: [receipt] trả lời `DLE EOT 4` (máy hoá đơn); ngược lại trả lời `ESC ! ?`
/// bằng một byte (máy tem). Ghi lại mọi byte nhận được trên mỗi kết nối.
Future<(ServerSocket, List<List<int>>)> _printer({
  required bool receipt,
}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final got = <List<int>>[];
  server.listen((s) {
    final buf = <int>[];
    s.listen(
      (d) {
        buf.addAll(d);
        if (receipt && d.length >= 3 && d[0] == 0x10 && d[1] == 0x04) {
          s.add([0x12]);
        }
        if (!receipt &&
            d.length >= 3 &&
            d[0] == 0x1B &&
            d[1] == 0x21 &&
            d[2] == 0x3F) {
          s.add([0x00]);
        }
      },
      onDone: () {
        got.add(List.of(buf));
        s.destroy();
      },
      onError: (_) {},
    );
  });
  return (server, got);
}

Future<String> _sent(List<List<int>> got) async {
  for (var i = 0; i < 200 && got.length < 4; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  return got.map((b) => latin1.decode(Uint8List.fromList(b))).join('|');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'máy in hoá đơn: lệnh kêu KHÔNG chứa lệnh tem dạng chữ (không in ký tự lạ)',
    () async {
      final (server, got) = await _printer(receipt: true);
      addTearDown(server.close);
      await PrinterLabel.identifyLanPrinter(
        ipAddress: '127.0.0.1',
        port: server.port,
      );
      final text = await _sent(got);
      expect(text, isNot(contains('SOUND')));
      expect(text, isNot(contains('BEEP')));
      expect(text, isNot(contains('FEED')));
    },
  );

  test(
    'máy hoá đơn không rõ hãng: chỉ mã còi chung, không có mã đẩy giấy / in chữ, kết thúc bằng ESC @',
    () async {
      final (server, got) = await _printer(receipt: true);
      addTearDown(server.close);
      await PrinterLabel.identifyLanPrinter(
        ipAddress: '127.0.0.1',
        port: server.port,
        feed: false,
      );
      await _sent(got);
      // Kết nối cuối cùng là lệnh kêu (3 kết nối đầu là dò loại máy).
      final beep = got.last;
      final text = latin1.decode(Uint8List.fromList(beep));
      expect(text, contains('\x07\x1bB\x01\x01'), reason: 'BEL + ESC B n t');
      expect(
        text,
        isNot(contains('\x1bC')),
        reason: 'ESC C n = đặt chiều dài trang → đẩy giấy dài',
      );
      expect(
        text,
        isNot(contains('\x1b(A')),
        reason: 'mã riêng của Epson → in chữ trên máy khác',
      );
      expect(text, isNot(contains('\x1d(A')));
      expect(text, isNot(contains('\x1bp')), reason: 'ESC p = mở két');
      expect(beep.sublist(beep.length - 2), [
        0x1B,
        0x40,
      ], reason: 'hủy trạng thái còn lại');
    },
  );

  test('máy in tem: gửi lệnh tem, không gửi lệnh ESC/POS', () async {
    final (server, got) = await _printer(receipt: false);
    addTearDown(server.close);
    await PrinterLabel.identifyLanPrinter(
      ipAddress: '127.0.0.1',
      port: server.port,
      feed: true,
    );
    final text = await _sent(got);
    expect(text, contains('SOUND 1,200'));
    expect(text, isNot(contains('\u001bJ')));
  });
}
