import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_printer_label');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('preserves dual-language evidence without claiming optional features',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'probe_capabilities');
      expect(call.arguments, {'device_id': 'LAN:192.168.1.10'});
      return {
        'deviceId': 'LAN:192.168.1.10',
        'languages': {'escpos': 'confirmed', 'tspl': 'confirmed'},
        'reason': 'status_reply',
      };
    });
    final result =
        await PrinterLabel.probeCapabilities(deviceId: 'LAN:192.168.1.10');
    expect(result.confirmsEscPos, isTrue);
    expect(result.confirmsTspl, isTrue);
    expect(result.features.values, everyElement('not_tested'));
    expect(result.toMap()['receiveBufferBytes'], isNull);
  });

  test('offline or missing replies never become supported/unsupported claims',
      () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              'deviceId': 'BT:printer',
              'reason': 'no_read_channel',
              'languages': {'escpos': 'unsupported', 'tspl': null},
            });
    final result = await PrinterLabel.probeCapabilities(deviceId: 'BT:printer');
    expect(result.hasConfirmedLanguage, isFalse);
    expect(result.escPos, 'unknown');
    expect(result.tspl, 'unknown');
    expect(result.reason, 'no_read_channel');
  });
}
