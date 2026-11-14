@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

void main() {
  test('scanVendorBroadcast chạy được (in kết quả trên mạng hiện tại)', () async {
    final sw = Stopwatch()..start();
    final found = await PrinterLabel.scanVendorBroadcast();
    // ignore: avoid_print
    print('vendor broadcast: $found (${sw.elapsedMilliseconds}ms)');
    expect(found, isA<List<Map<String, String>>>());
  });
}
