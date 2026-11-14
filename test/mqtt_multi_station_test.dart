@Tags(['network'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

void main() {
  test('Hai trạm: lệnh thường in 1 lần; lệnh máy in tích hợp đúng trạm đích',
      () async {
    final secret = 'multi-${DateTime.now().microsecondsSinceEpoch}';
    final printedBy = <String>[];

    PrintRelayStation station(String id, MqttPrintRelayTransport t) =>
        PrintRelayStation(
          transport: t,
          stationId: id,
          canHandle: (job) async => true,
          onJob: (job) async {
            printedBy.add('$id:${job.printer.isBuiltIn ? 'builtin' : 'lan'}');
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return true;
          },
        );

    final tA = MqttPrintRelayTransport(secret: secret);
    final tB = MqttPrintRelayTransport(secret: secret);
    final tSender = MqttPrintRelayTransport(secret: secret);
    final a = station('A', tA);
    final b = station('B', tB);
    expect(await a.start(), isTrue);
    expect(await b.start(), isTrue);

    final client = PrintRelayClient(resultTimeout: const Duration(seconds: 15));
    expect(await client.hasOnlineStation(tSender), isTrue);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(client.stations.map((s) => s['id']).toSet(), {'A', 'B'});

    final image = Uint8List.fromList(List.filled(500, 1));
    for (var i = 0; i < 3; i++) {
      final r = await client.send(
        tSender,
        PrintRelayJob.receipt(
          printer: const PrintRelayPrinter(address: '192.168.1.143'),
          image: image,
        ),
      );
      expect(r, PrintRelayResult.done);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    final lanPrints = printedBy.where((e) => e.endsWith(':lan')).length;
    expect(lanPrints, 3, reason: 'mỗi lệnh chỉ 1 trạm in: $printedBy');

    final r = await client.send(
      tSender,
      PrintRelayJob.receipt(
        printer: const PrintRelayPrinter.stationBuiltIn(stationId: 'B'),
        image: image,
      ),
    );
    expect(r, PrintRelayResult.done);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(printedBy.where((e) => e.endsWith(':builtin')).toList(), ['B:builtin']);
    // ignore: avoid_print
    print('printedBy: $printedBy');

    await a.stop();
    await b.stop();
    for (final t in [tA, tB, tSender]) {
      await t.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
