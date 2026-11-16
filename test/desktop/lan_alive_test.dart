import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  test('cổng mở → máy in còn bật', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    addTearDown(server.close);
    expect(
      await LanPrinterScanner.isPrinterAlive('127.0.0.1', port: server.port),
      isTrue,
    );
  });

  test(
    'cổng bị từ chối + không biết MAC → KHÔNG tính là bật (máy khác nhận IP cũ)',
    () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final port = server.port;
      await server.close(); // cổng đóng → bị từ chối kết nối
      // Cách cũ coi "từ chối" là đang bật (dễ báo xanh nhầm).
      expect(await LanPrinterScanner.isAlive('127.0.0.1', port: port), isTrue);
      expect(
        await LanPrinterScanner.isPrinterAlive('127.0.0.1', port: port),
        isFalse,
      );
      // Có MAC nhưng bảng ARP không khớp (không có): vẫn không bật.
      expect(
        await LanPrinterScanner.isPrinterAlive(
          '127.0.0.1',
          port: port,
          mac: 'AA:BB:CC:DD:EE:FF',
        ),
        isFalse,
      );
    },
  );
}
