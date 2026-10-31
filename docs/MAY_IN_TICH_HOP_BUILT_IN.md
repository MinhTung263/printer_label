# Máy in tích hợp (Built-in Printer) — Thay đổi & Hướng dẫn sử dụng

Tài liệu này mô tả hành vi mới của máy in tích hợp (Sunmi, iMin, Urovo, Pax…) sau
khi sửa lỗi "máy in tích hợp tự động in mỗi khi gửi lệnh", và cách dùng đúng.

---

## 1. Vấn đề trước đây

Mỗi khi gửi bất kỳ lệnh in ESC/POS nào, máy in tích hợp **luôn tự động in ra**,
kể cả khi người dùng chỉ muốn in ra một máy in ngoài (Bluetooth/LAN/USB).

Nguyên nhân: hàm định tuyến `resolveConnectionsForPrint` phía native **luôn tự
thêm** máy in tích hợp vào danh sách máy in đích, bất kể lệnh in nhắm tới đâu.
Riêng máy Urovo còn đi thẳng vào SDK tích hợp, bỏ qua cả việc chọn máy.

---

## 2. Hành vi mới

**Máy in tích hợp CHỈ in khi được chỉ định tường minh** bằng `device_id == "BUILT_IN"`.

| Tình huống | Kết quả in |
|---|---|
| Chỉ kết nối máy ngoài | Chỉ in ra (các) máy ngoài |
| Chỉ có máy in tích hợp | In ra máy tích hợp (khi truyền `DeviceId.builtIn`) |
| Máy ngoài **+** máy tích hợp | In ra tất cả máy được đưa vào danh sách đích |

Muốn in ra máy tích hợp → phải truyền `deviceId: DeviceId.builtIn`.

---

## 3. Cách sử dụng (Dart / Flutter)

### 3.1. Hằng số định danh máy in tích hợp

```dart
import 'package:printer_label/printer_label.dart';

DeviceId.builtIn; // == "BUILT_IN"
```

### 3.2. In ra riêng máy in tích hợp

```dart
await ESCPrintService.instance.printWidget(
  deviceId: DeviceId.builtIn,
  widget: myReceiptWidget,
  size: TicketSize.mm80,
);
```

### 3.3. In ra riêng một máy ngoài (không kèm máy tích hợp)

```dart
await ESCPrintService.instance.printWidget(
  deviceId: DeviceId.bluetooth('AA:BB:CC:DD:EE:FF'), // hoặc DeviceId.lan(ip)
  widget: myReceiptWidget,
  size: TicketSize.mm80,
);
```
> Máy tích hợp sẽ KHÔNG in vì không được chỉ định.

### 3.4. In ra nhiều máy cùng lúc (máy ngoài + máy tích hợp) — SONG SONG

Dùng API mới `printWidgetToDevices`: ảnh được **chụp một lần** rồi gửi **song song**
tới tất cả máy (không render lại, không in tuần tự phải đợi từng máy).

```dart
final deviceIds = <String>[
  DeviceId.bluetooth('AA:BB:CC:DD:EE:FF'),
  DeviceId.lan('192.168.1.50'),
  DeviceId.builtIn, // thêm máy tích hợp vào danh sách
];

await ESCPrintService.instance.printWidgetToDevices(
  deviceIds: deviceIds,
  widget: myReceiptWidget,
  size: TicketSize.mm80,
);
```

### 3.5. In text / barcode / QR ra máy tích hợp

Các API in thô cũng dùng chung quy tắc — truyền `DeviceId.builtIn`:

```dart
await ESCPrintService.instance.printText(
  deviceId: DeviceId.builtIn,
  text: 'Hello built-in printer\n',
);
```

---

## 4. Kết nối / kiểm tra máy in tích hợp

```dart
// Có máy in tích hợp không, loại gì
final type = await PrinterLabel.getBuiltInPrinterType(); // BuiltInPrinterType
final hasBuiltIn = type != BuiltInPrinterType.none;

// Tự động kết nối máy in tích hợp
final connected = await PrinterLabel.autoConnectBuiltIn();

// Ngắt kết nối máy in tích hợp (đồng thời tắt hẳn, không tự in nữa)
await PrinterLabel.disconnectBuiltIn(); // gọi disconnectPrinter('BUILT_IN')
```

> Sau khi gọi `disconnectBuiltIn()`, máy tích hợp bị đánh dấu tắt
> (`isBuiltInPrinterDisabled = true`) và sẽ không in kể cả khi truyền
> `DeviceId.builtIn`, cho đến khi kết nối lại.

---

## 5. Tóm tắt các file đã thay đổi

### Native (Android/Kotlin)

- **`PrinterLabelPlugin.kt` — `resolveConnectionsForPrint`**
  Máy in tích hợp chỉ được thêm vào danh sách đích khi `device_id == "BUILT_IN"`;
  không còn tự động thêm vào mọi lệnh in.

- **`PrinterMethodCallHandler.kt`**
  Thêm helper `isBuiltInTarget(call)` (kiểm tra `device_id == "BUILT_IN"`).
  Các nhánh Urovo (`print_text_esc`, `print_barcode_esc`, `print_qrcode_esc`,
  `print_image_esc`) chỉ in ra máy Urovo tích hợp khi lệnh nhắm tường minh tới
  built-in; ngược lại in ra máy ngoài qua luồng thường.

### Dart (thư viện)

- **`lib/src/models/device_id.dart`**
  Thêm hằng số `DeviceId.builtIn = 'BUILT_IN'`.

- **`lib/src/service/esc/esc_print_service*.dart`**
  Thêm API `printWidgetToDevices({widget, size, deviceIds, pixelRatio})`:
  chụp ảnh một lần và in song song ra nhiều máy.

### Example

- **`example/lib/tabs/esc_tab.dart`**
  `_targetDeviceIds` luôn gồm tất cả máy ngoài **và** `DeviceId.builtIn` khi
  máy tích hợp đang bật. Nút IN HOÁ ĐƠN dùng `printWidgetToDevices` để in song song.

---

## 6. Lưu ý về chất lượng in (bản in bị mờ)

Độ nét bản in phụ thuộc `pixelRatio` khi chụp widget thành ảnh:

- `pixelRatio` thấp (≈ bằng bề rộng giấy: 384px cho K58, 576px cho K80) → chữ dễ mờ.
- Nên chụp ở độ phân giải cao hơn (khoảng gấp ~2 lần bề rộng giấy) rồi để
  `resizeThermalImage` thu nhỏ về đúng 384/576px — downscale từ ảnh lớn cho chữ
  sắc nét, đen đậm.

Có thể truyền `pixelRatio` cao hơn khi gọi in, ví dụ:

```dart
await ESCPrintService.instance.printWidgetToDevices(
  deviceIds: deviceIds,
  widget: myReceiptWidget,
  size: TicketSize.mm80,
  pixelRatio: 3.5, // tăng độ nét
);
```
