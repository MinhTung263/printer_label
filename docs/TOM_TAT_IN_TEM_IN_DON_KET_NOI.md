# Tóm tắt: In tem, In đơn, Căn khổ giấy, Kết nối máy in

Tài liệu tóm tắt cách sử dụng các hàm chính trong plugin `printer_label` liên quan đến: in tem (TSPL), in đơn/hóa đơn (ESC/POS), cấu hình khổ giấy, và kết nối Bluetooth.

## 1. Cấu trúc dự án

Đây là một **Flutter plugin**, không phải app độc lập:

- `lib/` — API Dart (public interface, model, enum, service)
  - `lib/src/platform/printer_label.dart` — class `PrinterLabel`, API tĩnh chính
  - `lib/src/platform/printer_label_method_channel.dart` — cầu nối MethodChannel
  - `lib/src/enums/` — `label_per_row_enum.dart` (khổ tem), `paper_size_enum.dart` (khổ giấy đơn)
  - `lib/src/models/` — `label_model.dart`, `print_thermal.dart`...
  - `lib/src/service/label/` — `LabelPrintService` (in tem TSPL)
  - `lib/src/service/esc/` — `ESCPrintService` (in đơn ESC/POS)
- `android/src/main/kotlin/com/printer/printer_label/` — code Kotlin native
  - `PrinterLabelPlugin.kt` (894 dòng) — quản lý kết nối, in TSPL, phát hiện mode máy in
  - `PrinterMethodCallHandler.kt` — điều phối MethodChannel, validate lệnh in
  - `BluetoothPrinterManager.kt` (955 dòng) — quét/kết nối BT, quyền, máy in tích hợp
  - `PrinterThermal.kt` — in ảnh/text/barcode ESC/POS
- `ios/Classes/` — code Swift native
  - `PrinterLabelPlugin.swift`, `BLEManager.swift`, `ESCPosPrinter.swift`, `LANPrinterManager.swift`
- `example/` — app demo (`tabs/label_tab.dart` = UI "in tem", `tabs/esc_tab.dart` = UI "in đơn/hóa đơn")

---

## 2. In tem (nhãn dán) — giao thức TSPL

**Luồng gọi (Dart):**

1. `LabelPrintService.printLabels<T>()` — `lib/src/service/label/label_printer_service.dart:18-40`
   Hàm cấp cao nhất nên dùng: chụp widget thành ảnh cho từng tem, build `LabelModel`, gọi `PrinterLabel.printLabel`.
2. `LabelFromWidget.captureImages<T>()` — `lib/src/service/label/label_from_widget.dart:17-139`
   Xếp N tem/hàng (1/2/3 tem), tính kích thước pixel = `stampWidth/stampHeight * 6.57` (hệ số mm→px màn hình), chụp theo lô 10 ảnh để tránh treo máy/hết bộ nhớ.
3. `PrinterLabel.printLabel()` — `lib/src/platform/printer_label.dart:64-74`
   API public, nhận `LabelModel`, gọi method channel `print_label`.
4. `MethodChannelPrinterLabel.printLabel()` — `lib/src/platform/printer_label_method_channel.dart:100-112`
   Đóng gói `LabelModel.toJson()` (`type: 'TSPL'`, `size`, `gap`, `label_count`).

**Native Android** — `PrinterLabelPlugin.printLabel()` — `PrinterLabelPlugin.kt:690-752`:
- Kiểm tra `type == "TSPL"`.
- Đổi mm → dots: `targetWidthDots = sizeWidth * 8` (8 dots/mm ≈ 203 DPI).
- Dịch ảnh trái `-20 dots` để bù độ lệch phần cứng của máy in.
- Dùng `TSPLPrinter`: `.sizeMm(w,h).gapMm(gapW,gapH).reference(0,0).direction(0).cls().bitmap(...).print(1)`.

**Native iOS** — `PrinterLabelPlugin.swift:378-423` — tương tự, dùng `PTCommandTSPL`, cùng bù lệch `-20.0`.

Ngoài in ảnh còn có `printText()`, `printBarcode()`, `printQRCode()` (lệnh TSPL thô) ở cả 2 nền tảng.

---

## 3. In đơn / hóa đơn — giao thức ESC/POS

Trong code **không có hàm tên `printOrder`/`printDon`** — toàn bộ luồng này gọi là **ESC**.

**Luồng gọi (Dart):**

1. `ESCPrintService.printWidget()` — `lib/src/service/esc/esc_print_service.dart:14-28`
   API cấp cao: chụp cả widget hóa đơn thành 1 ảnh dài rồi in.
2. `ESCPrintServiceImpl.printWidget()` → `print()` — `esc_print_service_impl.dart:10-51`
   Chụp ảnh dài (`WidgetCaptureHelper.captureFromLongWidget`) → resize đúng 384px/576px theo `TicketSize` (`resizeThermalImage()`) → gọi `PrinterLabel.printESC()`.
3. `PrinterLabel.printESC()` — `lib/src/platform/printer_label.dart:92-102`
   Nhận `PrintThermalModel`, gọi method channel `print_image_esc`.

**Native Android** — `PrinterThermal.printImageESC()` — `PrinterThermal.kt:15-101`:
- Kiểm tra `type == "ESC"`.
- Convert bitmap → raster ESC/POS 1-bit (`getEscPosRasterBytes()`, ngưỡng xám 200).
- Gói lệnh: `ESC @` (khởi tạo) + `ESC a 1` (căn giữa) + raster + 5×`LF` (feed giấy) + `GS V 66 1` (cắt giấy).
- **Riêng Bluetooth** (không phải máy in tích hợp): gửi theo lô 120 byte, delay 4ms/lô, nghỉ thêm 80ms mỗi 1500 byte — để tránh nghẽn buffer BT SPP.

**Native iOS** — `ESCPosPrinter.swift:8-87`:
- Resize ảnh theo `paperSize` (58mm→384px, 80mm→576px, mặc định 576px).
- Dùng `PTCommandESC`: `initCommandQueue()` → `setJustification(1)` → `appendRasterImage(mode: .dithering)` → `printAndLineFeed()` → `setFullCutWithDistance(1)`.

---

## 4. Căn khổ giấy (paper size)

Tem và đơn dùng **2 hệ thống cấu hình khác hẳn nhau**:

### Tem (TSPL) — theo mm rộng × cao + khe hở (gap)
`lib/src/enums/label_per_row_enum.dart` — class `LabelPerRow` định nghĩa sẵn nhiều khổ:
- `single` = 50×30mm, gap 2mm (mặc định)
- `single40x30`, `single58x40`, `single60x80`, `single70x30`, `single100x100`, `single100x150`, `single102x152`
- `doubleLabels` (2 tem/hàng) = 75×22mm, `double38x25`, `double40x30`, `double46x34`, `double50x30`, `double50x50`
- `triple` (3 tem/hàng) = 112×22mm, `triple30x30`, `triple35x25`, `triple26x26`

Getter `count` trả về 1/2/3 tem/hàng dựa theo tên; `stampWidth`/`stampHeight` trả kích thước vật lý từng tem (dùng để layout widget).

→ Android/iOS đều đổi mm sang dots theo hệ số **8 dots/mm** khi in thực tế; khi chụp ảnh trên màn hình dùng hệ số **6.57 px/mm** (khác nhau vì một bên là độ phân giải máy in, một bên là độ phân giải màn hình).

### Đơn/hóa đơn (ESC/POS) — theo khổ giấy cố định
`lib/src/enums/paper_size_enum.dart` — `enum TicketSize { mm58, mm80 }`:
- `mm58` → 384 dots
- `mm80` → 576 dots

Chỉ có 2 khổ cố định (không tùy chỉnh mm như tem), vì máy in hóa đơn dùng giấy cuộn liên tục, không cần biên tem chính xác như TSPL.

**Tự động nhận khổ giấy máy in tích hợp**: `getBuiltInPrinterPaperSize()` (Android `App.kt:61-90`) — đọc system property Sunmi (`ro.sunmi.printer.paper`) hoặc suy luận theo model máy (máy bàn → 80mm, máy cầm tay → 58mm).

**Tóm lại**: In tem = tự chọn kích thước mm bất kỳ; in đơn = chỉ chọn 1 trong 2 khổ giấy cố định (58mm/80mm).

---

## 5. Kết nối Bluetooth

**API Dart** (`lib/src/platform/printer_label.dart`):

| Hàm | Dòng | Mô tả |
|---|---|---|
| `bluetoothEnabled()` | 15 | Kiểm tra BT đã bật chưa |
| `startBluetoothScan()` / `stopBluetoothScan()` | 113-123 | Quét thiết bị (chỉ có tác dụng trên iOS; Android tự quản lý qua stream) |
| `getBluetoothDevices({filterPrinterOnly})` | 155-157 | Lấy danh sách thiết bị đã ghép đôi (bonded) |
| `bluetoothScanStream({filterPrinterOnly})` | 163-164 | Stream thiết bị quét được theo thời gian thực (EventChannel) |
| `connectBluetooth({macAddress})` | 129-131 | Kết nối tới 1 máy in theo địa chỉ MAC (Android) / UUID (iOS) |
| `autoConnectBuiltIn()` | 133-136 | (Chỉ Android) Tự bật BT và kết nối máy in tích hợp sẵn trên thiết bị POS |
| `checkConnect({deviceId})` | 20-22 | Kiểm tra trạng thái kết nối |
| `disconnectPrinter({deviceId})` | 46-48 | Ngắt kết nối 1 hoặc tất cả máy in |
| `getAllConnections()` | 38-41 | (Chỉ Android) Map deviceId → trạng thái kết nối |

**Native Android** (`BluetoothPrinterManager.kt`):
- `startBluetoothScan()` → `proceedBluetoothScan()` → `actualStartBluetoothScan()` (109-257): xin quyền, tự bật BT, đăng ký `BroadcastReceiver` bắt `ACTION_FOUND`, lọc thiết bị là máy in qua `isPrinter()` (khớp từ khóa như print/pos/thermal/label hoặc tên hãng epson/star/citizen/bixolon/sewoo/tsc/sunmi...).
- `connectBt(macAddress, result)` (266-299): tạo `IDeviceConnection` qua `POSConnect`, lưu vào map `connections`, timeout kết nối 5 giây.
- `autoConnectBuiltIn()` / `autoConnectBuiltInSync()`: tìm thiết bị đã ghép đôi khớp tên hãng POS phổ biến (SUNMI/iMin/Pax/Urovo) và tự kết nối.
- Ngắt kết nối: `PrinterLabelPlugin.disconnectPrinter()` / `disconnectAll()` (468-488) — gọi `conn.close()` và xóa khỏi map.
- Theo dõi trạng thái: map `connections`, `connectionTypes`, hàm `isConnectionActive(deviceId)` (267-285) — coi kết nối BT là "chết" nếu adapter BT hệ thống đang tắt.

**Native iOS** (`BLEManager.swift`):
- `startScan()`/`stopScan()`, `connect(identifier:)`, `disconnect(identifier:)`/`disconnectAll()`, `isConnected(identifier:)`, `hasAnyConnection()` — dùng CoreBluetooth.
- Kết nối LAN dùng manager riêng: `LANPrinterManager`.

---

## 6. Cầu nối MethodChannel (Dart ↔ Native)

- **Kênh chính**: `"flutter_printer_label"` (`lib/src/enums/channel_enum.dart:4`).
- **EventChannel**: `"flutter_printer_label/bt_scan"` (stream thiết bị BT), `"flutter_printer_label/usb_events"` (sự kiện USB, chỉ Android).
- **Các method name chính**: `connect_bt`, `scan_bt`, `stop_scan_bt`, `get_bluetooth_devices`, `print_label` (in tem), `print_image_esc` (in đơn), `checkConnect`, `disconnect`, `auto_connect_built_in`, `check_printer_status`...
- **Android**: `PrinterMethodCallHandler.onMethodCall()` — switch lớn điều phối, lệnh in đi qua `runPrintJob()` để validate loại máy in trước khi gửi.
- **iOS**: `PrinterLabelPlugin.handle()` — switch tương tự, gọi thẳng hàm xử lý (không có bước validate ESC/TSPL như Android).

---

## 7. Tự động phát hiện máy in tích hợp

Chỉ có trên Android — `isBuiltInPrinter()` (`BuiltInPrinterManager.kt`):
- Kiểm tra `Build.MANUFACTURER`/`Build.MODEL` có khớp các hãng POS tích hợp máy in phổ biến hay không (Sunmi/iMin/Pax/Urovo).
- Nếu khớp, `detectPrinterMode()` (`PrinterLabelPlugin.kt`) luôn gán loại máy in là `"ESC"` cho thiết bị đó — không cần probe lệnh trạng thái.
- Dùng kèm `hasBuiltInPrinter()`, `getBuiltInPrinterPaperSize()`, `getBuiltInPrinterName()`, `autoConnectBuiltIn()` để kiểm tra/kết nối máy in tích hợp từ phía Dart.

---

## Ghi chú nhanh khi dùng

- **In tem**: dùng `LabelPrintService` + chọn khổ từ `LabelPerRow` (mm + gap tùy ý).
- **In đơn**: dùng `ESCPrintService` + chọn `TicketSize.mm58` hoặc `TicketSize.mm80`.
- **Kết nối máy in**: quét bằng `bluetoothScanStream()`/`getBluetoothDevices()` → `connectBluetooth(macAddress)` → kiểm tra `checkConnect()` trước khi gọi in.
- Máy in tích hợp trên thiết bị POS (Sunmi...) nên dùng `autoConnectBuiltIn()` thay vì quét BT thủ công.
- Nếu chọn sai hàm in (TSPL/ESC) so với loại máy in thực tế đang kết nối, hệ thống sẽ tự chặn và báo lỗi thay vì in ra giấy lỗi.
