import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/desktop.dart';

bool _hasCut(Uint8List b) {
  for (var i = 0; i + 3 < b.length; i++) {
    if (b[i] == 0x1D &&
        b[i + 1] == 0x56 &&
        b[i + 2] == 0x42 &&
        b[i + 3] == 0x01) {
      return true;
    }
  }
  return false;
}

void main() {
  final raster = Uint8List.fromList([0x1D, 0x76, 0x30, 0, 1, 0, 1, 0, 0xFF]);

  test(
    'phiếu: mặc định có lệnh cắt; tắt tự cắt thì không gửi lệnh cắt nhưng vẫn đẩy giấy',
    () {
      final withCut = EscPosCommands.receipt(raster);
      final noCut = EscPosCommands.receipt(raster, cut: false);
      expect(_hasCut(withCut), isTrue);
      expect(_hasCut(noCut), isFalse);
      // Vẫn đẩy 5 dòng để phần in qua lưỡi xé.
      expect(noCut.length, withCut.length - EscPosCommands.cut.length);
      expect(noCut.sublist(noCut.length - 5), EscPosCommands.feed5);
    },
  );

  test('nhiều bản: mỗi bản có / không có lệnh cắt theo cờ', () {
    final three = EscPosCommands.receipt(raster, copies: 3);
    var n = 0;
    for (var i = 0; i + 3 < three.length; i++) {
      if (three[i] == 0x1D && three[i + 1] == 0x56) n++;
    }
    expect(n, 3);
    expect(
      _hasCut(EscPosCommands.receipt(raster, copies: 3, cut: false)),
      isFalse,
    );
  });

  test('phiếu in thử chữ cũng theo cờ cắt', () {
    expect(_hasCut(EscPosCommands.textTicket(['a'])), isTrue);
    expect(_hasCut(EscPosCommands.textTicket(['a'], cut: false)), isFalse);
  });
}
