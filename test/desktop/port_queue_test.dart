import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

void main() {
  late Duration oldHold;
  late Duration oldCooldown;
  setUp(() {
    oldHold = PortQueue.maxHold;
    oldCooldown = PortQueue.cooldown;
    PortQueue.maxHold = const Duration(milliseconds: 200);
    PortQueue.cooldown = Duration.zero;
  });
  tearDown(() {
    PortQueue.maxHold = oldHold;
    PortQueue.cooldown = oldCooldown;
  });

  test('việc gửi tới cùng máy in chạy tuần tự', () async {
    final order = <int>[];
    await Future.wait([
      PortQueue.run('p1', () async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        order.add(1);
      }),
      PortQueue.run('p1', () async => order.add(2)),
    ]);
    expect(order, [1, 2]);
  });

  test(
    'một việc treo mãi KHÔNG chặn các việc sau (máy in khác cũng không bị ảnh hưởng)',
    () async {
      final hang = Completer<void>();
      unawaited(PortQueue.run('p2', () => hang.future).catchError((_) {}));
      final sw = Stopwatch()..start();
      // Việc sau vẫn chạy được sau tối đa maxHold, không phải chờ vô hạn.
      final ran = await PortQueue.run('p2', () async => 'ok');
      expect(ran, 'ok');
      expect(sw.elapsedMilliseconds, lessThan(1500));
      // Máy in khác chạy ngay.
      expect(await PortQueue.run('p3', () async => 'khác'), 'khác');
      hang.complete();
    },
  );

  test('việc lỗi không làm hỏng hàng đợi', () async {
    await expectLater(
      PortQueue.run('p4', () async => throw StateError('lỗi gửi')),
      throwsStateError,
    );
    expect(await PortQueue.run('p4', () async => 7), 7);
  });
}
