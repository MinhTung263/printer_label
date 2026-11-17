import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_label/src/desktop/usb/winspool_bindings.dart';

void main() {
  // Sai bố cục struct = đọc nhầm tên / cổng máy in trên Windows. Kiểm tra được trên
  // mọi hệ điều hành vì bố cục chỉ phụ thuộc kích thước con trỏ.
  test('PRINTER_INFO_2W đúng bố cục (13 con trỏ + 8 DWORD)', () {
    final ptr = sizeOf<IntPtr>();
    expect(sizeOf<PrinterInfo2>(), 13 * ptr + 8 * 4);
  });

  test('PRINTER_DEFAULTS đúng bố cục', () {
    final ptr = sizeOf<IntPtr>();
    expect(sizeOf<PrinterDefaults>(), ptr == 8 ? 24 : 12);
  });
}
