import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// `DOC_INFO_1` của winspool.
final class DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

/// `PRINTER_DEFAULTS` của winspool (mở hàng in với quyền quản trị để xả lệnh kẹt).
final class PrinterDefaults extends Struct {
  external Pointer<Utf16> pDatatype;
  external Pointer<Void> pDevMode;
  @Uint32()
  external int desiredAccess;
}

/// `PRINTER_INFO_2W` của winspool (`EnumPrintersW` cấp 2). Trường nào không dùng vẫn
/// phải khai báo đủ để đúng bố cục bộ nhớ (64-bit: 13 con trỏ rồi 8 DWORD = 136 byte).
final class PrinterInfo2 extends Struct {
  external Pointer<Utf16> pServerName;
  external Pointer<Utf16> pPrinterName;
  external Pointer<Utf16> pShareName;
  external Pointer<Utf16> pPortName;
  external Pointer<Utf16> pDriverName;
  external Pointer<Utf16> pComment;
  external Pointer<Utf16> pLocation;
  external Pointer<Void> pDevMode;
  external Pointer<Utf16> pSepFile;
  external Pointer<Utf16> pPrintProcessor;
  external Pointer<Utf16> pDatatype;
  external Pointer<Utf16> pParameters;
  external Pointer<Void> pSecurityDescriptor;
  @Uint32()
  external int attributes;
  @Uint32()
  external int priority;
  @Uint32()
  external int defaultPriority;
  @Uint32()
  external int startTime;
  @Uint32()
  external int untilTime;
  @Uint32()
  external int status;
  @Uint32()
  external int cJobs;
  @Uint32()
  external int averagePPM;
}

/// Khai báo FFI tối thiểu cho in RAW qua spooler Windows — tự khai báo thay vì
/// dùng gói `win32` để không khoá phiên bản `win32` của app dùng plugin (API
/// 5.x và 6.x khác nhau). Chỉ tạo trên Windows.
class Winspool {
  Winspool()
    : _spool = DynamicLibrary.open('winspool.drv'),
      _kernel = DynamicLibrary.open('kernel32.dll');

  final DynamicLibrary _spool;
  final DynamicLibrary _kernel;

  late final int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)
  openPrinter = _spool
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
        int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)
      >('OpenPrinterW', isLeaf: true);

  late final int Function(int, int, Pointer<DocInfo1>) startDocPrinter = _spool
      .lookupFunction<
        Uint32 Function(IntPtr, Uint32, Pointer<DocInfo1>),
        int Function(int, int, Pointer<DocInfo1>)
      >('StartDocPrinterW', isLeaf: true);

  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)
  writePrinter = _spool
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)
      >('WritePrinter', isLeaf: true);

  late final int Function(
    int,
    Pointer<Utf16>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Uint32>,
  )
  enumPrinters = _spool
      .lookupFunction<
        Int32 Function(
          Uint32,
          Pointer<Utf16>,
          Uint32,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Utf16>,
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<Uint32>,
        )
      >('EnumPrintersW');

  /// `SetPrinter(h, 0, NULL, command)` — `command` 3 = `PRINTER_CONTROL_PURGE`.
  late final int Function(int, int, Pointer<Void>, int) setPrinter = _spool
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)
      >('SetPrinter', isLeaf: true);

  late final int Function(int) startPagePrinter = _handleFn('StartPagePrinter');
  late final int Function(int) endPagePrinter = _handleFn('EndPagePrinter');
  late final int Function(int) endDocPrinter = _handleFn('EndDocPrinter');
  late final int Function(int) closePrinter = _handleFn('ClosePrinter');

  late final int Function() getLastError = _kernel
      .lookupFunction<Uint32 Function(), int Function()>(
        'GetLastError',
        isLeaf: true,
      );

  int Function(int) _handleFn(String name) =>
      _spool.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        name,
        isLeaf: true,
      );
}
