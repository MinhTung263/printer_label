import 'dart:convert';
import 'dart:typed_data';

import '../enums/label_per_row_enum.dart';
import '../platform/printer_label.dart';
import 'print_relay_image.dart';

/// Loại lệnh in gửi qua trạm.
enum PrintRelayJobKind {
  /// Ảnh hoá đơn (ESC/POS).
  receipt,

  /// Các hàng tem (TSPL), mỗi ảnh là một hàng.
  label,
}

/// Trạng thái lệnh trong hàng đợi: pending → printing → done | failed.
abstract final class PrintRelayStatus {
  static const String pending = 'pending';
  static const String printing = 'printing';
  static const String done = 'done';
  static const String failed = 'failed';
}

/// Máy in đích của lệnh in qua trạm.
class PrintRelayPrinter {
  const PrintRelayPrinter({
    required this.address,
    this.isUsb = false,
    this.usbDeviceId,
    this.id,
    this.name,
    this.isBuiltIn = false,
    this.stationId,
  });

  /// Máy in tích hợp của trạm [stationId] (VD Sunmi / T1-G) — chỉ trạm đó in.
  const PrintRelayPrinter.stationBuiltIn({
    required String this.stationId,
    this.name,
  }) : address = 'builtin',
       isUsb = false,
       usbDeviceId = null,
       id = null,
       isBuiltIn = true;

  /// Máy in tích hợp sẵn trong trạm (không phải LAN / USB).
  final bool isBuiltIn;

  /// Chỉ trạm có mã này được in lệnh (`null` = trạm nào giành được trước).
  final String? stationId;

  /// Bản chỉ định trạm [id] (máy gửi nhắm thẳng một Agent).
  PrintRelayPrinter withStation(String id) => PrintRelayPrinter(
    address: address,
    isUsb: isUsb,
    usbDeviceId: usbDeviceId,
    id: this.id,
    name: name,
    isBuiltIn: isBuiltIn,
    stationId: id,
  );

  /// IP máy in LAN, hoặc địa chỉ máy in USB.
  final String address;
  final bool isUsb;

  /// Mã máy in USB dạng `USB:...` ([PrinterLabel.isUsbAttached]); trống thì dùng
  /// [address].
  final String? usbDeviceId;

  /// Mã máy in đã lưu ở app (để trạm tìm cấu hình của chính máy in đó).
  final Object? id;
  final String? name;

  String get usbId => (usbDeviceId ?? '').isNotEmpty ? usbDeviceId! : address;
}

/// Một lệnh in gửi từ máy không tới được máy in sang trạm in (máy cùng mạng /
/// đang cắm USB với máy in) để trạm in hộ.
///
/// [toMap] / [fromMap] là định dạng lưu trên hàng đợi — giữ ổn định để máy chạy
/// bản cũ và bản mới vẫn in qua nhau được.
class PrintRelayJob {
  const PrintRelayJob({
    this.id,
    required this.kind,
    required this.printer,
    required this.images,
    this.paperSize,
    this.labelSize,
    this.copies = 1,
    this.openDrawer = false,
    this.status = PrintRelayStatus.pending,
    this.createdAt,
    this.sender,
  });

  /// Lệnh in hoá đơn: [paperSize] là tên khổ giấy của app (VD `size80`).
  factory PrintRelayJob.receipt({
    required PrintRelayPrinter printer,
    required Uint8List image,
    String? paperSize,
    int quantity = 1,
    bool openDrawer = false,
    String? sender,
  }) => PrintRelayJob(
    kind: PrintRelayJobKind.receipt,
    printer: printer,
    images: [image],
    paperSize: paperSize,
    copies: quantity,
    openDrawer: openDrawer,
    sender: sender,
  );

  /// Lệnh in tem. Mặc định thu ảnh về đúng độ phân giải máy in
  /// ([PrinterLabel.shrinkLabelImage]) rồi đổi sang đen / trắng
  /// ([PrintRelayImage.compact]) để gửi qua mạng nhanh hơn.
  static Future<PrintRelayJob> label({
    required PrintRelayPrinter printer,
    required List<Uint8List> images,
    required LabelPerRow size,
    int copies = 1,
    bool shrink = true,
    String? sender,
  }) async => PrintRelayJob(
    kind: PrintRelayJobKind.label,
    printer: printer,
    images: shrink
        ? [
            for (final i in images)
              await PrintRelayImage.compact(
                await PrinterLabel.shrinkLabelImage(i, size),
              ),
          ]
        : images,
    labelSize: size,
    copies: copies,
    sender: sender,
  );

  /// Mã lệnh trên hàng đợi (có sau khi gửi / khi trạm nhận).
  final String? id;
  final PrintRelayJobKind kind;
  final PrintRelayPrinter printer;

  /// Hoá đơn: một ảnh; tem: mỗi hàng một ảnh.
  final List<Uint8List> images;

  /// Khổ giấy hoá đơn (tên do app quy ước).
  final String? paperSize;
  final LabelPerRow? labelSize;

  /// Số bản (hoá đơn) / số lần lặp (tem), tối thiểu 1.
  final int copies;
  final bool openDrawer;
  final String status;

  /// Mốc tạo lệnh (ms) — trạm bỏ lệnh quá hạn.
  final int? createdAt;

  /// Tên máy gửi lệnh (hiện ở nhật ký máy Agent); `null` với máy bản cũ.
  final String? sender;

  bool get isLabel => kind == PrintRelayJobKind.label;

  /// Bản với máy in đích [printer] khác (VD đã chỉ định trạm).
  PrintRelayJob withPrinter(PrintRelayPrinter printer) => PrintRelayJob(
    id: id,
    kind: kind,
    printer: printer,
    images: images,
    paperSize: paperSize,
    labelSize: labelSize,
    copies: copies,
    openDrawer: openDrawer,
    status: status,
    createdAt: createdAt,
    sender: sender,
  );

  int get payloadBytes => images.fold(0, (sum, i) => sum + i.length);

  Map<String, Object?> toMap() => {
    'kind': kind.name,
    'status': status,
    'createdAt': createdAt ?? DateTime.now().millisecondsSinceEpoch,
    'printerId': printer.id,
    'printerIp': printer.address.trim(),
    'printerType': printer.isBuiltIn
        ? 'builtin'
        : (printer.isUsb ? 'usb' : 'lan'),
    if (printer.stationId != null) 'targetStation': printer.stationId,
    'printerName': printer.name,
    if (sender != null) 'sender': sender,
    if (printer.isUsb) 'usbDeviceId': printer.usbId,
    if (isLabel) ...{
      'labelSize': labelSize?.name,
      'copies': copies < 1 ? 1 : copies,
      'images': images.map(base64Encode).toList(),
    } else ...{
      'size': paperSize,
      'quantity': copies < 1 ? 1 : copies,
      'openDrawer': openDrawer,
      'image': images.isEmpty ? null : base64Encode(images.first),
    },
  };

  /// Đọc lệnh từ hàng đợi; `null` khi dữ liệu không hợp lệ.
  static PrintRelayJob? fromMap(String id, Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final address = map['printerIp'];
    if (address is! String || address.isEmpty) return null;
    final isLabel = map['kind'] == PrintRelayJobKind.label.name;
    List<Uint8List> images;
    try {
      if (isLabel) {
        final list = map['images'];
        images = list is List
            ? [for (final i in list) base64Decode(i.toString())]
            : const [];
      } else {
        final image = map['image'];
        images = image is String ? [base64Decode(image)] : const [];
      }
    } catch (_) {
      images = const [];
    }
    final count = isLabel ? map['copies'] : map['quantity'];
    return PrintRelayJob(
      id: id,
      kind: isLabel ? PrintRelayJobKind.label : PrintRelayJobKind.receipt,
      printer: PrintRelayPrinter(
        address: address,
        isUsb: map['printerType'] == 'usb',
        isBuiltIn: map['printerType'] == 'builtin',
        stationId: map['targetStation']?.toString(),
        usbDeviceId: map['usbDeviceId']?.toString(),
        id: map['printerId'],
        name: map['printerName']?.toString(),
      ),
      images: images,
      paperSize: map['size']?.toString(),
      labelSize: LabelPerRow.fromName(map['labelSize']?.toString()),
      copies: count is int && count > 0 ? count : 1,
      openDrawer: map['openDrawer'] == true,
      status: map['status']?.toString() ?? '',
      createdAt: map['createdAt'] is int ? map['createdAt'] as int : null,
      sender: map['sender']?.toString(),
    );
  }
}
