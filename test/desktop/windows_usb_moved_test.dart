import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/src/desktop/usb/windows_usb_print.dart';

String _p(String vidPid, String instance) =>
    r'\\?\usb#'
    '$vidPid#$instance#{28d78fad-5a12-11d1-ae5b-0000f803a8c2}';

void main() {
  const xp = 'vid_0483&pid_5740';
  final oldPath = _p(xp, '6&2a3b4c&0&1');

  test('máy còn ở đường dẫn cũ → không đổi', () {
    expect(WindowsUsbPrint.pickMoved(oldPath, [oldPath]), isNull);
  });

  test('cắm sang cổng khác (không serial) → tìm lại theo VID/PID', () {
    final moved = _p(xp, '6&2a3b4c&0&2');
    expect(WindowsUsbPrint.pickMoved(oldPath, [moved]), moved);
  });

  test('có số serial: đường dẫn bền, không tự đổi sang máy khác', () {
    final withSerial = _p(xp, 'ABC123');
    expect(WindowsUsbPrint.pickMoved(withSerial, [_p(xp, '6&1&0&2')]), isNull);
  });

  test('không giành máy đã cấu hình cho vị trí khác (hai máy cùng model)', () {
    final other = _p(xp, '6&2a3b4c&0&3');
    expect(WindowsUsbPrint.pickMoved(oldPath, [other], taken: {other}), isNull);
  });

  test('nhiều máy cùng model chưa rõ máy nào → không đoán', () {
    expect(
      WindowsUsbPrint.pickMoved(oldPath, [
        _p(xp, '6&2a3b4c&0&2'),
        _p(xp, '6&2a3b4c&0&4'),
      ]),
      isNull,
    );
  });

  test('khác model → không nhận', () {
    expect(
      WindowsUsbPrint.pickMoved(oldPath, [_p('vid_04b8&pid_0e15', '6&1&0&2')]),
      isNull,
    );
  });
}
