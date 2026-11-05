import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/printer_label.dart';

void main() {
  for (final size in [
    LabelPerRow.single,
    LabelPerRow.doubleLabels,
    LabelPerRow.triple
  ]) {
    testWidgets('captures ${size.name} at printer width with correct row count',
        (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        }),
      ));
      await tester.runAsync(() async {
        final images = await LabelFromWidget.captureImages<int>(
          [1, 2],
          context,
          labelPerRow: size,
          quantity: (item) => item == 1 ? 2 : 1,
          itemBuilder: (_) => SizedBox(
            width: size.stampWidth * 6.57,
            height: size.stampHeight * 6.57,
            child: const ColoredBox(color: Colors.black),
          ),
        );
        expect(images.length, (3 / size.count).ceil());
        final codec = await ui.instantiateImageCodec(images.first);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, closeTo(size.width! * 8, 1));
        frame.image.dispose();
        codec.dispose();
      });
    });
  }

  testWidgets('streams bounded batches with a final marker', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    await tester.runAsync(() async {
      final counts = <int>[];
      final flags = <bool>[];
      final result = await LabelFromWidget.captureImages<int>(
        List.generate(21, (i) => i),
        context,
        labelPerRow: LabelPerRow.single,
        quantity: (_) => 1,
        itemBuilder: (_) => const SizedBox(width: 328.5, height: 197.1),
        onBatch: (List<Uint8List> rows, isLast) async {
          counts.add(rows.length);
          flags.add(isLast);
        },
      );
      expect(result, isEmpty);
      expect(counts, [10, 10, 1]);
      expect(flags, [false, false, true]);
    });
  });
}
