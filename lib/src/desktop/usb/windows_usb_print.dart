import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../paper_status.dart';
import '../port_queue.dart';
import '../printer_port.dart';
import 'ieee1284.dart';
import 'usb_printer_info.dart';

/// Máy in USB trên Windows nói chuyện THẲNG với driver `usbprint` có sẵn của hệ điều hành
/// (giao diện thiết bị `GUID_DEVINTERFACE_USBPRINT`): không cần cài driver hãng, không cần tạo
/// hàng in, không cần quyền quản trị. Mọi máy khai báo là "máy in USB" chuẩn (lớp 0x07) đều
/// hiện ở đây ngay khi cắm — kể cả máy Windows chưa có hàng in. Địa chỉ `usbp:<đường dẫn thiết bị>`.
///
/// Máy khai kiểu riêng của hãng (không phải lớp máy in) không có ở đây.
abstract final class WindowsUsbPrint {
  static const prefix = 'usbp:';

  static bool isDevice(String address) => address.startsWith(prefix);

  static String pathOf(String address) => address.substring(prefix.length);

  /// Các máy in USB đang cắm.
  static Future<List<UsbPrinterInfo>> list() async {
    final paths = await _paths(fresh: true);
    // Hỏi chuỗi định danh từng máy riêng, mỗi máy có giới hạn thời gian: máy tắt / đang bận không
    // trả lời lệnh hỏi thì IOCTL chờ mãi — không để nó treo cả danh sách.
    final ids = await Future.wait([for (final p in paths) _idOrNull(p)]);
    return [
      for (var i = 0; i < paths.length; i++)
        UsbPrinterInfo(
          address: '$prefix${paths[i]}',
          name: _nameOf(paths[i], ids[i]),
          detail: 'USB',
        ),
    ];
  }

  /// Đường dẫn thiết bị các máy in USB đang cắm (không mở thiết bị).
  static (DateTime, List<String>)? _pathsCache;

  static Future<List<String>> _paths({bool fresh = false}) async {
    // Dò rút / cắm dày: dùng lại kết quả vừa liệt kê trong 1s (mỗi lần liệt kê tạo một isolate).
    final hit = _pathsCache;
    if (!fresh &&
        hit != null &&
        DateTime.now().difference(hit.$1) < const Duration(seconds: 1)) {
      return hit.$2;
    }
    try {
      final out = await Isolate.run(_enumeratePaths).timeout(_timeout);
      _pathsCache = (DateTime.now(), out);
      return out;
    } catch (_) {
      return const [];
    }
  }

  static const _timeout = Duration(seconds: 5);

  static Future<String?> _idOrNull(String path) async {
    try {
      return await Isolate.run(
        () => _readId(path),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  /// Máy [address] còn cắm không.
  static Future<bool> present(String address) async {
    final path = pathOf(address).toLowerCase();
    return (await _paths()).any((p) => p.toLowerCase() == path);
  }

  /// Máy in vừa cắm sang CỔNG USB KHÁC: máy không có số serial thì Windows tự đặt
  /// mã thể hiện (dạng `6&2a3b4c&0&2`, chứa `&`) theo cổng cắm → đường dẫn đổi, địa chỉ
  /// đã lưu hết đúng. Tìm lại máy cùng VID/PID đang cắm ở đường dẫn mới; trả địa chỉ mới,
  /// `null` khi máy cũ còn đó, không tìm lại được hoặc không chắc đúng máy.
  ///
  /// [taken]: địa chỉ các máy in khác đã cấu hình — không giành máy của chúng (hai máy
  /// cùng model: rút một chiếc thì chiếc còn lại KHÔNG được nhận lệnh của chiếc kia).
  static Future<String?> findMoved(
    String address, {
    Set<String> taken = const {},
  }) async {
    final now = await _paths(fresh: true);
    final moved = pickMoved(
      pathOf(address),
      now,
      taken: {
        for (final t in taken)
          if (isDevice(t)) pathOf(t),
      },
    );
    return moved == null ? null : '$prefix$moved';
  }

  /// Chọn đường dẫn mới của máy [oldPath] trong [present] (thuần — kiểm thử được).
  static String? pickMoved(
    String oldPath,
    List<String> present, {
    Set<String> taken = const {},
  }) {
    final lower = {for (final p in present) p.toLowerCase()};
    if (lower.contains(oldPath.toLowerCase())) return null;
    final old = _parse(oldPath);
    // Có số serial: đường dẫn đã bền theo máy, không phụ thuộc cổng.
    if (old == null || !old.portBound) return null;
    final takenLower = {for (final t in taken) t.toLowerCase()};
    final candidates = [
      for (final p in present)
        if (_parse(p)?.vidPid == old.vidPid &&
            !takenLower.contains(p.toLowerCase()))
          p,
    ];
    return candidates.length == 1 ? candidates.single : null;
  }

  static ({String vidPid, bool portBound})? _parse(String path) {
    final m = RegExp(
      r'usb#(vid_[0-9a-f]{4}&pid_[0-9a-f]{4})#([^#]*)#',
      caseSensitive: false,
    ).firstMatch(path);
    if (m == null) return null;
    return (
      vidPid: m.group(1)!.toLowerCase(),
      portBound: m.group(2)!.contains('&'),
    );
  }

  /// Chuỗi IEEE 1284 của máy [address] (hỏi máy qua `IOCTL_USBPRINT_GET_1284_ID`); `null` khi
  /// không đọc được.
  static Future<String?> deviceId(String address) => _idOrNull(pathOf(address));

  /// VD `\\?\usb#vid_0483&pid_5740#serial#{guid}` → `USB 0483:5740`.
  static String shortName(String address) {
    final m = RegExp(
      r'vid_([0-9a-f]{4})&pid_([0-9a-f]{4})',
      caseSensitive: false,
    ).firstMatch(pathOf(address));
    return m == null
        ? 'Máy in USB'
        : 'USB ${m.group(1)!.toUpperCase()}:${m.group(2)!.toUpperCase()}';
  }

  static String _nameOf(String path, String? id) {
    final n = id == null ? '' : Ieee1284.name(id);
    return n.isNotEmpty ? n : shortName('$prefix$path');
  }
}

/// Ghi dữ liệu thô tới máy in USB qua `usbprint` — chạy trong isolate riêng (WriteFile chờ máy in
/// nhận hết dữ liệu).
class WindowsUsbPrintPort implements PrinterPort {
  WindowsUsbPrintPort(this.address);

  final String address;

  @override
  String get id => address;

  @override
  Future<void> send(Uint8List data, {bool checkStatus = true}) =>
      PortQueue.run(id, () async {
        final path = WindowsUsbPrint.pathOf(address);
        final error = await Isolate.run(() => _write(path, data));
        if (error == null) return;
        if (error.startsWith('open 2') || error.startsWith('open 3')) {
          throw UsbPrinterNotFound(address); // rút cáp / đổi cổng
        }
        throw Exception('Không gửi được tới máy in USB: $error');
      });

  /// `usbprint` không trả trạng thái giấy qua đường này — không hỏi.
  @override
  Future<PaperStatus> queryStatus() async => PaperStatus.unknown;
}

// ---- Gọi Windows (SetupAPI + kernel32) -------------------------------------------------

/// `{28D78FAD-5A12-11D1-AE5B-0000F803A8C2}` — giao diện thiết bị `usbprint`.
Pointer<Uint8> _usbPrintGuid() {
  final g = calloc<Uint8>(16);
  final d = g.asTypedList(16);
  final bd = ByteData.sublistView(d);
  bd.setUint32(0, 0x28D78FAD, Endian.little);
  bd.setUint16(4, 0x5A12, Endian.little);
  bd.setUint16(6, 0x11D1, Endian.little);
  d.setAll(8, const [0xAE, 0x5B, 0x00, 0x00, 0xF8, 0x03, 0xA8, 0xC2]);
  return g;
}

final class _Api {
  _Api()
    : _setup = DynamicLibrary.open('setupapi.dll'),
      _kernel = DynamicLibrary.open('kernel32.dll');

  final DynamicLibrary _setup;
  final DynamicLibrary _kernel;

  late final int Function(Pointer<Uint8>, Pointer<Utf16>, int, int)
  getClassDevs = _setup
      .lookupFunction<
        IntPtr Function(Pointer<Uint8>, Pointer<Utf16>, IntPtr, Uint32),
        int Function(Pointer<Uint8>, Pointer<Utf16>, int, int)
      >('SetupDiGetClassDevsW');

  late final int Function(
    int,
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
  )
  enumInterfaces = _setup
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Void>,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint8>,
        ),
        int Function(int, Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>)
      >('SetupDiEnumDeviceInterfaces');

  late final int Function(
    int,
    Pointer<Uint8>,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Void>,
  )
  getDetail = _setup
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(
          int,
          Pointer<Uint8>,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<Void>,
        )
      >('SetupDiGetDeviceInterfaceDetailW');

  late final int Function(int) destroyInfoList = _setup
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetupDiDestroyDeviceInfoList',
      );

  late final int Function(
    Pointer<Utf16>,
    int,
    int,
    Pointer<Void>,
    int,
    int,
    int,
  )
  createFile = _kernel
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW');

  late final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Void>,
  )
  writeFile = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('WriteFile');

  late final int Function(
    int,
    int,
    Pointer<Void>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Void>,
  )
  deviceIoControl = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Uint32,
          Pointer<Void>,
          Uint32,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(
          int,
          int,
          Pointer<Void>,
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<Void>,
        )
      >('DeviceIoControl');

  late final int Function(int) closeHandle = _kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  late final int Function() getLastError = _kernel
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
}

const int _digcfPresent = 0x2;
const int _digcfDeviceInterface = 0x10;
const int _genericRead = 0x80000000;
const int _genericWrite = 0x40000000;
const int _shareReadWrite = 0x3;
const int _openExisting = 3;
const int _invalidHandle = -1;

/// `IOCTL_USBPRINT_GET_1284_ID` = CTL_CODE(FILE_DEVICE_UNKNOWN, 13, METHOD_BUFFERED, FILE_ANY_ACCESS).
const int _ioctlGet1284Id = 0x00220034;

/// Đường dẫn thiết bị các máy in USB đang cắm (chỉ liệt kê, KHÔNG mở thiết bị).
List<String> _enumeratePaths() {
  final api = _Api();
  final guid = _usbPrintGuid();
  final is64 = sizeOf<IntPtr>() == 8;
  final result = <String>[];
  final set = api.getClassDevs(
    guid,
    nullptr,
    0,
    _digcfPresent | _digcfDeviceInterface,
  );
  if (set == _invalidHandle || set == 0) {
    calloc.free(guid);
    return result;
  }
  // SP_DEVICE_INTERFACE_DATA: cbSize(4) + GUID(16) + Flags(4) + Reserved(ULONG_PTR).
  final ifSize = is64 ? 32 : 28;
  final ifData = calloc<Uint8>(ifSize);
  try {
    for (var i = 0; i < 64; i++) {
      ByteData.sublistView(
        ifData.asTypedList(ifSize),
      ).setUint32(0, ifSize, Endian.little);
      if (api.enumInterfaces(set, nullptr, guid, i, ifData) == 0) break;
      final need = calloc<Uint32>();
      api.getDetail(
        set,
        ifData,
        Pointer<Uint8>.fromAddress(0),
        0,
        need,
        nullptr,
      );
      final size = need.value;
      calloc.free(need);
      if (size < 8 || size > 4096) continue;
      // SP_DEVICE_INTERFACE_DETAIL_DATA_W: cbSize(4) + WCHAR DevicePath[].
      final detail = calloc<Uint8>(size);
      try {
        ByteData.sublistView(
          detail.asTypedList(size),
        ).setUint32(0, is64 ? 8 : 6, Endian.little);
        if (api.getDetail(set, ifData, detail, size, nullptr.cast(), nullptr) ==
            0) {
          continue;
        }
        final path = Pointer<Utf16>.fromAddress(
          detail.address + 4,
        ).toDartString();
        if (path.isEmpty) continue;
        result.add(path);
      } finally {
        calloc.free(detail);
      }
    }
  } finally {
    calloc.free(ifData);
    calloc.free(guid);
    api.destroyInfoList(set);
  }
  return result;
}

String? _readId(String path) => _readIdWith(_Api(), path);

/// Mở thiết bị chỉ để hỏi chuỗi IEEE 1284 (không giữ).
String? _readIdWith(_Api api, String path) {
  final name = path.toNativeUtf16();
  try {
    final h = api.createFile(
      name,
      _genericRead | _genericWrite,
      _shareReadWrite,
      nullptr,
      _openExisting,
      0,
      0,
    );
    if (h == _invalidHandle || h == 0) return null;
    final buf = calloc<Uint8>(1024);
    final got = calloc<Uint32>();
    try {
      final ok = api.deviceIoControl(
        h,
        _ioctlGet1284Id,
        nullptr,
        0,
        buf,
        1024,
        got,
        nullptr,
      );
      if (ok == 0 || got.value < 3) return null;
      // 2 byte đầu: độ dài (big-endian, gồm cả 2 byte này), rồi chuỗi ASCII.
      final bytes = buf.asTypedList(got.value);
      final len = (bytes[0] << 8) | bytes[1];
      final end = len.clamp(2, got.value);
      final id = String.fromCharCodes(bytes.sublist(2, end));
      return id.trim().isEmpty ? null : id;
    } finally {
      calloc.free(buf);
      calloc.free(got);
      api.closeHandle(h);
    }
  } finally {
    calloc.free(name);
  }
}

/// Ghi [data] tới thiết bị [path]; `null` = xong, ngược lại là bước lỗi + mã lỗi Windows.
String? _write(String path, Uint8List data) {
  final api = _Api();
  final name = path.toNativeUtf16();
  final buf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
  final written = calloc<Uint32>();
  try {
    buf.asTypedList(data.length).setAll(0, data);
    final h = api.createFile(
      name,
      _genericWrite,
      _shareReadWrite,
      nullptr,
      _openExisting,
      0,
      0,
    );
    if (h == _invalidHandle || h == 0) return 'open ${api.getLastError()}';
    try {
      var offset = 0;
      while (offset < data.length) {
        final chunk = data.length - offset;
        final ok = api.writeFile(
          h,
          Pointer<Uint8>.fromAddress(buf.address + offset),
          chunk,
          written,
          nullptr,
        );
        if (ok == 0) return 'write ${api.getLastError()}';
        if (written.value == 0) return 'write 0 byte';
        offset += written.value;
      }
    } finally {
      api.closeHandle(h);
    }
    return null;
  } finally {
    calloc
      ..free(name)
      ..free(buf)
      ..free(written);
  }
}
