# Phân tích chi tiết plugin `printer_label`

## 1. Kiến trúc tổng thể

```
App Flutter
   │
   ├─ Facade tĩnh PrinterLabel (lib/src/platform/printer_label.dart)
   │     └─ PrinterLabelPlatform (abstract, plugin_platform_interface)
   │           └─ MethodChannelPrinterLabel
   │                 ├─ MethodChannel  "flutter_printer_label"        (mọi lệnh connect/print/status)
   │                 ├─ EventChannel   "flutter_printer_label/bt_scan"   (stream kết quả scan Bluetooth)
   │                 └─ EventChannel   "flutter_printer_label/usb_events"(stream cắm/rút USB)
   │
   ├─ 3 service tầng cao, mỗi service có cặp interface/impl riêng (pattern PlatformInterface + token),
   │  nhưng impl thực chất gọi ngược lại xuống facade `PrinterLabel` chứ không tự đi MethodChannel:
   │     ESCPrintService     — in hóa đơn nhiệt ESC/POS (ảnh, text, barcode, QR)
   │     LabelPrintService   — in tem nhãn từ danh sách Widget, giao thức TSPL
   │     CupStickerPrinter   — in tem ly/cốc (widget hoặc ảnh raw), giao thức TSPL
   │
   ▼ MethodChannel "flutter_printer_label"
┌────────────────────────────┬───────────────────────────────────────────────────┐
│ Android (Kotlin)           │ iOS (Swift)                                        │
├────────────────────────────┼───────────────────────────────────────────────────┤
│ PrinterLabelPlugin         │ PrinterLabelPlugin                                 │
│   └─ PrinterMethodCallHandler (dispatch theo call.method)                       │
│        ├─ BluetoothPrinterManager  (scan/connect/permission Classic BT)         │
│        ├─ BuiltInPrinterManager    (nhận diện máy in tích hợp POS)              │
│        └─ PrinterThermal           (build lệnh ESC/POS thủ công)                │
│        + TSPL build trực tiếp trong PrinterLabelPlugin (SDK net.posprinter)     │
│                             │   └─ BLEManager        (singleton, CoreBluetooth thuần) │
│                             │   └─ LANPrinterManager (Network framework, TCP)   │
│                             │   └─ ESCPosPrinter     (build lệnh ESC bằng PrinterSDK.xcframework)│
└────────────────────────────┴───────────────────────────────────────────────────┘
```

Điểm mấu chốt: cả hai nền tảng đều **tự viết tay lớp transport** (Bluetooth/LAN) thay vì dùng transport có sẵn trong SDK in ấn của bên thứ ba. SDK bên thứ ba (`net.posprinter` trên Android, `PrinterSDK.xcframework` trên iOS) chỉ đóng vai trò "command builder" — sinh ra chuỗi byte lệnh máy in theo ngôn ngữ TSPL/ESC, còn việc gửi bytes đó qua Bluetooth/LAN là code tự viết để kiểm soát tốt hơn tốc độ, buffer, retry.

Trên Dart, `PrinterLabel` (facade) còn có logic **platform-guard** để 1 API dùng chung nhưng hành vi khác nhau theo OS — ví dụ `startBluetoothScan()`/`stopBluetoothScan()` chỉ có tác dụng thật trên iOS (Android dùng cơ chế khác), còn `autoConnectBuiltIn()`, `hasBuiltInPrinter()`, `getBuiltInPrinterPaperSize()` chỉ có tác dụng thật trên Android (iOS không có khái niệm máy in tích hợp sẵn phần cứng).

---

## 2. Ưu tiên thiết bị in như thế nào

Plugin **không có logic "chọn thiết bị ưu tiên" ở tầng native** — native chỉ nhận đúng `deviceId`/`connectionType` được truyền vào và gửi tới đúng thiết bị đó (hoặc tất cả nếu không truyền gì). Việc "ưu tiên" hoàn toàn do **tầng gọi (Dart/app)** quyết định trước khi gọi API in.

### 2.1. Ở tầng native khi không truyền `deviceId` (fallback ngầm)

**iOS** — `sendToPrinter()` (`PrinterLabelPlugin.swift`) định tuyến theo thứ tự:
1. Nếu có `connectionType == "Bluetooth"` → dùng BLE.
2. Nếu `deviceId` là UUID hợp lệ (có/không tiền tố `BT:`) → BLE theo đúng UUID đó.
3. Nếu `deviceId` có tiền tố `LAN:` → LAN theo đúng IP đó.
4. Nếu **hoàn toàn không có `deviceId`**: ưu tiên gửi tới **thiết bị Bluetooth đầu tiên đang kết nối** (`connectedPeripherals.first` — thứ tự Dictionary không đảm bảo); nếu không có BLE nào kết nối thì gửi tới **tất cả** LAN printer đang kết nối.

**Android** — `resolveConnectionsForPrint()` trong `PrinterLabelPlugin.kt` tương tự: nếu có `device_id` cụ thể thì lấy đúng connection đó (tự động thử auto-connect built-in nếu chưa có); nếu không có `device_id`, sẽ tự dò và ưu tiên **máy in tích hợp sẵn (built-in)** trước (qua `autoConnectBuiltInSync`), rồi mới fallback các connection đang có sẵn trong map `connections`.

### 2.2. Ở tầng Dart/example app (nơi thực sự quyết định thứ tự ưu tiên)

Đây là nơi thể hiện rõ nhất chiến lược ưu tiên, ví dụ `esc_tab.dart:23-31`:

```dart
List<String?> get _targetDeviceIds {
  if (widget.connectedDevices.isNotEmpty) {
    return widget.connectedDevices.map((d) => d.id).toList();
  }
  if (_hasBuiltInPrinter) {
    return [null]; // null đại diện cho máy in tích hợp sẵn
  }
  return [DeviceId.lan(widget.ipAddress)];
}
```

Thứ tự ưu tiên do app tự thiết kế:
1. **Thiết bị người dùng đã chủ động kết nối** (Bluetooth/LAN/USB đang có trong danh sách `connectedDevices`) — ưu tiên cao nhất, in trên **tất cả** thiết bị đã kết nối (vòng lặp `for (final deviceId in _targetDeviceIds)`).
2. Nếu chưa kết nối thiết bị nào, nhưng máy đang chạy là **máy in tích hợp sẵn (built-in POS)** → dùng `deviceId = null` để native tự động dò và kết nối built-in printer.
3. Cuối cùng mới fallback về địa chỉ IP LAN đã nhập sẵn trong UI (`DeviceId.lan(ipAddress)`).

`DeviceId` (`lib/src/models/device_id.dart`) là cơ chế hỗ trợ việc này: mã hoá loại kết nối ngay trong chuỗi ID bằng tiền tố (`LAN:ip`, `BT:mac`, `USB:path`), giúp 1 danh sách `deviceId` string tự mô tả loại kết nối mà không cần truyền thêm `connectionType` riêng — thuận tiện cho việc in đồng loạt trên nhiều loại kết nối khác nhau (`print_all` bên Android lọc theo `connection_type` dựa vào việc này).

**Tóm lại**: "ưu tiên thiết bị" là quy ước ở tầng ứng dụng (đã kết nối thủ công > built-in tự động > LAN mặc định), không phải một thuật toán cứng trong plugin. Chỉ riêng trường hợp gọi API mà **không truyền `deviceId` nào cả**, native mới có fallback ngầm định (ưu tiên built-in trên Android, ưu tiên BLE đang kết nối trên iOS).

---

## 3. Cơ chế tự phát hiện máy in tích hợp qua `getBuiltInPrinterPaperSize`

Đây là tính năng **chỉ có trên Android** (iOS không có máy in tích hợp phần cứng nên hàm này trả `0` vô điều kiện ở phía Dart). Toàn bộ logic nằm trong `android/.../BuiltInPrinterManager.kt` — thực chất là 4 hàm top-level (không phải class), không dùng SDK AIDL riêng của từng hãng mà suy luận qua các tín hiệu hệ thống.

### Bước 1 — Nhận diện thiết bị có phải máy POS tích hợp máy in (`isBuiltInPrinter()`)

```kotlin
val manufacturer = Build.MANUFACTURER.lowercase()
val model = Build.MODEL.lowercase()
return manufacturer.contains("sunmi") || manufacturer.contains("imin") ||
       manufacturer.contains("pax")   || manufacturer.contains("urovo") ||
       model.contains("sunmi") || model.contains("imin") ||
       model.contains("pax")   || model.contains("urovo")
```

Chỉ đơn giản so khớp chuỗi hãng/model thiết bị (`Build.MANUFACTURER`, `Build.MODEL`) với 4 thương hiệu POS phổ biến có máy in tích hợp: **Sunmi, iMin, Pax, Urovo**. Đây là bước kiểm tra nhanh, không cần quyền hay Package Visibility.

### Bước 2 — Xác thực thêm qua Package Manager (`hasBuiltInPrinter()`, dùng cho hàm khác nhưng cùng cơ chế)

Nếu bước 1 không khớp (ví dụ do lỗi nhận diện tên), thử `pm.getPackageInfo(pkg, 0)` với danh sách package service in ấn đã biết của các hãng (`com.sunmi.printerservice`, `woyou.aidl.service`, `net.imin.printer`, `com.pax.sz.printerservice`, `com.landicorp.android.pinpadservice`, `com.urovo.printerservice`, `android.printservice.urovoprint`). Cách này bù cho hạn chế **Package Visibility từ Android 11+** (cần khai báo `<queries>` trong `AndroidManifest.xml`, plugin đã khai báo sẵn).

### Bước 3 — `getBuiltInPrinterPaperSize()`: dò khổ giấy thật (58mm hay 80mm)

```
if (!isBuiltInPrinter()) return 0        // Không phải máy POS tích hợp → trả 0 (không có máy in)

1) Đọc System Property của Sunmi (qua reflection android.os.SystemProperties.get):
   - "ro.sunmi.printer.paper" == "0"  → 80mm
   - "ro.sunmi.printer.paper" == "1"  → 58mm
   - "ro.sunmi.hardware.printer" chứa "80" → 80mm
   - "ro.sunmi.hardware.printer" chứa "58" → 58mm

2) Nếu System Property không có giá trị hữu ích, đoán theo nhóm Model:
   - Model chứa "t1"/"t2"/"s2"/"d2"/"d3"/"d4"/"swan"/"mix" (dòng máy tính tiền để bàn, thường có
     đầu in khổ lớn) → 80mm
   - Còn lại (V2, V2s, V3, M2, A920, Urovo... — máy cầm tay) → mặc định 58mm
```

`getSystemProperty()` dùng **reflection** để gọi `android.os.SystemProperties.get(key)` — đây là API hệ thống ẩn (`@hide`) của Android, không có trong SDK công khai nên phải truy cập qua `Class.forName` + `getMethod`, và luôn có `try/catch` trả `""` nếu thất bại (ví dụ trên ROM chặn truy cập class ẩn).

### Sử dụng ở tầng Dart/UI (`esc_tab.dart:39-52`)

```dart
final paperSize = await PrinterLabel.getBuiltInPrinterPaperSize();
final hasPrinter = paperSize > 0;
if (hasPrinter) {
  _selectedSize = paperSize == 80 ? TicketSize.mm80 : TicketSize.mm58;
}
```

App gọi hàm này ngay khi khởi tạo tab để tự động: (1) biết máy hiện tại có phải POS tích hợp sẵn máy in hay không, và (2) tự chọn khổ giấy mặc định khớp phần cứng thật, không cần người dùng chọn tay.

**Nhận xét**: cơ chế này hoàn toàn dựa trên suy luận gián tiếp (tên hãng/model + system property + đoán theo dòng máy) chứ **không gọi trực tiếp API/AIDL chính thức của từng hãng** để hỏi khổ giấy thật. Ưu điểm là đơn giản, không cần tích hợp SDK riêng của từng hãng POS; nhược điểm là có thể sai nếu gặp model mới chưa nằm trong danh sách đoán, hoặc hãng đổi format system property.

---

## 4. Cơ chế căn chỉnh tem in đúng chính giữa (căn giữa)

Có **2 cơ chế căn giữa độc lập**, dùng cho 2 loại in khác nhau: (A) in nhiều tem/label từ widget theo hàng (`LabelFromWidget`), và (B) resize ảnh về đúng kích thước vật lý tem/giấy in (`image_resize.dart`).

### 4.A. Căn giữa khi ghép nhiều tem trên 1 hàng (`label_from_widget.dart`)

Khi in label theo `LabelPerRow` (1/2/3 tem mỗi hàng), việc "canh giữa" không phải làm bằng `Align`/`Center` mà được tính toán **bằng padding và spacer cố định 2 bên + giữa các tem**, sao cho tổng bề rộng khớp chính xác với khổ giấy vật lý:

```dart
final double leftPadding  = ... (10.0 cho double, 8.0 cho triple/single)
final double rightPadding = leftPadding;                      // đối xứng 2 bên
final double effectiveSpacer = ... (10.0 double / 12.0 triple / 0.0 single)

final double stampWidthPx = labelPerRow.stampWidth * 6.57;    // mm → px

final double totalWidgetWidth =
    leftPadding +
    (stampWidthPx * itemsPerRow) +
    (effectiveSpacer * (itemsPerRow - 1)) +
    rightPadding;
```

Widget hàng được dựng bằng `Row(mainAxisSize: MainAxisSize.min, ...)` với thứ tự: `[leftPadding] [tem 1] [spacer] [tem 2] [spacer] [tem 3] [rightPadding]`. Vì `leftPadding == rightPadding` và các `stampWidthPx`/`effectiveSpacer` áp dụng đều cho mọi tem, layout tự động đối xứng — đây là kiểu "canh giữa bằng khoảng cách đối xứng" (symmetric margin), không phải canh giữa bằng thuộc tính alignment.

**Trường hợp hàng cuối bị thiếu tem** (ví dụ hàng cho 2 tem/hàng nhưng chỉ còn 1 sản phẩm): thay vì để lệch trái, code chèn thêm `SizedBox(width: stampWidthPx + effectiveSpacer)` vào đúng những vị trí còn thiếu để giữ layout đều — đảm bảo tem đã in không bị dịch chuyển vị trí so với hàng đầy đủ.

**Ép kích thước canvas khớp chính xác**: khi chụp ảnh (`screenshotController.captureFromWidget`), tham số `targetSize: Size(totalWidgetWidth, totalWidgetHeight)` được truyền tường minh trùng khớp với kích thước đã tính toán — đảm bảo ảnh xuất ra không bị crop lệch tâm hay co giãn ngoài ý muốn. Widget còn được bọc trong `MediaQuery` với `devicePixelRatio: 3.0` và `textScaler: TextScaler.noScaling` cố định, tránh việc cài đặt phóng chữ hệ thống của người dùng làm lệch kích thước tính toán.

### 4.B. Căn giữa khi resize ảnh về đúng kích thước vật lý tem (`image_resize.dart` — dùng cho Cup Sticker)

Hàm `resizeImage()` (dùng bởi `CupStickerPrinter`) căn giữa nội dung ảnh bên trong khung tem có padding đều 4 phía:

```dart
final int targetWidthPx  = mmToPx(size.widthMm, dpi);
final int targetHeightPx = mmToPx(size.heightMm, dpi);
final int paddingPx      = mmToPx(paddingMm ?? 2, dpi);       // mặc định padding 2mm mỗi cạnh

// Vùng nội dung = kích thước tem trừ đi padding 2 bên (trái+phải, trên+dưới)
final int contentWidthPx  = (targetWidthPx  - paddingPx * 2).clamp(1, targetWidthPx);
final int contentHeightPx = (targetHeightPx - paddingPx * 2).clamp(1, targetHeightPx);

// Scale ảnh gốc vừa khít vùng nội dung (không giữ tỉ lệ gốc — ép đúng contentWidth x contentHeight)
final codec = await ui.instantiateImageCodec(imageBytes,
    targetWidth: contentWidthPx, targetHeight: contentHeightPx);

// Vẽ nền trắng full kích thước tem
canvas.drawRect(Rect.fromLTWH(0, 0, targetWidthPx, targetHeightPx), whitePaint);

// Vẽ ảnh đã scale, dịch vào đúng offset = paddingPx cả 2 trục → tự động cách đều 4 cạnh
canvas.drawImage(contentImage, Offset(paddingPx, paddingPx), Paint());
```

Vì `paddingPx` bằng nhau ở tất cả 4 cạnh (trái = phải = trên = dưới = cùng 1 giá trị `paddingMm` quy đổi ra px) và ảnh nội dung được scale đúng bằng `targetSize - 2*padding`, nội dung sẽ **tự động nằm giữa** khung tem — đây là kiểu canh giữa bằng công thức offset cố định (không dùng logic đo kích thước ảnh thực tế rồi chia đôi, mà ép ảnh khớp đúng kích thước còn lại sau khi trừ padding hai bên bằng nhau).

Hàm `resizeThermalImage()` (dùng cho ESC/POS receipt, không phải cup sticker) thì **không canh giữa theo cả 2 trục** — chỉ scale `targetWidth` bằng đúng bề rộng giấy nhiệt (384px/576px) và giữ nguyên chiều cao theo tỉ lệ gốc (`ui.instantiateImageCodec(imageBytes, targetWidth: targetWidth)` không truyền `targetHeight`), sau đó vẽ ảnh tại `Offset.zero` (góc trên-trái, không lệch trái/phải vì bề rộng đã khớp chính xác 100% giấy). Việc canh giữa theo chiều ngang cho từng dòng nội dung bên trong (tiêu đề, tên cửa hàng...) do chính widget Flutter tự làm bằng `textAlign: TextAlign.center` khi build `ThermalReceiptPreview` (ví dụ `esc_tab.dart`), trước khi được chụp thành ảnh — tức là căn giữa nội dung xảy ra ở bước dựng UI, còn `resizeThermalImage` chỉ đảm bảo bề rộng ảnh cuối cùng khớp đúng khổ giấy chứ không tự căn giữa nội dung.

### Lưu ý về sự không nhất quán giữa 2 cơ chế

- `LabelFromWidget` dùng hệ số quy đổi mm → px là **hằng số cố định 6.57** (`stampWidth * 6.57`), trong khi `image_resize.dart` dùng công thức chuẩn theo DPI: `mmToPx(mm, dpi) = mm * dpi / 25.4` (với DPI mặc định 203 → hệ số ~7.99). Đây là 2 cách tính "mm sang px" khác nhau cho cùng khái niệm, được dùng ở 2 luồng in khác nhau (Label/BarcodeView vs Cup Sticker) — không gây lỗi chức năng vì chúng phục vụ 2 pipeline độc lập, nhưng là điểm cần lưu ý nếu muốn hợp nhất logic quy đổi kích thước trong tương lai.

---

## Tổng hợp tham chiếu file

| Chủ đề | File chính |
|---|---|
| Facade & platform interface | `lib/src/platform/printer_label.dart`, `printer_label_interface.dart`, `printer_label_method_channel.dart` |
| Ưu tiên thiết bị (native fallback) | `ios/Classes/PrinterLabelPlugin.swift` (`sendToPrinter`), `android/.../PrinterLabelPlugin.kt` (`resolveConnectionsForPrint`) |
| Ưu tiên thiết bị (tầng app) | `example/lib/tabs/esc_tab.dart` (`_targetDeviceIds`), `lib/src/models/device_id.dart` |
| Phát hiện máy in tích hợp | `android/src/main/kotlin/com/printer/printer_label/BuiltInPrinterManager.kt` |
| Căn giữa nhiều tem/hàng | `lib/src/service/label/label_from_widget.dart` |
| Căn giữa ảnh trong khung tem (padding) | `lib/src/utils/image_resize.dart` (`resizeImage`, `resizeThermalImage`) |
| Enum kích thước tem theo hàng | `lib/src/enums/label_per_row_enum.dart` |
