@Tags(['network'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

void main() {
  test('Một Agent: máy gửi nhắm thẳng, bỏ bước giành lệnh', () async {
    final secret = 'speed-${DateTime.now().microsecondsSinceEpoch}';
    final tA = MqttPrintRelayTransport(secret: secret);
    final tS = MqttPrintRelayTransport(secret: secret);
    var printed = 0;
    final station = PrintRelayStation(
      transport: tA,
      stationId: 'A',
      canHandle: (_) async => true,
      onJob: (_) async {
        printed++;
        return true;
      },
    );
    expect(await station.start(), isTrue);
    final client = PrintRelayClient(resultTimeout: const Duration(seconds: 15));
    expect(await client.hasOnlineStation(tS), isTrue);
    await Future<void>.delayed(const Duration(seconds: 1));
    final times = <int>[];
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      final r = await client.send(
        tS,
        PrintRelayJob.receipt(
          printer: const PrintRelayPrinter(address: '192.168.1.143'),
          image: Uint8List.fromList(List.filled(2000, 1)),
        ),
      );
      times.add(sw.elapsedMilliseconds);
      expect(r, PrintRelayResult.done);
    }
    // ignore: avoid_print
    print('MQTT nhắm thẳng 1 Agent: $times ms');
    expect(printed, 3);
    await station.stop();
    await tA.dispose();
    await tS.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
