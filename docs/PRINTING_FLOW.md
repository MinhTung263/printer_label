# Tổng quan chi tiết luồng xử lý in — Android & iOS

Tài liệu này giải thích **kỹ và có ngữ cảnh** toàn bộ pipeline in ấn của plugin `printer_label`: không chỉ "code làm gì" mà còn "vì sao nó được viết như vậy", vì phần lớn logic trong plugin này tồn tại để vá các lỗi thực tế (in thiếu tem, in lệch, chữ biến thành ký tự rác, socket bị máy in từ chối...). Hiểu được "vì sao" sẽ giúp không vô tình xóa mất một đoạn code "nhìn có vẻ dư thừa" nhưng thực ra đang chặn một bug cụ thể.

> Quy ước: `file.ext:line` tham chiếu vị trí trong mã nguồn tại thời điểm viết tài liệu (2026-08-22). Số dòng có thể lệch nhẹ theo các lần sửa sau.

---

## Mục lục

1. [Kiến trúc tổng thể 3 tầng](#1-kiến-trúc-tổng-thể-3-tầng)
2. [Tầng Flutter/Dart — hợp đồng MethodChannel](#2-tầng-flutterdart--hợp-đồng-methodchannel)
3. [ANDROID — Nền tảng và lý do chọn kiến trúc này](#3-android--nền-tảng-và-lý-do-chọn-kiến-trúc-này)
4. [ANDROID — Kết nối Bluetooth: giải thích từng bước](#4-android--kết-nối-bluetooth-giải-thích-từng-bước)
5. [ANDROID — Kết nối USB: giải thích từng bước](#5-android--kết-nối-usb-giải-thích-từng-bước)
6. [ANDROID — Kết nối LAN: giải thích cơ chế chia sẻ socket](#6-android--kết-nối-lan-giải-thích-cơ-chế-chia-sẻ-socket)
7. [ANDROID — Máy in tích hợp (built-in)](#7-android--máy-in-tích-hợp-built-in)
8. [ANDROID — Cách lệnh in được build và gửi](#8-android--cách-lệnh-in-được-build-và-gửi)
9. [ANDROID — Xử lý ảnh, két tiền, code chết, hằng số](#9-android--xử-lý-ảnh-két-tiền-code-chết-hằng-số)
10. [iOS — Nền tảng và lý do chọn kiến trúc này](#10-ios--nền-tảng-và-lý-do-chọn-kiến-trúc-này)
11. [iOS — Kết nối Bluetooth Low Energy: giải thích từng bước](#11-ios--kết-nối-bluetooth-low-energy-giải-thích-từng-bước)
12. [iOS — Kết nối LAN: giải thích cơ chế xác nhận & retry](#12-ios--kết-nối-lan-giải-thích-cơ-chế-xác-nhận--retry)
13. [iOS — Cách lệnh ESC/POS được build từ ảnh](#13-ios--cách-lệnh-escpos-được-build-từ-ảnh)
14. [iOS — Định tuyến lệnh in & cấu hình mạng](#14-ios--định-tuyến-lệnh-in--cấu-hình-mạng)
15. [So sánh Android vs iOS](#15-so-sánh-android-vs-ios)
16. [Luồng ví dụ end-to-end](#16-luồng-ví-dụ-end-to-end)

---

## 1. Kiến trúc tổng thể 3 tầng

```
┌───────────────────────────────────────────────────────────────────┐
│  FLUTTER / DART (lib/)                                            │
│  - PrinterLabel (facade) → PrinterLabelPlatform                   │
│  - ESCPrintServiceImpl / LabelPrintServiceImpl / CupSticker...    │
│  - MethodChannelPrinterLabel (implements PrinterLabelPlatform)    │
└───────────────────────────┬─────────────────────────────────────-─┘
                            │ MethodChannel "flutter_printer_label"
                            │ EventChannel  ".../bt_scan", ".../usb_events"
              ┌─────────────┴─────────────┐
              ▼                           ▼
┌────────────────────────────┐ ┌───────────────────────────────────┐
│  ANDROID (Kotlin)          │ │  iOS (Swift)                      │
│  PrinterLabelPlugin        │ │  PrinterLabelPlugin               │
│  → PrinterMethodCallHandler│ │  → route trực tiếp trong handle() │
│  → BluetoothPrinterManager │ │  → BLEManager.shared              │
│  → PrinterThermal (ESC)    │ │  → ESCPosPrinter                  │
│  → UrovoPrinterManager      │ │  → LANPrinterManager.shared       │
│  → CashBoxManager            │ │  → POSNetConfigHelper             │
│  → LanPrinterProbe            │ │  → ImageUtils (binarized)         │
│  → NetworkConfigHelper        │ │                                    │
│  → UsbConnectionReceiver       │ │  (iOS không có USB printer)       │
│  Dựa trên SDK net.posprinter    │ │  Dựa trên CoreBluetooth +          │
│  (jar bên thứ 3, POSPrinter/     │ │  Network.framework (tự viết),      │
│  TSPLPrinter/IDeviceConnection)   │ │  chỉ dùng SDK ngoài cho TSPL/ESC    │
│                                    │ │  "gốc" (text/barcode/QR)           │
└────────────────────────────┘ └───────────────────────────────────┘
```

**Vì sao 2 nền tảng lại được viết theo 2 triết lý hoàn toàn khác nhau?**

Android dùng một SDK thương mại đóng gói sẵn (`net.posprinter`) làm lớp trừu tượng hóa kết nối (`IDeviceConnection`) — tức là plugin Android **không tự viết code đọc/ghi `BluetoothSocket` hay `Socket` TCP thô**, mà giao toàn bộ việc đó cho SDK, chỉ tự build lệnh in và tự lo phần "đóng gói lại" (retry, chia gói, đồng bộ) bên trên SDK.

iOS thì ngược lại: **tự viết toàn bộ tầng vận chuyển** — `BLEManager` tự gọi trực tiếp `CBCentralManager`/`CBPeripheral` (CoreBluetooth), `LANPrinterConnection` tự gọi trực tiếp `NWConnection` (Network.framework). SDK ngoài (`PrinterSDK` — `PTCommandTSPL`/`PTCommandESC`/`PTDispatcher`) chỉ được dùng để build các lệnh TSPL/ESC "gốc" (text, barcode, QR không phải ảnh) — còn phần in ảnh (chiếm phần lớn khối lượng in thực tế, vì hầu hết nội dung được Flutter render sẵn thành bitmap) được tự build byte thủ công trong `ESCPosPrinter.swift`.

Hệ quả thực tế: khi đọc code Android, bạn sẽ thấy nhiều lớp "manager" mỏng gọi xuống SDK; khi đọc code iOS, bạn sẽ thấy logic dày hơn nằm ngay trong `BLEManager`/`LANPrinterConnection` vì không có SDK nào lo phần đó cho bạn.

---

## 2. Tầng Flutter/Dart — hợp đồng MethodChannel

### 2.1 Channel

| Channel | Loại | Vai trò |
|---|---|---|
| `flutter_printer_label` | MethodChannel | Toàn bộ lệnh connect/disconnect/print/status |
| `flutter_printer_label/bt_scan` | EventChannel | Stream thiết bị Bluetooth quét được |
| `flutter_printer_label/usb_events` | EventChannel | Stream attach/detach USB (chỉ Android; iOS trả stream rỗng vì không có USB printer) |

Định nghĩa tại `lib/src/platform/printer_label_method_channel.dart` và `lib/src/enums/printer_method_enum.dart`.

### 2.2 Danh sách method (enum `PrinterMethod`)

`getPlatformVersion`, `checkConnect`, `disconnect`, `connect_lan`, `connect_bt`, `connect_usb`, `scan_bt`, `stop_scan_bt`, `get_bluetooth_devices`, `print_label`, `print_image`, `print_image_esc`, `bluetooth_enabled`, `print_text`, `print_text_esc`, `print_barcode`, `print_qrcode`, `print_barcode_esc`, `print_qrcode_esc`, `check_printer_status`, `auto_connect_built_in`, `has_built_in_printer`, `get_built_in_printer_paper_size`, `open_drawer`.

Ngoài enum còn có method gọi bằng string literal trực tiếp (không qua enum): `scan_net_printers`, `set_net_ip`, `get_lan_printer_info`, `identify_lan_printer`.

### 2.3 Vì sao có 2 định dạng in song song: TSPL vs ESC?

Đây là điểm mấu chốt để hiểu toàn bộ tài liệu: plugin phục vụ **2 loại máy in vật lý khác hẳn nhau**, và mỗi loại có ngôn ngữ lệnh riêng:

- **Máy in tem/label** (dán decal, có cảm biến khe hở giữa các tem) → hiểu ngôn ngữ **TSPL** (TSC Printer Language). Model tương ứng là **`LabelModel`** (`lib/src/models/label_model.dart`), `toJson()` gắn `"type": "TSPL"`, dùng cho method `print_label`. Có cờ `isLastBatch`: khi in một dải rất dài (ví dụ 500 tem), Dart không chờ render hết toàn bộ rồi gửi một cục dữ liệu khổng lồ, mà **chia thành nhiều lô ảnh, mỗi lô một lời gọi native riêng**. Native chỉ được nhả socket LAN ở lô **cuối cùng** — nếu nhả giữa lô, lô kế tiếp phải mở lại đúng socket chưa giải phóng hẳn phía máy in ("máy in đang bận") → tem in ra lệch hoặc lỗi.
- **Máy in hóa đơn nhiệt** (receipt/ticket, không có khe hở tem) → hiểu ngôn ngữ **ESC/POS** (chuẩn Epson, phổ biến nhất trong ngành POS). Model tương ứng là **`PrintThermalModel`** (`lib/src/models/print_thermal.dart`), `toJson()` gắn `"type": "ESC"`, dùng cho method `print_image_esc`. Toàn bộ nội dung hóa đơn (text, logo, bảng giá...) được Flutter **chụp lại thành một ảnh bitmap duy nhất** (`WidgetCaptureHelper`) rồi gửi nguyên khối xuống native — native không cần biết bố cục hóa đơn, chỉ cần biến ảnh đó thành lệnh raster ESC/POS.

Cả hai đều nhận `device_id` + `connection_type` (`USB`/`LAN`/`Bluetooth`) tùy chọn để chỉ định đích in; nếu bỏ trống, native tự suy luận đích in (xem mục 6 và mục 14).

### 2.4 Lớp service phía Dart — vì sao cần các bước tối ưu trước khi gọi native?

- **`ESCPrintServiceImpl`**: `printWidget`/`printWidgetToDevices` chụp widget Flutter thành ảnh, rồi **resize tối ưu cho tốc độ truyền Bluetooth** (`resizeThermalImage`) — vì Bluetooth Classic/BLE có băng thông thấp hơn nhiều so với USB/LAN, ảnh gốc độ phân giải cao sẽ khiến việc gửi mất nhiều giây; resize giảm dung lượng dữ liệu cần truyền mà vẫn giữ đủ độ phân giải cho đầu in nhiệt (khổ giấy 384/576 dots không cần ảnh siêu nét). Hàm này cũng hỗ trợ in đồng thời nhiều máy (`Future.wait`) và **mở két trước khi gửi bill, chỉ trên các máy đang thực sự in lượt đó** — lý do: nếu mở két vô điều kiện trên mọi máy có gắn két, thì in ở quầy bếp/bar (không nên mở két thu ngân) sẽ vô tình bật két thu ngân của quầy khác.
- **`LabelPrintServiceImpl`**: `printLabels` dùng callback `onBatch` để **gửi từng lô ảnh ngay khi render xong**, không chờ render toàn bộ dải dài rồi mới gửi — vì nếu chờ, socket tới máy in (đặc biệt LAN) sẽ im lặng quá lâu và bị chính máy in/hệ điều hành cắt do idle timeout, khiến lệnh in thất bại giữa dải.

---

## 3. ANDROID — Nền tảng và lý do chọn kiến trúc này

### 3.1 SDK nền tảng: `net.posprinter.*`

Toàn bộ tầng kết nối/gửi lệnh (BT, LAN, USB) đi qua một SDK bên thứ ba đóng gói sẵn (`libs/printer-lib-3.2.0/classes.jar`, khai báo tại `android/build.gradle:57`, kèm thư viện native `.so` cho 4 kiến trúc CPU trong `libs/printer-lib-3.2.0/jni/`). Đây là dạng SDK "POSPrinter/Xprinter/Gprinter" phổ biến trong ngành máy in nhiệt Trung Quốc, cung cấp:



- **`POSConnect`** — factory khởi tạo và tạo kết nối: `POSConnect.init(context)` (phải gọi 1 lần khi plugin khởi động), `POSConnect.createDevice(type)` với `type ∈ {DEVICE_TYPE_BLUETOOTH, DEVICE_TYPE_ETHERNET, DEVICE_TYPE_USB, DEVICE_TYPE_SERIAL}`.
- **`IDeviceConnection`** — interface trừu tượng hóa **mọi** loại kết nối vật lý về cùng một API: `.connect(id, IConnectListener)` (id là địa chỉ MAC/IP/định danh USB tùy loại), `.sendData()` (bất đồng bộ, đưa vào hàng đợi nội bộ của SDK — plugin không kiểm soát được khi nào byte thực sự ra khỏi thiết bị), `.sendSync()` (đồng bộ, ghi thẳng xuống stream vật lý và **trả về số byte thực sự đã gửi** — đây là API mà plugin dùng cho phần lớn logic quan trọng, vì nó cho phép kiểm tra và retry chính xác), `.isConnect`, `.close()`, `.setSendCallback()` (đăng ký callback biết khi nào 1 lệnh cụ thể đã được đẩy ra khỏi hàng đợi).
- **`POSPrinter`** — builder lệnh ESC/POS cấp cao (text, barcode, ảnh, cắt giấy...), đồng thời cũng chứa `POSPrinter.searchNetDevice`/`udpNetConfig` để quét/cấu hình máy in LAN qua UDP broadcast (dòng Xprinter).
- **`TSPLPrinter`** — builder lệnh TSPL cấp cao (khổ giấy, gap, bitmap, in tem).

Điều quan trọng cần hiểu: **mọi "manager" trong plugin Android (Bluetooth/LAN/USB) chỉ có một nhiệm vụ duy nhất — tạo và quản lý vòng đời một `IDeviceConnection`**. Việc build lệnh in cụ thể và quyết định cách gửi (đồng bộ/chunk/retry) được tách riêng ra `PrinterThermal` và `PrinterLabelPlugin`, để không phải lặp lại logic đó cho từng loại kết nối.

> **Lưu ý dễ gây nhầm lẫn**: `android/print_constants.kt` — mặc dù tên gợi ý là file hằng số — thực chất là một **script `main()` độc lập**, dùng reflection để in ra console toàn bộ field static của class `android.device.PrinterManager` (SDK hệ thống của Urovo). Đây là công cụ debug thủ công dev dùng để khảo sát API lúc viết `UrovoPrinterManager`, không nằm trong package chính (`com.printer.printer_label`) và **không tham gia runtime của plugin**.

### 3.2 Sơ đồ lớp và state trung tâm

```
PrinterLabelPlugin (FlutterPlugin, ActivityAware)      — entry point, giữ toàn bộ state kết nối
   │
   ├─ PrinterMethodCallHandler (MethodCallHandler)      — dispatcher method → hàm xử lý trên plugin
   │
   ├─ BluetoothPrinterManager    — scan/connect/permission Bluetooth
   ├─ PrinterThermal             — build & gửi lệnh ESC/POS (text/barcode/QR/ảnh/mở két)
   ├─ UrovoPrinterManager        — điều khiển máy in tích hợp Urovo qua reflection (không qua IDeviceConnection)
   ├─ CashBoxManager             — mở két tiền native (RJ11/RJ12) qua reflection/AIDL/broadcast hãng POS
   ├─ LanPrinterProbe            — dò MAC/hãng máy in LAN qua ARP (không mở socket)
   ├─ NetworkConfigHelper        — build & gửi lệnh ESC cấu hình IP qua TCP 9100
   ├─ BuiltInPrinterManager.kt   — (hàm top-level) nhận diện & lấy khổ giấy máy in tích hợp
   ├─ UsbConnectionReceiver      — BroadcastReceiver ACTION_USB_DEVICE_ATTACHED/DETACHED
   └─ ConnectionType             — enum USB/LAN/BT
```

`PrinterLabelPlugin` là "bộ nhớ trung tâm" giữ **toàn bộ state kết nối đa thiết bị** — điều này cần thiết vì một ứng dụng POS thực tế thường in đồng thời trên nhiều máy (máy in bill ở quầy, máy in bếp, máy in tem dán sản phẩm...), nên plugin không thể chỉ giữ "một kết nối hiện tại" như nhiều SDK demo đơn giản:

- `connections: ConcurrentHashMap<String, IDeviceConnection>` — khóa là `device_id` (dạng `"BT:<mac>"`, `"LAN:<ip>"`, `"USB:v..._p..._s..."`, hoặc `"BUILT_IN"`). Dùng `ConcurrentHashMap` vì nhiều thread (callback , thread in, maiSDKn thread Flutter) đọc/ghi đồng thời.
- `connectionTypes: ConcurrentHashMap<String, ConnectionType>` — nhớ mỗi deviceId thuộc loại kết nối nào, để khi resolve đích in không phải suy luận lại từ chuỗi.
- `builtInDeviceIds` — set các deviceId đã được xác nhận là máy in tích hợp (đánh dấu lúc connect qua `autoConnectBuiltIn`).
- `pendingConnects` — **giải quyết một vấn đề đồng thời cụ thể**: nếu Dart gọi `connect_bt` hai lần liên tiếp trước khi lần đầu trả kết quả (ví dụ do `Future.wait` gọi song song trên nhiều màn hình), SDK chỉ gọi callback `IConnectListener` một lần — nếu không gộp `Result` lại, `Result` thứ hai sẽ treo vĩnh viễn (Dart `await` không bao giờ hoàn thành). `pendingConnects` gộp mọi `Result` trùng deviceId để tất cả đều được `complete()` cùng lúc.
 + Vấn 

- `registeredLanPrinters` — set các IP máy in LAN **đã từng kết nối thành công ít nhất một lần**. Đây là nền tảng cho cơ chế "nhả rồi tự mở lại socket" giải thích ở mục 6.

`PrinterMethodCallHandler` nhận `plugin: PrinterLabelPlugin` qua constructor và dispatch bằng `when (call.method)` — gọi trực tiếp các hàm public/internal trên `plugin`, không có tầng trung gian nào khác.

---

## 4. ANDROID — Kết nối Bluetooth: giải thích từng bước

Toàn bộ logic nằm ở `BluetoothPrinterManager.kt`. Đây là **Bluetooth Classic (SPP — Serial Port Profile)**, khác với BLE dùng trên iOS — lý do là phần lớn máy in nhiệt giá rẻ/phổ thông ở Android dùng chip Bluetooth Classic (mô phỏng cổng serial), trong khi máy in mini cầm tay hay dùng ở iOS thường là BLE.

### 4.1 Lấy adapter & liệt kê thiết bị

`getBluetoothAdapter()` dùng `BluetoothManager.getAdapter()` trên API ≥ M (Android 6.0), fallback về `BluetoothAdapter.getDefaultAdapter()` (API cũ hơn, đã deprecated nhưng vẫn cần cho thiết bị Android cũ). `getBluetoothDevices()` đọc `adapter.bondedDevices` — tức là **danh sách thiết bị đã ghép nối ở tầng hệ điều hành** (người dùng đã pair trong Settings hoặc qua dialog pairing), không phải kết quả scan.

### 4.2 Vì sao cần lọc "có phải máy in không"?

`isPrinter()` so khớp tên thiết bị Bluetooth với 2 nhóm từ khóa:
- **Từ khóa dài, khớp ở bất kỳ vị trí trong tên**: `print, pos, thermal, epson, star, sunmi,...` — các hãng/loại thiết bị rõ ràng.
- **Tiền tố ngắn, chỉ khớp ở đầu tên** (hoặc kèm dấu phân định `-`/`_`/khoảng trắng): `mpt, rpp, xp, zj,...` — vì các chuỗi 2-3 ký tự này rất dễ trùng ngẫu nhiên với tên thiết bị khác (tai nghe, loa...) nếu cho khớp tự do ở giữa chuỗi.

Việc lọc này tồn tại vì danh sách `bondedDevices` của một điện thoại dùng lâu có thể chứa hàng chục thiết bị (tai nghe, đồng hồ, xe hơi...) — nếu hiển thị tất cả cho người dùng chọn máy in sẽ gây nhầm lẫn nghiêm trọng trong ứng dụng POS.

### 4.3 Quy trình scan (discovery) — 4 bước có thể thất bại độc lập

`startBluetoothScan()` không đơn giản gọi `adapter.startDiscovery()` ngay, vì có nhiều điều kiện tiên quyết trên Android:

1. **Xin quyền** (`requestScanPermissions`) — Android 12+ (API 31) yêu cầu `BLUETOOTH_SCAN` là quyền runtime riêng (trước đó gộp vào location permission).
2. **Kiểm tra & nhắc bật GPS** nếu API < 31 — vì trên các bản Android cũ, quét Bluetooth **về mặt kỹ thuật đòi hỏi Location Services đang bật** (do scan Bluetooth có thể suy ra vị trí tương đối qua RSSI), dù ứng dụng không cần định vị thật.
3. **Bật Bluetooth nếu đang tắt**: `proceedBluetoothScan()` thử `adapter.enable()` (API ngầm, deprecated, không hiện dialog) và poll tối đa 25×200ms (~5s) xem đã bật chưa; nếu không thành công thì mới hiện dialog chính thức `ACTION_REQUEST_ENABLE` (yêu cầu người dùng xác nhận, request code `1001`) — thứ tự ưu tiên "thử ngầm trước, hỏi người dùng sau" giúp trải nghiệm mượt hơn trên thiết bị POS chuyên dụng (kiosk) nơi việc bật ngầm thường được cho phép.
4. **Thực thi scan thật**: `actualStartBluetoothScan()` đăng ký `BroadcastReceiver` nội bộ lắng 2 sự kiện hệ thống — `BluetoothDevice.ACTION_FOUND` (mỗi khi tìm thấy 1 thiết bị mới) và `BluetoothAdapter.ACTION_DISCOVERY_FINISHED` (khi quét xong, thường sau ~12s theo giới hạn của Android) — rồi gọi `adapter.startDiscovery()`. Mỗi thiết bị tìm thấy được đẩy ngay qua `scanEventSink` (EventChannel) dưới dạng `{name, mac}` để Dart cập nhật UI theo thời gian thực (không chờ quét xong mới trả 1 danh sách).

### 4.4 Kết nối (`connectBt`) — vì sao có bước "gộp Result"?

```
connectBt(macAddress, result, markBuiltIn):
  1. deviceId = "BT:$macAddress"
  2. Nếu đã có pending connect cùng deviceId → gộp Result mới vào, KHÔNG tạo connection mới
  3. POSConnect.createDevice(DEVICE_TYPE_BLUETOOTH) → lưu vào connections/connectionTypes
  4. device.connect(rawId(deviceId), makeConnectListener(deviceId))
  5. scheduleConnectTimeout(deviceId)  — timeout 5000ms
```

Bước 2 tồn tại vì UI Flutter có thể gọi `connectBluetooth` nhiều lần liên tiếp (ví dụ người dùng bấm nút "Kết nối" 2 lần do phản hồi chậm) — nếu tạo 2 `IDeviceConnection` riêng cho cùng một MAC, SDK có thể rơi vào trạng thái không xác định (2 socket cùng cố gắng bind vào 1 địa chỉ Bluetooth). Gộp `Result` đảm bảo chỉ có đúng 1 lời gọi `connect()` thực sự chạy, còn tất cả các `Result` Dart đang chờ đều nhận cùng kết quả khi nó tới.

**`makeConnectListener()`** (dùng chung cho cả BT/USB/LAN) xử lý các mã trạng thái từ `IConnectListener` của SDK: `CONNECT_SUCCESS` (lưu connection, hoàn tất `Result` với `true`), `CONNECT_FAIL`/`CONNECT_INTERRUPT` (hoàn tất `false`), `SEND_FAIL` (lỗi khi đang gửi dữ liệu — không phải lỗi connect), `USB_DETACHED`/`USB_ATTACHED` (chỉ có ý nghĩa với kết nối USB).

**Timeout kết nối 5000ms** (`scheduleConnectTimeout`) tồn tại vì nếu máy in đã tắt nguồn hoặc ngoài vùng phủ sóng, `IConnectListener` của SDK có thể **không bao giờ được gọi lại** — không có timeout, `Result` Dart sẽ treo vô hạn, khiến UI loading xoay mãi.

### 4.5 Auto-connect máy in tích hợp qua Bluetooth nội bộ

Nhiều thiết bị POS cầm tay (Sunmi, iMin, Pax...) có máy in tích hợp **nhưng giao tiếp với hệ điều hành qua một adapter Bluetooth nội bộ** (không phải Bluetooth thật ra ngoài) — với hệ điều hành, nó vẫn hiện ra như "một thiết bị Bluetooth đã ghép nối sẵn". `autoConnectBuiltIn()`/`autoConnectBuiltInSync()` tìm trong `bondedDevices` thiết bị khớp `isBuiltInPrinterName()` (từ khóa `SUNMI, iMin, Pax, Urovo, B68, P068, SmartPos, InnerPrinter, BluetoothPrinter,...`) hoặc có `BluetoothClass.Device.Major.IMAGING` (nhóm thiết bị hình ảnh/in ấn theo phân loại Bluetooth chuẩn), rồi gọi `connectBt(mac, markBuiltIn=true)` — cờ `markBuiltIn` khiến deviceId được thêm vào `builtInDeviceIds`, để các lệnh in sau này nhắm `device_id == "BUILT_IN"` biết phải route tới đúng connection này.

### 4.6 Quyền (permission) — khác biệt giữa các phiên bản Android

Android đã thay đổi mô hình quyền Bluetooth qua nhiều version: trước Android 12 dùng `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` làm điều kiện cho scan; từ Android 12 (API 31) có quyền riêng `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`. `hasConnectPermission()`/`hasScanPermission()` kiểm tra đúng bộ quyền theo `Build.VERSION.SDK_INT`. Nếu bị từ chối, `showPermissionDialog()` **tự vẽ một dialog bằng code thuần** (`LinearLayout`/`GradientDrawable`, không dùng layout XML) dẫn người dùng tới `openAppSettings()` — cách làm này tránh phải thêm resource XML vào một plugin (plugin không có Activity/theme riêng để chắc chắn style dialog chuẩn hệ thống hiển thị đúng).

### 4.7 Gửi lệnh in qua Bluetooth — vì sao phải chunk và sleep?

Chi tiết đầy đủ ở mục 8, nhưng điểm mấu chốt riêng cho Bluetooth: dữ liệu được chia thành **gói 120 bytes**, sleep **4ms** sau mỗi gói, và nghỉ thêm **80ms mỗi khi đã gửi đủ 1500 bytes**. Đây không phải giới hạn kỹ thuật của Bluetooth Classic (SPP có thể truyền nhanh hơn nhiều) — mà là **giới hạn tốc độ xử lý của đầu in nhiệt vật lý**: đầu in cần thời gian để làm nóng và kéo giấy, nếu dữ liệu tới nhanh hơn tốc độ in thật, buffer nội bộ máy in tràn và bị mất dữ liệu hoặc in sai. Việc này chỉ áp dụng cho Bluetooth ngoài (không áp dụng máy in tích hợp, vì máy in tích hợp giao tiếp qua bus nội bộ tốc độ cao và ổn định hơn nhiều).

// mức này đang được test qua các lần thử nghiệm

### 4.8 Phân tích cải thiện — rủi ro treo vĩnh viễn chưa được xử lý (2026-08-22)

Rà soát bổ sung (chưa vá) phát hiện 3 điểm có thể khiến một luồng/Result bị **treo vô thời hạn** thay vì fail rõ ràng — nguy hiểm hơn một lỗi in bình thường vì không có thông báo nào cho người dùng biết app đang "đứng hình":

- **`autoConnectBuiltInSync()` chờ quyền không có timeout** — [`latchPermission.await()`](android/src/main/kotlin/com/printer/printer_label/BluetoothPrinterManager.kt#L850) không truyền timeout, khác hẳn latch chờ bật Bluetooth ngay bên dưới có timeout rõ ràng 30s. Nếu dialog xin quyền `BLUETOOTH_CONNECT` hiện ra mà người dùng không phản hồi (chuyển app, đa nhiệm), luồng gọi hàm này (thường chạy lúc khởi động plugin) **treo vĩnh viễn**. *Gợi ý: thêm timeout 15-20s cho `latchPermission.await()`, coi như "không cấp quyền" nếu hết hạn.*
- **`permissionCallback` là một field global duy nhất**, dùng chung cho cả [`requestConnectPermissions`](android/src/main/kotlin/com/printer/printer_label/BluetoothPrinterManager.kt#L669) (gán callback ở [dòng 692](android/src/main/kotlin/com/printer/printer_label/BluetoothPrinterManager.kt#L692)) và [`requestScanPermissions`](android/src/main/kotlin/com/printer/printer_label/BluetoothPrinterManager.kt#L711) (gán callback ở [dòng 737](android/src/main/kotlin/com/printer/printer_label/BluetoothPrinterManager.kt#L737)). Nếu 2 luồng xin quyền chồng lên nhau gần như đồng thời (ví dụ auto-connect built-in đang xin CONNECT trong khi người dùng bấm "Scan" xin SCAN), callback trước bị ghi đè và **không bao giờ được gọi lại** — lệnh gọi tương ứng treo mãi. *Gợi ý: đổi thành hàng đợi callback theo request code thay vì 1 field dùng chung.*
- **Dialog xin quyền tự vẽ bằng code** ([`showPermissionDialog`](android/src/main/kotlin/com/printer/printer_label/BluetoothPrinterManager.kt#L524), [`showLocationSettingsDialog`](android/src/main/kotlin/com/printer/printer_label/BluetoothPrinterManager.kt#L767)) dùng `plugin.activity` để `.show()`, nhưng [`onDetachedFromActivity()`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L182) chỉ set `activity = null`, không `dismiss()` dialog đang mở. Nếu Activity bị huỷ khi dialog còn hiện (xoay màn hình, back/finish) → nguy cơ `WindowLeakedException` khi window token đã invalid. *Gợi ý: giữ reference dialog, gọi `dismiss()` trong `onDetachedFromActivity()`.*
- Bổ sung nhỏ: [`disconnectPrinter`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L550)/[`disconnectAll`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L578) không huỷ `pendingConnects` đang chờ cùng `deviceId` — nếu người dùng bấm Connect rồi Disconnect gần như đồng thời, connect đang chạy nền có thể vẫn thành công sau đó và "hồi sinh" đúng kết nối mà người dùng vừa yêu cầu ngắt.

---

## 5. ANDROID — Kết nối USB: giải thích từng bước

Phần này phức tạp hơn Bluetooth/LAN vì Android USB Host API có nhiều lớp bất đồng bộ (broadcast hệ thống, permission dialog, driver USB) mà plugin phải điều phối đúng thứ tự.

### 5.1 Vì sao cần một định danh USB "ổn định"?

Android cấp cho mỗi thiết bị USB một `device.deviceName` dạng đường dẫn hệ thống (`/dev/bus/usb/001/002`) — **đường dẫn này có thể thay đổi** giữa các lần cắm lại (tùy thứ tự enumerate của kernel). Nếu plugin dùng `deviceName` làm khóa để nhớ "máy in này đã kết nối trước đây", Dart sẽ mất kết nối đã lưu mỗi khi rút/cắm lại dây. Giải pháp: `stableUsbId(device)` build định danh từ **Vendor ID + Product ID + Serial Number** của chính thiết bị (`"USB:v{vid}_p{pid}_s{serial}"`) — 3 giá trị này là thuộc tính vật lý của thiết bị, không đổi qua các lần cắm lại (trừ khi không lấy được serial, khi đó bỏ phần `_s...`).

### 5.2 Luồng khi cắm dây USB

1. Hệ điều hành phát broadcast `ACTION_USB_DEVICE_ATTACHED` → `UsbConnectionReceiver.onReceive()` nhận, gọi `plugin.handleUsbDeviceAttached(device)`.
2. Plugin lưu `usbDevicePaths[deviceId] = device.deviceName`, hiện Toast thông báo.
3. Kiểm tra `usbManager.hasPermission(device)`:
   - **Đã có quyền** (ví dụ Android đã nhớ quyền từ lần cắm trước) → gọi `tryConnectWithDelay(device, 0)` ngay.
   - **Chưa có quyền** → `requestUsbPermissionOnce()` mở dialog xin quyền hệ thống, **đồng thời** đặt `postDelayed(500ms)` để tự thử connect nếu quyền vừa được cấp qua một đường khác (ví dụ Android tự cấp quyền cho ứng dụng đã khai `usb_device_filter` trong manifest, không hiện dialog).

### 5.3 Vì sao phải chặn xin quyền trùng lặp?
`requestUsbPermissionOnce()` dùng set `pendingPermissionRequests` để đảm bảo **không mở 2 dialog xin quyền chồng nhau cho cùng một thiết bị**. Lý do được ghi rõ trong comment mã nguồn: nếu dialog xin quyền thứ 2 mở trong khi dialog thứ 1 đang hiện, hệ điều hành có thể coi ứng dụng "mất foreground" trong khoảnh khắc chuyển đổi — và khi mất foreground, Android có thể **đóng USB session đang mở**, khiến gói dữ liệu in đầu tiên gửi ngay sau đó bị lỗi dù kết nối "trông có vẻ" thành công.

### 5.4 Trì hoãn trước khi connect thật

`tryConnectWithDelay(device, attempt)` không gọi `POSConnect.createDevice`/`connect()` ngay khi có quyền, mà trì hoãn **1200ms** (lần đầu) hoặc **800ms** (các lần retry) — khoảng nghỉ này cho driver USB-serial thời gian khởi tạo hoàn chỉnh ở tầng hệ điều hành trước khi SDK cố gắng mở stream đọc/ghi. Nếu `createDevice` trả `null` hoặc ném exception, hàm tự retry tối đa 3 lần.

### 5.5 Kết nối tường minh từ Dart — khôi phục sau khi app bị kill

`connectUsb(deviceId, result)` cho phép Dart chủ động gọi kết nối lại (không chỉ dựa vào broadcast ATTACHED) — quan trọng vì: nếu app Android bị hệ điều hành kill (do thiếu RAM) rồi người dùng mở lại app, `connections` (map trong memory) đã mất, nhưng **hệ điều hành sẽ không bắn lại `ACTION_USB_DEVICE_ATTACHED`** cho một thiết bị vẫn đang cắm sẵn (event ATTACHED chỉ bắn khi cắm mới). Do đó Dart cần một cách chủ động quét lại và kết nối, và `connectUsb` quét `usbManager.deviceList` tìm thiết bị khớp `stableUsbId` để phục vụ đúng nhu cầu này.

### 5.6 Xác nhận "đã sẵn sàng ghi thật" sau khi SDK báo thành công

Một vấn đề tinh vi: SDK `net.posprinter` có thể gọi callback `CONNECT_SUCCESS` **trước khi driver USB ở tầng hệ điều hành thực sự sẵn sàng nhận ghi** (do độ trễ khởi tạo driver). Để tránh gói dữ liệu in đầu tiên bị rơi mất, `makeConnectListener` — riêng với USB — spawn một thread gửi thử `sendSync(byteArrayOf(0x00))` (1 byte rác, vô hại với hầu hết máy in) tối đa 5 lần với backoff tăng dần (`150ms × i`) **trước khi** thực sự gọi `complete(true)` trả cho Dart. Chỉ khi byte thử nghiệm này gửi thành công, plugin mới coi kết nối USB là "sẵn sàng".

### 5.7 Rút dây & EventChannel `usb_events`

`handleUsbDeviceDetached()` đóng connection, dọn khỏi mọi map, phát event. `usbEventStreamHandler`: khi Dart bắt đầu lắng nghe stream, plugin **chủ động quét lại** toàn bộ `usbManager.deviceList`, lọc bằng `isUsbPrinter()` (`device.deviceClass == 7` — mã lớp thiết bị chuẩn USB Printer Class) và tự động attach các máy in đang cắm sẵn — đảm bảo Dart nhận được trạng thái đúng ngay cả khi bắt đầu lắng nghe sau khi thiết bị đã cắm từ trước.

### 5.8 Gửi lệnh in qua USB

Dùng chung route raster + `sendAllSync` với LAN (chunk 4096 bytes) — **không còn dùng** `POSPrinter.printBitmap` (API cấp cao của SDK) như thiết kế ban đầu, vì đã gặp bug thực tế: in nhiều bản (`quantity > 1`) qua USB chỉ ra đúng 1 bản. Chuyển sang tự build byte + `sendSync` tự kiểm soát cho phép phát hiện và retry chính xác khi có byte bị rơi.

### 5.9 Phân tích cải thiện — case có thể in lỗi/treo qua USB (2026-08-22)

- **[`connectUsb`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L874)/[`tryConnectWithDelay`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L990) không hề gọi [`scheduleConnectTimeout`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L607)** — khác với `connect_bt`/`connect_lan` (gọi ở [dòng 854](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L854)) luôn có timeout 5000ms bảo vệ. Nếu SDK `net.posprinter` không bao giờ gọi lại `IConnectListener` (driver USB kẹt — đã từng quan sát thực tế), `pendingConnects[deviceId]` tồn tại vĩnh viễn và `Future` phía Dart **treo vô thời hạn**, không timeout, không lỗi. Đây là điểm nghiêm trọng nhất của mục này. *Gợi ý: gọi `scheduleConnectTimeout(deviceId)` ngay sau `posDevice.connect(...)` trong `tryConnectWithDelay`.*
- **[`requestUsbPermissionOnce()`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L915) có thể kẹt `deviceId` vĩnh viễn trong [`pendingPermissionRequests`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L92)** nếu người dùng thoát/kill app trong lúc dialog xin quyền hệ thống đang hiện (broadcast `ACTION_USB_PERMISSION` không bao giờ tới để [`remove()`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L935) khỏi set). Hệ quả: lần cắm lại/`connectUsb` sau đó sẽ không bao giờ hiện lại dialog xin quyền nữa cho tới khi kill hẳn tiến trình, đồng thời `Result` gốc của `connectUsb` cũng treo theo vì không có gì `complete()` nó. *Gợi ý: thêm timeout dọn set kèm `complete(false)` nếu không có phản hồi sau N giây.*
- **[`stableUsbId`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L598) không phân biệt được 2 máy in cùng vid/pid khi `serialNumber` rỗng/null** (khá phổ biến với máy in nhiệt giá rẻ) — fallback về `"USB:v{vid}_p{pid}"`. Nếu cắm 2 máy cùng model qua hub USB, cả hai collapse về cùng một key trong `connections`/`connectionTypes`/`usbDevicePaths`, máy kết nối sau ghi đè entry của máy trước — lệnh in có thể bị gửi nhầm máy hoặc rơi vào một `IDeviceConnection` mồ côi không bao giờ được `close()`. *Gợi ý: khi serial rỗng, ghép thêm `device.deviceName` (đường dẫn bus/port) vào key.*
- **Mọi nhánh thất bại kết nối (BT/USB/LAN) đều trả `result.success(false)` giống hệt nhau** — Dart không phân biệt được nguyên nhân là "timeout", "SDK từ chối", "hết 3 lần thử USB" hay "thiếu quyền" để hiển thị đúng thông báo hoặc quyết định có nên tự retry hay không. *Gợi ý: mang theo mã lỗi (enum) khi `PendingConnect.complete()`.*

---

## 6. ANDROID — Kết nối LAN: giải thích cơ chế chia sẻ socket

Đây là phần **phức tạp và quan trọng nhất** của toàn bộ tầng Android, vì nó giải quyết một ràng buộc vật lý khó chịu: **hầu hết máy in nhiệt LAN chỉ chấp nhận đúng 1 kết nối TCP tại một thời điểm** trên cổng in chuẩn 9100 — máy in sẽ "accept" (chấp nhận) nhiều socket ở tầng TCP, nhưng chỉ 1 trong số đó thực sự được in; các socket phụ bị đóng ngay khi có byte dữ liệu tới (client nhận lỗi "Connection reset"/"Broken pipe"). Đây là hành vi đã được kiểm chứng thực tế trên phần cứng, không phải giả định.

### 6.1 Vấn đề cần giải quyết

Một ứng dụng POS thường có nhiều màn hình/nhiều luồng cùng muốn in ra **cùng một máy in LAN** (ví dụ: màn hình order gọi in bill, đồng thời có tác vụ định kỳ in báo cáo). Nếu mỗi lượt in đều giữ socket mở vĩnh viễn, các lượt in khác sẽ liên tục bị từ chối. Nhưng nếu mỗi lượt in mở-đóng socket ngay lập tức, chi phí TCP handshake + độ trễ máy in nhận diện socket mới sẽ làm chậm đáng kể khi in liên tục nhiều tem/bill.

### 6.2 Giải pháp: "ghép nối" (registered) khác với "socket đang mở" (connected)

Plugin tách 2 khái niệm:
- **`registeredLanPrinters`**: set các IP **đã từng kết nối thành công** — coi như "máy in này đã biết, sẵn sàng dùng lại", dùng để trả `checkConnect() == true` dù socket vật lý hiện tại đã đóng.
- **Socket TCP đang mở thật**: trạng thái tạm thời, được mở lại tự động mỗi khi cần gửi dữ liệu và đóng lại khi rảnh.

`releaseLanSocketAfterPrint = true` (mặc định): sau khi in xong, **chủ động đóng socket** để các thiết bị/tác vụ khác trong app (hoặc ứng dụng khác trên mạng) có thể dùng máy in — nhưng IP vẫn nằm trong `registeredLanPrinters` nên lần in kế tiếp tự mở lại mà không cần Dart gọi `connect_lan` lại.

### 6.3 Mở lại socket khi cần: `ensureLanConnectedSync`

```
ensureLanConnectedSync(ip):
  - Nếu đang có pendingConnects cho cùng deviceId (người dùng đang chủ động connect())
      → nhường quyền, không tự mở song song (tránh 2 lần connect() đạp nhau)
  - Retry tối đa 4 lần, backoff: 0.4s → 0.8s → 1.6s → (3.2s không dùng, dừng ở lần 4)
```

Backoff tăng dần vì lý do rất cụ thể: nếu máy in đang bận với một socket khác (ví dụ vẫn chưa đóng hẳn sau lượt in trước của chính app này), việc kết nối lại ngay lập tức nhiều khả năng thất bại tiếp; chờ lâu hơn dần cho máy in đủ thời gian giải phóng.

### 6.4 Đếm số job đang dùng socket để biết khi nào an toàn đóng

`retainLanSocket(conn)` được gọi **trước khi** một job in bắt đầu, `releaseLanSocket(conn, closeWhenIdle)` gọi khi job đó kết thúc (thành công hoặc lỗi). Mỗi IP có một bộ đếm riêng (`AtomicInteger`) — chỉ khi bộ đếm về 0 (không còn job nào đang dùng socket này) thì mới thực sự có thể đóng. Điều này cho phép **nhiều job in cùng lúc tới cùng một IP** (ví dụ 2 lô ảnh của một lượt in tem dài) chia sẻ đúng một socket mà không tranh nhau đóng/mở.

Khi bộ đếm về 0 và cần đóng, plugin **không đóng ngay** mà hoãn **800ms** (`LAN_IDLE_CLOSE_DELAY_MS`) — nếu trong 800ms đó có job mới xuất hiện (ví dụ lô kế tiếp của cùng lượt in), socket được tái sử dụng luôn, tránh chi phí mở lại kết nối liên tục.

### 6.5 Watchdog 15 giây — lưới an toàn cuối cùng

`scheduleLanWatchdog` đặt một mốc dự phòng **15000ms**: nếu vì lý do nào đó (app crash, người dùng thoát màn hình giữa lượt in nhiều lô) tín hiệu "đây là lô cuối" (`is_last_batch`) không bao giờ tới, watchdog sẽ tự đóng socket sau 15s để không giữ máy in bị "chiếm dụng" vô thời hạn.

### 6.6 Vì sao cơ chế phức tạp này chỉ an toàn nhờ `sendAllSync` đồng bộ

Toàn bộ cơ chế đếm job/đóng-mở socket ở trên chỉ hoạt động đúng vì đường gửi dữ liệu đã chuyển từ `POSPrinter.printBitmap` (API bất đồng bộ của SDK, thả dữ liệu vào hàng đợi rồi trả về ngay — plugin không biết khi nào byte thực sự ra khỏi socket) sang `sendAllSync` tự viết (đồng bộ, biết chính xác khi nào việc gửi hoàn tất hoặc thất bại). Nếu vẫn dùng API bất đồng bộ, plugin sẽ đóng socket "quá sớm" (khi hàng đợi SDK còn dữ liệu chưa gửi hết), cắt cụt bản in.

### 6.7 Quét máy in LAN — 2 cơ chế tách biệt và vì sao

1. **`LanPrinterProbe.probe(ip, port)`** — **tuyệt đối không mở socket TCP tới máy in**. Chỉ đọc bảng ARP của hệ điều hành (`/proc/net/arp`, hoặc chạy lệnh `ip neigh` nếu file không đọc được) để tra MAC theo IP, rồi so khớp 6 ký tự hex đầu của MAC (mã OUI — Organizationally Unique Identifier, định danh hãng sản xuất) với bảng cứng các hãng máy in phổ biến (HPRT, Xprinter, Epson, TSC, Rongta, Zebra, Bixolon, Star, Citizen, Brother, SNBC, Godex, Sunmi). **Lý do không mở socket**: một số máy in nhiệt sẽ **tự động in một dòng giấy trắng hoặc feed giấy** khi có socket TCP mới kết nối tới cổng 9100 (hành vi "kích hoạt in khi có connection") — quét mạng bằng cách thử connect tới hàng chục IP sẽ vô tình làm hao giấy hàng loạt máy in trong mạng.
2. **`POSPrinter.searchNetDevice`** — dùng UDP broadcast thật của SDK để tìm máy in Xprinter/Gprinter, trả về `mac/ip/mask/gateway/dhcp`; đây là quét "chủ động và chính xác hơn" nhưng chỉ nhận diện được máy in cùng dòng SDK hỗ trợ, chờ cố định 1.5s.

### 6.8 Cấu hình lại IP máy in — 2 tuyến ưu tiên

`set_net_ip`: nếu có `mac` → ưu tiên **UDP** (`POSPrinter.udpNetConfig`, gửi tới cổng **9000**, khác cổng in 9100 — để máy in phân biệt được "đây là gói cấu hình, không phải dữ liệu in" và không in ra giấy trắng khi nhận gói cấu hình). Nếu không có `mac` (chỉ có `current_ip`), fallback sang **TCP ESC** (`NetworkConfigHelper.sendEscIpConfig`) — mở socket TCP thật tới `currentIp:9100`, gửi lệnh ESC/POS chuẩn Epson `GS ( E` (packet: `[1D 28 45][pL pH][02][49][dhcp][ip×4][mask×4][gw×4]`).

### 6.9 Phân tích cải thiện — ANR thật và các case in lỗi/im lặng chưa xử lý (2026-08-22)

- **ANR thật: [`check_printer_status`](android/src/main/kotlin/com/printer/printer_label/PrinterMethodCallHandler.kt#L219-L244) có thể chặn main thread tới ~23 giây.** Nhánh này gọi thẳng [`plugin.ensureLanConnectedSync(ip)`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L652-L707) ngay trong `onMethodCall`; `channel.setMethodCallHandler(methodCallHandler)` ([PrinterLabelPlugin.kt:132](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L132)) không dùng `BinaryMessenger.TaskQueue` nên callback này chạy trên **main thread**. Bản thân `ensureLanConnectedSync` có 4 lần thử, mỗi lần `latch.await(CONNECT_TIMEOUT_MS=5000ms)` ([dòng 692](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L692)) cộng backoff 0.4s→0.8s→1.6s giữa các lần — worst case ≈ 4×5000ms + 2800ms ≈ **22.8 giây chặn UI thật sự** khi máy in LAN đang offline. Đây đã được xác minh trực tiếp trong code (không phải suy đoán) và là điểm nghiêm trọng nhất trong toàn bộ phân tích bổ sung này vì gây ANR (crash-adjacent), không chỉ chậm. *Gợi ý: bọc nhánh `check_printer_status` trong `kotlin.concurrent.thread`, trả kết quả qua `Handler(Looper.getMainLooper()).post` — đúng pattern đã dùng ở nhánh `identify_lan_printer` ngay phía trên nó trong cùng file ([dòng 200-217](android/src/main/kotlin/com/printer/printer_label/PrinterMethodCallHandler.kt#L200-L217)).*
- **Resolve "in tất cả máy" (không truyền `device_id`) chạy tuần tự qua từng IP** — vòng lặp [`registeredLanPrinters.forEach { ensureLanConnectedSync(ip) }`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L444) (trong [`resolveConnectionsForPrint`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L374)) không song song. Nếu app có nhiều máy in LAN đã ghép nối (bill + bếp + tem) và một máy đang tạm offline, lệnh in tới **máy còn sống** cũng bị delay cộng dồn tới ~23s cho mỗi IP chết đứng trước nó trong vòng lặp, dù không liên quan gì tới máy đó. *Gợi ý: chạy `ensureLanConnectedSync` song song cho các IP (mỗi IP một thread), hoặc dùng timeout ngắn hơn hẳn cho nhánh reconnect-ngầm này so với nhánh connect chủ động của người dùng.*
- **[`set_net_ip`](android/src/main/kotlin/com/printer/printer_label/PrinterMethodCallHandler.kt#L322) có thể báo `success=true` giả** — biểu thức kết quả cuối cùng ở [dòng 366](android/src/main/kotlin/com/printer/printer_label/PrinterMethodCallHandler.kt#L366): `val success = escOk || mac.isNotEmpty()`. Nếu nhánh UDP thất bại rồi rơi xuống ESC mà ESC cũng không chạy được/thất bại, `success` vẫn `true` chỉ vì có `mac`. App tưởng đã đổi IP thành công nhưng máy in thực chất không nhận được gì, dẫn tới "mất tích" máy in sau khi đổi IP mà không có cảnh báo. *Gợi ý: `success` chỉ nên phản ánh kết quả thật của nhánh đã chạy, bỏ điều kiện `|| mac.isNotEmpty()`.*
- **[`LanPrinterProbe`](android/src/main/kotlin/com/printer/printer_label/LanPrinterProbe.kt#L134) dựa vào ARP có thể không đáng tin trên Android 10+** (đọc [`/proc/net/arp`](android/src/main/kotlin/com/printer/printer_label/LanPrinterProbe.kt#L8-L10)/[`ip neigh`](android/src/main/kotlin/com/printer/printer_label/LanPrinterProbe.kt#L25) — dễ bị hạn chế quyền hoặc cache đã hết hạn nếu lâu không giao tiếp với máy in). Nếu `mac` trả về rỗng dù máy in là Xprinter thật, `set_net_ip` sẽ rơi xuống nhánh ESC-TCP mà Xprinter không hiểu — kết hợp với điểm phía trên, ứng dụng báo `success=true` giả trong khi cấu hình IP không có tác dụng gì. *Gợi ý: nếu ESC-TCP thất bại và không có mac, thử thêm `POSPrinter.searchNetDevice` (UDP broadcast không cần mac) trước khi kết luận thất bại.*
- **[`retainLanSocket`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L718)/[`releaseLanSocket`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L732) có cửa sổ TOCTOU hẹp**: `resolveConnectionsForPrint` đọc `connections[key]` để lấy `conn`, nhưng việc tăng bộ đếm job (`retainLanSocket`) diễn ra sau đó ở một bước khác — giữa 2 bước này, Handler đóng-socket-rảnh 800ms hoặc [watchdog 15s](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L783) chạy trên main thread có thể vừa `close()` + `remove()` connection đó. Nếu trúng đúng cửa sổ này, job vẫn cầm một `conn` đã đóng dù mới kiểm tra "đang kết nối" ngay trước đó — hiếm gặp nhưng có thật, dễ trúng nhất khi lô cuối vừa nhả (trong 800ms chờ) mà lô mới tới ngay sau. *Gợi ý: gộp "check active + retain" vào cùng một khối đồng bộ, hoặc kiểm tra lại `conn.isConnect` ngay trong `retainLanSocket` để phát hiện conn đã chết và tự trigger reconnect thay vì âm thầm bỏ qua.*

---

## 7. ANDROID — Máy in tích hợp (built-in)

Có **2 kịch bản built-in hoàn toàn khác nhau** tùy hãng sản xuất thiết bị POS, vì các hãng không thống nhất một chuẩn giao tiếp chung với máy in tích hợp của họ.

### 7.1 Kịch bản A: built-in giao tiếp qua "Bluetooth nội bộ" (Sunmi, iMin, Pax, SmartPeak, Kozen)

Các hãng này thiết kế máy in tích hợp sao cho **hệ điều hành nhìn nó như một thiết bị Bluetooth Classic đã ghép nối sẵn** (dù thực chất là bus nội bộ, không có sóng Bluetooth thật ra ngoài). Nhờ vậy, plugin có thể **tái sử dụng toàn bộ pipeline Bluetooth đã viết** (mục 4) mà không cần viết code riêng — chỉ cần bước nhận diện & tự động kết nối (`autoConnectBuiltIn`, mục 4.5) và đánh dấu `builtInDeviceIds`.

`BuiltInPrinterManager.kt` cung cấp các hàm nhận diện:
- `isBuiltInPrinter()` — so `Build.MANUFACTURER`/`Build.MODEL` với danh sách hãng đã biết.
- `hasBuiltInPrinter(context)` — nếu không chắc từ tên model, fallback kiểm tra **package service của hãng có cài trên máy hay không** (`com.sunmi.printerservice`, `woyou.aidl.service`, `net.imin.printer`, `com.pax.sz.printerservice`, `com.urovo.printerservice`,...). Các package này phải được khai báo trong `<queries>` của `AndroidManifest.xml` — vì từ Android 11 (API 30), chính sách "Package Visibility" chặn ứng dụng truy vấn thông tin package khác trừ khi khai báo tường minh.
- `getBuiltInPrinterPaperSize(context)` — đọc system property `ro.sunmi.printer.paper` (giá trị 0 = 80mm, 1 = 58mm) hoặc suy luận theo nhóm model (máy desktop → 80mm, máy cầm tay → 58mm mặc định) — thông tin này giúp Dart tự động chọn đúng khổ giấy khi render ảnh, không cần người dùng cấu hình tay.

> **Bug đã vá — nhận diện built-in qua tên BT bị false-positive với máy ngoài generic**: `isConnectionToBuiltInPrinter(conn)` (`BluetoothPrinterManager.kt:964-999`) có 2 lớp nhận diện: (1) `builtInDeviceIds.contains(deviceId)` — nguồn chính, đánh dấu tường minh lúc connect; (2) dự phòng khớp theo tên BT với `BUILT_IN_NAME_KEYWORDS` (`"BluetoothPrinter"`, `"Inner Printer"`, `"Bluetooth Printer"`...). Danh sách này quá chung — nhiều máy in nhiệt Bluetooth ngoài giá rẻ dùng đúng tên mặc định đó làm tên quảng bá. Trước khi vá: nếu người dùng connect thêm một máy ngoài như vậy SAU KHI built-in đã tự động kết nối, hàm trả `true` cho **cả 2** connection; `resolveConnectionsForPrint`'s `connections.entries.firstOrNull { isConnectionToBuiltInPrinter(...) }` (mục 6.7, dòng 387-389) lấy theo thứ tự lặp của `ConcurrentHashMap` — **không đảm bảo built-in được ưu tiên** — nếu chọn trúng entry máy ngoài, lệnh in `device_id="BUILT_IN"` bị gửi sang máy ngoài: built-in thật im lặng không in, máy ngoài nhận thêm lệnh này cộng với lệnh gửi đúng địa chỉ của chính nó → **in ra 2 bản**. Đã tái hiện thực tế trên Sunmi V3 + một máy Bluetooth ngoài tên generic. Fix: một khi `builtInDeviceIds` đã có bất kỳ entry nào (trường hợp bình thường, vì `autoConnectBuiltIn()` luôn đánh dấu ngay khi tìm thấy built-in), lớp dự phòng theo tên bị **tắt hoàn toàn** cho mọi connection khác — chỉ dùng fallback tên khi chưa từng đánh dấu được built-in nào.

### 7.2 Kịch bản B: built-in Urovo — con đường hoàn toàn riêng, không qua `IDeviceConnection`

Urovo **không** expose máy in tích hợp như một thiết bị Bluetooth — thay vào đó có một class hệ thống riêng `android.device.PrinterManager` (một phần của firmware Urovo, không phải AOSP chuẩn). `UrovoPrinterManager.kt` dùng **Java Reflection** để gọi vào class này mà không cần nhúng file `.jar` riêng của Urovo vào project (giảm phụ thuộc build, tránh xung đột nếu Urovo đổi version SDK).

`isUrovoDevice()` kiểm tra `Build.MANUFACTURER`/`Build.MODEL` chứa `"urovo"` hoặc model chứa `"i9100"`. Khi xác nhận là Urovo, các lệnh in ESC (`print_text_esc`, `print_barcode_esc`, `print_qrcode_esc`, `print_image_esc`) và `print_label` (khi nhắm built-in) đi qua route Urovo hoàn toàn riêng biệt (`printLabelUrovo`, `printImageESCUrovo`,...) — dùng API `setupPage/drawBitmap/drawText/printPage/paperFeed` thay vì build lệnh TSPL/ESC thô. Mọi lỗi reflection bị `catch` và nuốt âm thầm (`e.printStackTrace()`) — một đánh đổi có chủ ý để một API Urovo bị thiếu/đổi tên ở firmware nào đó không làm crash toàn app, nhưng cũng đồng nghĩa lỗi in trên Urovo khó phát hiện qua log thông thường.

### 7.3 Route quyết định built-in đi nhánh nào

`PrinterMethodCallHandler` kiểm tra **cả 3 điều kiện** trước khi cho vào nhánh Urovo: `device_id == "BUILT_IN"` **và** `UrovoPrinterManager.isUrovoDevice()` **và** `!isBuiltInPrinterDisabled`. Nếu bất kỳ điều kiện nào sai (ví dụ built-in nhưng là Sunmi, không phải Urovo) → rơi về nhánh chung `PrinterThermal` (qua `IDeviceConnection` — kết nối Bluetooth nội bộ đã tự động thiết lập ở mục 7.1).

---

## 8. ANDROID — Cách lệnh in được build và gửi

Plugin hỗ trợ **cả 2 định dạng** tùy tham số `"type"` từ Dart.

### 8.1 TSPL (tem/label)

```kotlin
printer.sizeMm(w, h).gapMm(gw, gh).reference(0,0).direction(0)
[.home()]  // chỉ khi use_home=true — dò khe decal cho khổ nhiều tem/hàng
printer.cls().bitmap(0, 0, BMP_MODE_OVERWRITE, targetWidthDots, shifted, AlgorithmType.Threshold).print(1)
PrinterThermal.awaitLabelSent(conn)  // chờ xác nhận đã ghi ra socket trước khi recycle bitmap
```

`.home()` chỉ được gọi khi `use_home=true` — lệnh này khiến máy in **kéo giấy để cảm biến quang học dò đúng vị trí bắt đầu của tem kế tiếp** (quan trọng với khổ nhiều tem/hàng, nơi vị trí bắt đầu có thể lệch dần qua nhiều lượt in nếu không "reset" định kỳ). Toàn bộ khối lệnh được bọc trong `synchronized(PrinterThermal.lockFor(conn))` — giải thích ở mục 8.3.

`printText`/`printBarcode`/`printQRCode` build lệnh trực tiếp qua API cấp cao của `TSPLPrinter`, sau đó gọi `awaitFlush(conn)` — gửi 1 byte NUL (vô hại) bằng `sendSync` để làm "hàng rào": vì đây dùng API bất đồng bộ `sendData()` của SDK ở bên trong `TSPLPrinter`, cách duy nhất để biết lệnh trước đã ra khỏi hàng đợi nội bộ SDK là gửi thêm một byte đồng bộ ngay sau và chờ nó hoàn tất (khi byte hàng rào được gửi xong, mọi thứ trước nó trong FIFO queue chắc chắn đã được gửi).

### 8.2 ESC/POS (hóa đơn)

**Ảnh raster** (`printImageESC`, method `print_image_esc`) build gói lệnh theo đúng thứ tự:

1. `ESC @` (`0x1B 0x40`) — initialize, xóa mọi trạng thái/buffer cũ của máy in.
2. `ESC a 1` (`0x1B 0x61 0x01`) — căn giữa (align center) cho nội dung tiếp theo.
3. Dữ liệu raster `GS v 0` (từ `getEscPosRasterBytes()`).
4. 5× `LF` (`0x0A`) — feed 5 dòng, để phần cuối hóa đơn không bị kẹt dưới lưỡi cắt.
5. `GS V 66 1` (`0x1D 0x56 0x42 0x01`) — lệnh cắt giấy (cut paper).

**Vì sao `getEscPosRasterBytes()` chia ảnh thành các dải cao tối đa 128 dòng, thay vì gửi 1 lệnh `GS v 0` cho toàn bộ ảnh?** Vì chuẩn ESC/POS quy định lệnh `GS v 0` có tham số chiều cao `yL/yH` chỉ 2 byte (tối đa 65535 dòng lý thuyết), nhưng **firmware thực tế của nhiều máy in nhiệt giá rẻ có giới hạn nội bộ thấp hơn nhiều** — nếu gửi một lệnh raster cho một hóa đơn rất cao (nhiều mục hàng), firmware có thể "quên" đang ở raster mode giữa chừng và diễn giải phần byte ảnh còn lại như là **văn bản ASCII thô** → in ra một mớ ký tự rác thay vì phần còn lại của hóa đơn. Chia thành nhiều lệnh 128 dòng (band) giữ mỗi lệnh trong giới hạn an toàn của firmware.

Với mỗi pixel, chuyển sang độ xám bằng công thức luminance chuẩn `gray = 0.299R + 0.587G + 0.114B`, rồi so với ngưỡng cố định **`gray < 200`** để quyết định là điểm đen hay trắng. **Vì sao ngưỡng 200 mà không phải 128 (trung điểm thông thường)?** Vì đầu in nhiệt chỉ có 2 trạng thái (cháy/không cháy — không có "xám"), còn chữ do Flutter render ra luôn có viền anti-alias (các pixel biên chữ là xám nhạt, không đen tuyệt đối). Nếu dùng ngưỡng 128, phần lớn viền anti-alias của chữ nhỏ (vốn đã mảnh) sẽ bị coi là "trắng" → chữ in ra bị mất nét, mờ, khó đọc. Ngưỡng 200 (gần trắng mới bị coi là trắng) giữ lại nhiều pixel biên hơn, cho chữ đậm và rõ hơn khi in.

`quantity` (số bản in) được xử lý bằng cách **nối byte của các bản liên tiếp thành một khối duy nhất rồi gửi một lần** — không gọi lại toàn bộ hàm build+gửi N lần. Lý do: nếu gửi N lần riêng biệt (đặc biệt qua LAN), khoảng dừng giữa các lần gửi có thể đủ lâu để cơ chế tự nhả socket (mục 6) kích hoạt giữa 2 bản in, khiến bản in thứ 2 phải mở lại socket từ đầu — không chỉ chậm mà còn có rủi ro máy in đang xử lý dở bản 1 thì bị ngắt.

### 8.3 Cơ chế đồng bộ hóa gửi dữ liệu — trái tim của độ tin cậy in ấn Android

`PrinterThermal` companion object định nghĩa 4 công cụ, mỗi công cụ vá một loại bug cụ thể đã xảy ra trong thực tế:

1. **`sendLocks` + `lockFor(conn)`** — một `Object` lock riêng cho từng `IDeviceConnection`. Nếu 2 lệnh in tới **cùng một máy in** được gọi gần như đồng thời (ví dụ 2 lô của một lượt in dài), việc build+gửi phải chạy **tuần tự** (nếu không, byte của 2 lệnh có thể xen lẫn nhau trên cùng một stream, tạo ra dữ liệu vô nghĩa). Nhưng khóa theo từng connection riêng nghĩa là **2 máy in khác nhau vẫn in song song được**, không phải chờ nhau — **trừ khi cả hai đều là Bluetooth Classic**.

   > **Cập nhật**: `lockFor(conn)` có một trường hợp đặc biệt — nếu `conn.getConnectType() == DEVICE_TYPE_BLUETOOTH`, hàm trả về một khóa **toàn cục duy nhất** (`bluetoothGlobalLock`) thay vì khóa riêng theo connection. Lý do: máy in tích hợp (Sunmi/iMin/Pax, kết nối qua "Bluetooth nội bộ" — mục 7.1) và một máy Bluetooth ngoài là 2 `IDeviceConnection` khác nhau, nhưng **cùng đi qua một chip Bluetooth vật lý duy nhất** của thiết bị Android. Nếu 2 job in Bluetooth (built-in + máy ngoài) chạy đúng lúc — ví dụ `ESCPrintServiceImpl.printWidgetToDevices` gọi `Future.wait` in đồng thời built-in và một máy Bluetooth vừa kết nối — tranh chấp ở tầng radio có thể khiến dữ liệu của máy này bị đẩy nhầm sang máy kia: built-in im lặng không ra giấy, còn máy ngoài lại nhận đủ dữ liệu của cả 2 lần in nên **in ra 2 bản**. Khóa toàn cục ép mọi lần ghi Bluetooth (dù built-in hay ngoài) chạy tuần tự, loại bỏ khả năng ghi chồng lấn đó; LAN/USB không bị ảnh hưởng, vẫn giữ khóa riêng theo connection như cũ.
2. **`awaitFlush(conn)`** — gửi 1 byte NUL đồng bộ, dùng làm hàng rào cho hàng đợi API bất đồng bộ `sendData()`.
3. **`awaitLabelSent(conn, timeout=300ms)`** — khác `awaitFlush` ở điểm: nó đăng ký `IStatusCallback` thật qua `conn.setSendCallback()` để nhận thông báo "lệnh cụ thể này đã ghi ra socket", bám đúng thứ tự hàng đợi thay vì chỉ gửi thêm 1 byte và suy luận. SDK chỉ giữ **WeakReference** tới callback này — nếu code không tự giữ một tham chiếu mạnh (`strong reference`) tới nó trong lúc chờ, callback có thể bị Garbage Collector thu hồi giữa đường và không bao giờ được gọi, khiến `awaitLabelSent` treo tới hết timeout một cách vô lý. Đây là lý do code có đoạn giữ tham chiếu mạnh tường minh.
4. **`sendAllSync(conn, data, chunkSize)`** — thay cho việc gọi `sendData()` (API "gửi rồi quên") của SDK, hàm này lặp thủ công, gửi từng chunk bằng `sendSync()` (đồng bộ, trả về **số byte thực sự đã ghi**, có thể ít hơn kích thước chunk yêu cầu — đúng như ngữ nghĩa của lời gọi `write()` cấp thấp trên Unix/Android) và **tự tiến con trỏ đúng theo số byte thực nhận được**, không giả định "gửi yêu cầu N byte thì chắc chắn N byte đã đi". Chunk đầu tiên có retry riêng (8 lần, backoff 150ms×n) vì quan sát thực tế cho thấy gói đầu tiên dễ thất bại nhất khi driver USB "chưa kịp warm up" ngay sau khi mở stream.

Các bug thực tế mà 4 công cụ này khắc phục (được ghi lại trong comment mã nguồn, dùng làm bằng chứng cho việc "không nên đơn giản hóa lại code này"): in 5 tem chỉ ra 1-2 tem; tem in ra lại là nội dung của lần in trước (do bitmap bị tái sử dụng/recycle quá sớm); in 3 bill qua USB chỉ ra 1 bill; chữ giá tiền biến thành ký tự rác do bitmap Android bị `recycle()` trước khi SDK đọc xong dữ liệu pixel.

**Text/Barcode/QR "gốc"** (không phải ảnh): `printTextESC` dùng `POSPrinter.initializePrinter().printText(...).feedLine().cutHalfAndFeed(1)`. `printBarcodeESC` map type string (`UPCA/UPCE/EAN13/EAN8/CODE39/ITF/CODEBAR/CODE93`, mặc định CODE128) sang hằng số SDK. `printQRCodeESC` build byte thô theo chuẩn Epson `GS ( k` (set model 2, set size, set error-correction level L, lưu data, in). **Mở két** (`openDrawer`) gửi `ESC p 0 25 250` + `ESC p 1 25 250` — hai lệnh kích cả 2 chân (pin 2 và pin 5) của cổng RJ11/RJ12, vì các hãng két khác nhau đấu dây vào chân khác nhau; gửi cả hai đảm bảo tương thích rộng mà không cần biết trước loại két.

### 8.4 Phân tích cải thiện — mâu thuẫn timeout, OOM không được bắt, và lock không có trần thời gian (2026-08-22)

- **[`awaitLabelSent`](android/src/main/kotlin/com/printer/printer_label/PrinterThermal.kt#L107) timeout 300ms mâu thuẫn với chính comment trong code** — KDoc phía trên hàm mô tả lại quá trình tuning và kết luận đã "chốt 500ms", nhưng tham số mặc định thực tế trong chữ ký hàm là `timeoutMs: Long = 300L`, và call site duy nhất ([`PrinterLabelPlugin.kt:1166`](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L1166)) dùng đúng giá trị mặc định này, không override thành 500. Nếu 500ms mới là giá trị đã kiểm chứng đủ an toàn, thì 300ms là một **regression tiềm ẩn**: với mạng/BT chậm, callback flush hợp lệ có thể về sau mốc 300ms, bị coi là timeout giả → `shifted.recycle()` chạy trong khi SDK còn đọc dở pixel → tái phát đúng bug "chữ/tem biến thành ký tự rác" mà cơ chế `awaitLabelSent` sinh ra để chặn (mục 8.3, mục 9.1 điểm 5). *Cần đối chiếu lại xem 300 hay 500 mới là giá trị đúng ý đồ ban đầu và đồng bộ code với comment.*
- **[`printImageESC`](android/src/main/kotlin/com/printer/printer_label/PrinterThermal.kt#L197) chỉ bắt [`Exception`](android/src/main/kotlin/com/printer/printer_label/PrinterThermal.kt#L333), không bắt `OutOfMemoryError`** (là `Throwable`, không phải `Exception`) — nếu OOM xảy ra (dễ xảy ra hơn khi `quantity` lớn, xem mục 9.5) sau khi socket LAN đã được "retain" (tăng bộ đếm job) nhưng trước khi job báo kết quả, bộ đếm không bao giờ về 0 → **socket LAN bị giữ vĩnh viễn**, không watchdog 15s nào cứu được (watchdog chỉ chạy khi `releaseLanSocket` được gọi). *Gợi ý: đổi thành `catch (e: Throwable)` ở nhánh này, đảm bảo luôn giải phóng socket dù có lỗi gì xảy ra.*
- **[`sendAllSync`](android/src/main/kotlin/com/printer/printer_label/PrinterThermal.kt#L174) không có trần thời gian tổng thể** — vòng lặp gửi chunk chỉ đảm bảo tiến khi `sent > 0`, không phải vòng lặp vô hạn thật sự, nhưng không có ngưỡng thời gian tổng nào để bail sớm. Với mạng cực chậm (gửi liên tục vài byte một), hàm có thể chạy rất lâu trong khi vẫn giữ `synchronized(lockFor(conn))` — chặn mọi job khác cùng máy in, không có cách nào hủy từ tầng Dart. *Gợi ý: thêm ngưỡng thời gian tổng (10-15s) hoặc đếm số lần "gửi thiếu liên tiếp" để bail sớm bằng lỗi rõ ràng thay vì treo mờ không giới hạn.*

---

## 9. ANDROID — Xử lý ảnh, két tiền, code chết, hằng số

### 9.1 Xử lý hình ảnh — vì sao native "không làm gì nhiều"?

Native **không** tự render layout hóa đơn/tem — toàn bộ bố cục (text, logo, khoảng cách...) đã được Flutter widget render sẵn thành PNG/bitmap byte array trước khi gửi qua channel. Đây là quyết định thiết kế có chủ đích: Flutter có hệ sinh thái widget/font/layout mạnh hơn nhiều so với việc tự vẽ layout bằng Canvas API native, và giữ code native đơn giản, tập trung vào phần khó thay thế (giao tiếp phần cứng).

Việc native làm chỉ gồm:
1. **Decode** ảnh (`BitmapFactory.decodeByteArray`).
2. **Scale** về đúng kích thước đích tính bằng dots (chỉ với TSPL/`print_label`, theo quy đổi **8 dots/mm** — độ phân giải chuẩn của hầu hết máy in tem nhiệt).
3. **Dịch ảnh** sang trái `-8px`: bù một khoảng lệch cố định phát sinh từ cách widget Flutter render padding — nếu không dịch, tem in ra sẽ lệch nhẹ so với khung tem vật lý.
4. **Nhị phân hóa** — chuyển ảnh màu/grayscale thành đen/trắng tuyệt đối, vì đầu in nhiệt vật lý không có khái niệm "xám" (chỉ có cháy hoặc không cháy 1 điểm). TSPL dùng thuật toán `AlgorithmType.Threshold` có sẵn trong SDK; ESC dùng ngưỡng tự tính `gray < 200` (giải thích ở mục 8.2).
5. **Giải phóng bộ nhớ đúng lúc**: `bitmap.recycle()` chỉ được gọi **sau khi** `awaitLabelSent()` xác nhận SDK đã đọc xong dữ liệu pixel — gọi `recycle()` sớm hơn (ví dụ ngay sau khi gọi API build lệnh, trước khi SDK thực sự đọc bitmap ở một thread khác) là nguyên nhân trực tiếp của bug "chữ biến thành ký tự rác" đã nêu ở mục 8.3.
6. **Chia dải (banding)**: mỗi 128 dòng một lệnh raster riêng cho ảnh cao (đã giải thích ở mục 8.2).

### 9.2 Két tiền (Cash box) — vì sao cần một manager riêng ngoài lệnh `ESC p`?

`ESC p` (mục 8.2) chỉ mở được két **gắn vào cổng RJ11/RJ12 của chính máy in**. Nhưng nhiều thiết bị POS tích hợp (iMin, Sunmi, Urovo...) có **cổng két riêng ngay trên thân máy POS**, độc lập với máy in — két này phải mở qua API/service riêng của hãng, không liên quan gì tới giao tiếp máy in.

`CashBoxManager.kt` xử lý trường hợp này bằng Reflection (tránh nhúng SDK từng hãng vào project): `isSupportedDevice()` so khớp `Build.MANUFACTURER/MODEL/BRAND` với từ khóa hãng (`imin, swan, i24d, sunmi, urovo, pax, telpo, landicorp, smartpeak, kozen, centerm, hisense, wizarpos`). `openCashBox()` thử tuần tự 3 hãng, mỗi hãng có logic riêng vì API rất khác nhau:

- **iMin** — 4 tầng fallback theo thứ tự ưu tiên giảm dần về độ "chính thức": `ServiceManager.getService("iminservice")` (system service cấp thấp nhất) → `com.imin.library.SystemApi` → `com.imin.printerlib.IminPrintUtils` → cuối cùng gửi broadcast Intent `"net.imin.printer.openCashBox"` (cách "cùn" nhất nhưng ít phụ thuộc API cụ thể nhất).
- **Sunmi** — chỉ cần gửi broadcast (`"com.sunmi.drawer.OPEN"` hoặc `"woyou.aidl.service.openDrawer"`), không cần bind service.
- **Urovo** — reflection thẳng `android.device.PrinterManager.openDrawer()` (cùng class dùng cho in ấn Urovo ở mục 7.2).

**Điểm cần lưu ý khi bảo trì**: `open_drawer` chỉ đi vào `CashBoxManager` khi `device_id` rỗng hoặc `"BUILT_IN"` — nghĩa là plugin giả định "két gắn ở máy POS, không phải két gắn ở máy in rời". Nếu ứng dụng có kịch bản két gắn vào một máy in Bluetooth/LAN cụ thể (không phải built-in), code phải rơi xuống nhánh `PrinterThermal.openDrawer()` (gửi `ESC p` qua kết nối đó) — và có một rủi ro logic đã được ghi chú trong code: `CashBoxManager.openCashBox()` trả `true` ngay khi **gọi được API của hãng thành công**, không kiểm tra két có thực sự cắm vào cổng đó hay không — nên nếu định tuyến sai (đáng lẽ phải gửi `ESC p` tới máy in nhưng lại rơi vào `CashBoxManager`), ứng dụng sẽ nhận `success` giả trong khi két thật không hề mở.

### 9.3 Code chết (legacy) — không tham gia runtime nhưng vẫn nằm trong repo

`TsplActivity.kt` và `App.kt` — **toàn bộ nội dung bị comment**, là code mẫu/demo từ giai đoạn phát triển sớm hơn: `TsplActivity` minh họa cách gọi trực tiếp `TSPLPrinter` (in text/barcode/QR/box/bitmap) trong một `AppCompatActivity` độc lập; `App.kt` minh họa quản lý kết nối qua `Application` singleton kết hợp thư viện `LiveEventBus` (pub/sub event bus phổ biến trong Android). Cả hai **không compile vào build hiện tại** (bị comment hoàn toàn) — có thể coi là tài liệu tham khảo lịch sử, an toàn để xóa nếu muốn dọn dẹp repo, nhưng không ảnh hưởng gì nếu giữ lại.

### 9.4 Hằng số quan trọng

| Hằng số | Giá trị | Vị trí | Ý nghĩa |
|---|---|---|---|
| `CONNECT_TIMEOUT_MS` | 5000ms | `PrinterLabelPlugin.kt` | Timeout chờ kết nối (mọi loại) |
| `REQUEST_PERMISSIONS_CODE` | 1002 | `PrinterLabelPlugin.kt` | Request code xin quyền runtime |
| `ACTION_USB_PERMISSION` | `com.printer.printer_label.USB_PERMISSION` | `PrinterLabelPlugin.kt` | Action riêng broadcast xin quyền USB |
| `REQUEST_ENABLE_BT` | 1001 | `BluetoothPrinterManager.kt` | Request code bật Bluetooth qua Activity |
| `LAN_IDLE_CLOSE_DELAY_MS` | 800ms | `PrinterLabelPlugin.kt` | Hoãn đóng socket LAN rảnh, cho phép tái dùng |
| `LAN_WATCHDOG_CLOSE_DELAY_MS` | 15000ms | `PrinterLabelPlugin.kt` | Mốc dự phòng đóng socket khi lô cuối không tới |
| `lanRetryBaseDelayMs` / `lanMaxAttempts` | 400ms / 4 | `PrinterLabelPlugin.kt` | Backoff mở lại kết nối LAN |
| `FIRST_CHUNK_MAX_RETRY` / base delay | 8 / 150ms | `PrinterThermal.kt` | Retry gói đầu tiên khi gửi lỗi |
| Chunk size BT ngoài | 120 bytes | `PrinterThermal.kt` | Kích thước gói gửi Bluetooth (throttle theo tốc độ đầu in) |
| Chunk size USB/LAN | 4096 bytes | `PrinterThermal.kt` | Kích thước gói gửi USB/LAN/built-in |
| Ngưỡng nhị phân hóa ảnh ESC | `gray < 200` | `PrinterThermal.kt` | Ngưỡng đen/trắng raster, tối ưu cho chữ có anti-alias |
| Band height raster ESC | 128 dòng | `PrinterThermal.kt` | Giới hạn chiều cao mỗi lệnh `GS v 0` để tránh lỗi firmware |
| `awaitLabelSent` timeout | 300ms | `PrinterThermal.kt` | Chờ callback xác nhận gửi xong 1 tem TSPL |
| Port LAN mặc định | 9100 | nhiều nơi | Port ESC/POS raw chuẩn công nghiệp |
| Port UDP config | 9000 | `PrinterMethodCallHandler.kt` | Port UDP cấu hình IP Xprinter (khác 9100 để tránh in nhầm) |
| Dots per mm | 8 | `PrinterLabelPlugin.kt` | Quy đổi mm → dots khi scale bitmap TSPL |
| `shiftX` bù padding | -8 dots | `PrinterLabelPlugin.kt` | Bù lề trái do widget Dart |

> Ghi chú kỹ thuật nhỏ: `print_barcode_esc`/`print_qrcode_esc` bị định nghĩa **trùng lặp 2 lần** trong `when` block của `PrinterMethodCallHandler.kt` — nhánh sau là dead code (Kotlin `when` chỉ khớp branch đầu tiên khớp điều kiện), không ảnh hưởng hành vi hiện tại nhưng nên dọn khi refactor để tránh nhầm lẫn cho người đọc sau.

### 9.5 Phân tích cải thiện — hằng số hard-code và chi phí bộ nhớ/CPU chưa tối ưu (2026-08-22)

- **`8 dots/mm` ([dòng 1107](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L1107)) và `shiftX = -8` ([dòng 1119](android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt#L1119)) là hằng số cố định, không thích ứng máy in tem 300dpi** — quy đổi mm→dots và bù lệch trái khi scale bitmap TSPL. Máy in tem 300dpi (~11.8 dots/mm) khá phổ biến ở phân khúc mã vạch/QR mật độ cao. Với hằng số cố định 8, ảnh tem sẽ bị scale sai hoàn toàn theo đúng model máy (tem in ra chỉ ≈68% kích thước đúng nếu máy thực là 300dpi) và độ bù lệch `shiftX` cũng sai theo tỷ lệ đó — không phải lệch nhẹ mà là sai khổ tem hệ thống trên toàn bộ dòng máy 300dpi. *Gợi ý: cho phép truyền `dotsPerMm` từ Dart theo cấu hình máy in cụ thể, thay vì hardcode chung cho mọi máy TSPL.*
- **[`getEscPosRasterBytes`](android/src/main/kotlin/com/printer/printer_label/PrinterThermal.kt#L341) ghi từng byte một vào `ByteArrayOutputStream`** ([dòng 408](android/src/main/kotlin/com/printer/printer_label/PrinterThermal.kt#L408): `stream.write(byteVal)`) — với hóa đơn cao hàng nghìn dòng (ví dụ 3000 dòng × ~100 bytes/dòng ≈ 300.000 lần gọi `write(int)`, vốn là method `synchronized` trong JDK), không sai chức năng nhưng tốn CPU/thời gian dựng lệnh trên thiết bị Android yếu, kéo dài độ trễ trước khi bắt đầu gửi dữ liệu thật. *Gợi ý: gom mỗi hàng vào một `ByteArray` cục bộ rồi gọi `stream.write(rowBytes, 0, len)` một lần thay vì per-byte.*
- **`quantity` lớn nối toàn bộ các bản in vào một buffer RAM duy nhất trước khi gửi** (route ESC, [dòng 275-280](android/src/main/kotlin/com/printer/printer_label/PrinterThermal.kt#L275-L280)) — mục 8.2 giải thích lý do gộp (tránh khoảng dừng kích hoạt tự nhả socket LAN giữa 2 bản), nhưng cách hiện thực là `repeat(copies) { buf.write(oneCopy) }` lặp trước khi gửi bất kỳ byte nào. Với ảnh hóa đơn lớn + `quantity` cao (ví dụ 50 bản), buffer có thể lên tới hàng chục MB trên thiết bị RAM thấp — cộng dồn rủi ro với việc `OutOfMemoryError` không được bắt ở mục 8.4. *Gợi ý: vẫn giữ khóa `synchronized(lockFor(conn))` và socket LAN xuyên suốt vòng lặp, nhưng gửi từng bản bằng `sendAllSync(oneCopy)` liên tiếp thay vì nối trước toàn bộ — giữ được lợi ích "không nhả socket giữa các bản" mà không cần nhân bản bộ nhớ theo `quantity`.*

---

## 10. iOS — Nền tảng và lý do chọn kiến trúc này

### 10.1 Vì sao iOS tự viết tầng vận chuyển thay vì dùng SDK như Android?

Không có tài liệu nào giải thích trực tiếp lý do lịch sử, nhưng quan sát từ code cho thấy: SDK máy in cho iOS (`PrinterSDK`, cung cấp `PTCommandTSPL`/`PTCommandESC`/`PTDispatcher`/`PTPrinter`) **chỉ cung cấp phần build lệnh in cấp cao (text/barcode/QR/TSPL)**, không cung cấp một abstraction kết nối đa năng như `IDeviceConnection` bên Android. Do đó nhóm phát triển buộc phải tự viết `BLEManager` (CoreBluetooth) và `LANPrinterConnection`/`LANPrinterManager` (Network.framework) để lấp khoảng trống, đồng thời tự build byte lệnh ESC/POS raster ảnh thủ công trong `ESCPosPrinter.swift` (SDK không hỗ trợ raster ảnh tùy biến theo nhu cầu chia dải 128 dòng của plugin).

### 10.2 Các file & vai trò

| File | Class/Struct | Vai trò |
|---|---|---|
| `PrinterLabelPlugin.swift` | `PrinterLabelPlugin` (FlutterPlugin) | Entry point duy nhất từ Flutter: nhận MethodChannel/EventChannel, parse tham số, dựng lệnh in bằng SDK `PTCommandTSPL`/`PTCommandESC`, định tuyến (`sendToPrinter`) tới `BLEManager` hoặc `LANPrinterManager`. |
| `PrinterLabelPlugin.swift` | `BLEScanStreamHandler` | Cầu nối EventChannel `bt_scan` ↔ `BLEManager.scanEventSink`. |
| `PrinterLabelPlugin.swift` | `EmptyStreamHandler` | Stub cho EventChannel `usb_events` (iOS không có USB printer). |
| `BLEManager.swift` | `BLEManager` (singleton `.shared`) | Toàn quyền quản lý CoreBluetooth: scan, connect, discover service/characteristic, ghi dữ liệu có backpressure, timeout, đa kết nối đồng thời. |
| `ESCPosPrinter.swift` | `ESCPosPrinter` | Build lệnh ESC/POS cho **in ảnh raster** (`GS v 0`) và **mở ngăn kéo tiền**. Có `weak var plugin` gọi ngược lại `sendToPrinter`. |
| `ImageUtils.swift` | `UIImage.binarized(threshold:)` | Nhị phân hóa ảnh cho luồng TSPL (label). |
| `LANPrinterConnection.swift` | `LANPrinterConnection` | Quản lý **một** kết nối TCP (`NWConnection`) tới **một** IP: hàng đợi ghi tuần tự, retry backoff, xác nhận máy in đã nhận, tự nhả socket khi rảnh. |
| `LANPrinterManager.swift` | `LANPrinterManager` (singleton) | Bản đồ `IP -> LANPrinterConnection`, theo dõi "đã ghép nối" vs "socket đang mở". |
| `POSNetConfigHelper.swift` | `POSNetConfigHelper` | Cấu hình IP tĩnh cho máy in LAN qua UDP broadcast; quét máy in LAN bằng UDP. |

### 10.3 Quan hệ gọi lẫn nhau

```
Flutter (Dart)
   │  MethodChannel "flutter_printer_label"
   │  EventChannel  "flutter_printer_label/bt_scan"
   │  EventChannel  "flutter_printer_label/usb_events"
   ▼
PrinterLabelPlugin  (sở hữu: escPrinter, bleScanHandler, printer: PTPrinter)
   │
   ├─ escPrinter: ESCPosPrinter  --(weak plugin)--> gọi lại plugin.sendToPrinter(...)
   ├─ BLEManager.shared        (singleton, khởi tạo sớm trong init())
   └─ LANPrinterManager.shared (singleton)
          └─ sở hữu nhiều LANPrinterConnection (theo IP)

PrinterLabelPlugin.sendToPrinter(data, deviceId, connectionType)
   -> quyết định BLE hay LAN dựa vào connectionType/deviceId (tiền tố "BT:"/"LAN:" hoặc UUID)
   -> BLEManager.shared.writeData / writeDataToFirstConnected / writeDataToAllConnected
   -> LANPrinterManager.shared.send(data:to:)
```

Điểm thiết kế quan trọng: `ESCPosPrinter` **không tự gửi dữ liệu ra bất kỳ đâu** — nó chỉ build một `Data` rồi gọi `plugin?.sendToPrinter(...)` (tham chiếu `weak` để tránh retain cycle, vì `plugin` sở hữu `escPrinter` — nếu `escPrinter` giữ `plugin` bằng strong reference sẽ tạo vòng tham chiếu không bao giờ được giải phóng). Điều này đảm bảo **`PrinterLabelPlugin` luôn là điểm cuối duy nhất định tuyến ra BLE/LAN** — dù lệnh in xuất phát từ đường ESC ảnh hay đường TSPL/ESC "gốc", chúng đều phải đi qua đúng một cổng định tuyến, tránh 2 nơi khác nhau tự quyết định BLE hay LAN theo 2 logic khác nhau (dễ gây bug không đồng nhất).

---

## 11. iOS — Kết nối Bluetooth Low Energy: giải thích từng bước

### 11.1 Vì sao BLE (không phải Bluetooth Classic) trên iOS?

Apple **không cho phép ứng dụng bên thứ 3 truy cập Bluetooth Classic/SPP** trên iOS (trừ một số ngoại lệ qua MFi program dành cho phụ kiện được Apple chứng nhận) — CoreBluetooth chỉ expose BLE (Bluetooth Low Energy, dùng mô hình GATT với service/characteristic) cho ứng dụng thông thường. Đây là lý do máy in được chọn tương thích với plugin trên iOS phải hỗ trợ BLE, khác hẳn Android (SPP).

### 11.2 Vì sao `CBCentralManager` chạy trên queue riêng, không phải main queue?

`BLEManager` khởi tạo `CBCentralManager` với delegate trên `bleQueue` (một `DispatchQueue` riêng do plugin tạo), **không dùng main queue mặc định**. Lý do: nếu dùng main queue, mọi callback CoreBluetooth (bao gồm `peripheralIsReady(toSendWriteWithoutResponse:)` — tín hiệu quan trọng báo "có thể ghi gói tiếp theo") sẽ phải **chờ tới lượt trong hàng đợi UI của main thread**. Khi Flutter đang render/animate UI (main thread bận), tín hiệu backpressure BLE bị delay theo — kết quả là việc gửi dữ liệu in bị giật cục, không đều, ảnh hưởng tốc độ và có thể gây lỗi timing với đầu in.

`CBCentralManager` này được tạo **sớm hơn nhiều** so với lúc người dùng thao tác — xem mục 11.8 (bản ghi 2026-08-27) về việc điều này từng khiến hệ thống tự hiện popup xin bật Bluetooth ngay lúc app khởi động.

### 11.3 Quy trình scan

`startScan()` chỉ chạy khi `centralManager.state == .poweredOn` — CoreBluetooth **cấm gọi `scanForPeripherals` khi Bluetooth chưa sẵn sàng** (sẽ ném lỗi hoặc không có tác dụng). Nếu Bluetooth đang tắt/đang khởi động, `centralManagerDidUpdateState` sẽ tự động resume scan ngay khi state chuyển `.poweredOn`, miễn là cờ `isScanning` vẫn `true` — cách này tránh phải yêu cầu Dart tự retry gọi scan.

`didDiscover` (callback mỗi khi thấy một peripheral quảng bá) áp 2 tầng lọc:
- **RSSI tối thiểu -70**: loại các thiết bị quá xa/tín hiệu yếu — quét được một thiết bị không có nghĩa là kết nối ổn định được với nó; lọc sớm giảm nhiễu danh sách hiển thị cho người dùng.
- **Lọc theo tên**: giống Android, dùng từ khóa dài + tiền tố ngắn để nhận diện máy in (loại bỏ tai nghe, đồng hồ, các thiết bị BLE khác trong khu vực).

Một chi tiết dễ bị bỏ sót khi bảo trì: `onCancel` của `BLEScanStreamHandler` (được gọi khi Dart hủy lắng nghe `EventChannel`) **không dừng scan thật** — scan CoreBluetooth vẫn tiếp tục chạy nền. Đây có thể là chủ đích (để không phải bật lại scan nếu Dart lắng nghe lại ngay sau đó) hoặc là một thiếu sót cần bổ sung `stopScan()` tùy theo yêu cầu tiết kiệm pin của ứng dụng cụ thể — cần lưu ý khi debug hiện tượng "app tốn pin bất thường khi màn hình scan đã đóng".

### 11.4 Kết nối — 4 tầng fallback tìm peripheral

Vì CoreBluetooth không cho ứng dụng lưu trực tiếp một `CBPeripheral` qua các lần chạy app (phải tra lại qua identifier), `connect(identifier:)` thử theo thứ tự:
1. Tìm trong cache `discoveredPeripherals` (nếu vừa scan xong, còn trong bộ nhớ phiên hiện tại).
2. `centralManager.retrievePeripherals(withIdentifiers:)` — tra theo UUID đã lưu từ trước **mà không cần scan lại** (nhanh hơn scan, hoạt động nếu hệ điều hành vẫn còn "nhớ" thiết bị này).
3. `centralManager.retrieveConnectedPeripherals(withServices:[])` — bắt các thiết bị **đã được kết nối ở tầng hệ thống** (ví dụ do một ứng dụng khác hoặc Settings đã kết nối trước).
4. Nếu cả 3 đều thất bại → trả `false`.

Khi tìm được peripheral: nếu đã `.connected` với characteristic ghi được sẵn → trả `true` ngay (tránh connect lại không cần thiết); nếu đang `.connecting` (một lời gọi connect khác đang xử lý) → trả `false` ngay (không xếp hàng chờ như Android — đây là khác biệt hành vi cần lưu ý); nếu chưa kết nối → **dọn sạch state cũ** (`writableCharacteristics`, `pendingServiceCount` của identifier này) trước khi gọi `connect()` — việc dọn này quan trọng vì nếu máy in bị mất nguồn đột ngột ở lần kết nối trước, characteristic cũ có thể vẫn còn trong map nhưng đã "chết" (không còn hợp lệ), gây lỗi khó hiểu nếu vô tình dùng lại.

**Timeout kết nối 5.0s**: đặt qua `DispatchWorkItem`, nếu tới hạn mà vẫn chưa có kết quả thì tự `cancelPeripheralConnection` và trả `false` — tránh treo UI khi máy in đã tắt nguồn (CoreBluetooth có thể không bao giờ gọi lại `didFailToConnect` trong một số trường hợp thiết bị mất tín hiệu đột ngột).

Sau khi `didConnect` (tầng centralManager xác nhận kết nối GATT thành công), plugin phải tự làm tiếp 2 bước bắt buộc của mô hình GATT: `discoverServices(nil)` → với mỗi service tìm được, `discoverCharacteristics(nil, for:)` → chọn ra characteristic có khả năng ghi (`.write`/`.writeWithoutResponse`). Chỉ khi **tất cả** service đã được xử lý xong (đếm bằng `pendingServiceCount`) mới coi kết nối là hoàn tất và trả kết quả cho Dart — vì một peripheral có thể quảng bá nhiều service, và characteristic dùng để in có thể không nằm trong service đầu tiên được duyệt.

### 11.5 Vì sao có danh sách máy in "yếu nguồn" bắt buộc dùng write-with-response?

`needsSlowWrite(_:)` kiểm tra tên máy in chứa `"ri-5809"`/`"ri5809"` — một số máy in mini cầm tay dùng pin nhỏ **sụt áp và tự tắt nguồn giữa lúc in** nếu bị "dội" dữ liệu quá nhanh liên tục (ghi `withoutResponse` không có cơ chế chờ, có thể đẩy dữ liệu nhanh hơn khả năng cấp điện ổn định của mạch in). Với các máy này, buộc dùng `.withResponse` (chờ xác nhận `didWriteValueFor` sau mỗi lần ghi) — chậm hơn nhưng mỗi lần ghi có một khoảng nghỉ tự nhiên (thời gian round-trip xác nhận), giảm áp lực dòng điện đột ngột. Đây là một danh sách "vá cứng" theo kinh nghiệm thực tế với một model cụ thể, không phải suy ra từ đặc tả BLE.

### 11.6 Gửi dữ liệu — 2 chiến lược write và backpressure thật

`writeData` lấy đồng thời `(peripheral, characteristic, writeType)` dưới một lock (`stateLock`) để tránh đọc dữ liệu không nhất quán khi nhiều máy in được ghi song song từ nhiều thread. `chunkSize` không phải hằng số cố định (khác GATT MTU mặc định 20 byte "truyền thống") — mà lấy từ `peripheral.maximumWriteValueLength(for: writeType)`, giá trị **MTU thực tế đã được negotiate** giữa iOS và peripheral cụ thể đó (có thể lớn hơn nhiều 20 byte với thiết bị BLE hiện đại).

- **`.withResponse`**: mỗi lần `writeValue` xong, chờ callback `didWriteValueFor` (tối đa 5s) rồi mới gửi chunk kế — chính bản thân việc chờ ack **đã là backpressure tự nhiên**, không cần thêm logic pause nhân tạo.
- **`.withoutResponse`**: không có ack, nên cần 2 lớp bảo vệ: (1) `waitUntilReadyToWrite` — chờ `peripheral.canSendWriteWithoutResponse == true` hoặc tín hiệu từ `readySignal` (một semaphore được "signal" trong callback `peripheralIsReady(toSendWriteWithoutResponse:)` — đây là cách CoreBluetooth báo "buffer nội bộ của iOS đã trống, có thể ghi tiếp", timeout 5s); (2) **pause nhân tạo theo byte** (~86µs/byte, cùng công thức với Android) — vì "buffer của iOS đã trống" không đồng nghĩa "đầu in vật lý đã theo kịp việc kéo giấy" — buffer BLE của iOS có thể trống rất nhanh trong khi đầu in vẫn còn đang xử lý dữ liệu vừa nhận.

Mỗi peripheral có **queue ghi riêng theo identifier** — đảm bảo dữ liệu của cùng một máy không bị chèn lộn thứ tự, nhưng nhiều máy khác nhau ghi song song, không phải chờ nhau (giống triết lý `lockFor(conn)` bên Android, chỉ khác công cụ: GCD queue thay vì `synchronized` lock).

### 11.7 Mất kết nối & vì sao không có auto-reconnect

`didDisconnectPeripheral` dọn toàn bộ state liên quan đến peripheral đó (`connectedPeripherals`, `writableCharacteristics`, `pendingServiceCount`, `connectTimeouts`) và **đánh thức mọi semaphore đang chờ** (`readySignal`/`ackSignal` gọi `.signal()`) — bước đánh thức này quan trọng: nếu một thread đang `wait()` một semaphore chờ tín hiệu ghi tiếp mà máy in rớt kết nối giữa lúc đó, không đánh thức sẽ khiến thread đó bị treo tới hết timeout (5s) một cách vô ích thay vì nhận biết ngay "đã mất kết nối, dừng gửi".

iOS **không tự động kết nối lại** sau khi mất kết nối — khác hẳn cơ chế LAN tự mở lại socket (mục 12). Việc kết nối lại phải do Dart chủ động gọi lại `connect_bt`. Đây là sự khác biệt triết lý có chủ đích: với BLE, "mất kết nối" thường đồng nghĩa máy in đã tắt nguồn hoặc ra khỏi tầm phủ sóng — một retry tự động vô điều kiện có thể chạy vô ích trong thời gian dài; để Dart (biết ngữ cảnh UI, ví dụ người dùng đang xem màn hình in) quyết định khi nào retry hợp lý hơn.

### 11.8 Phân tích cải thiện — race giữa timeout và GATT callback, semaphore không được serialize (2026-08-22)

- **Race giữa timeout kết nối 5.0s và `didConnect`/`didDiscoverCharacteristicsFor`** — [`scheduleConnectTimeout`](ios/Classes/BLEManager.swift#L240) xoá `pendingConnectResults` và gọi `result(false)`, nhưng [`didConnect`](ios/Classes/BLEManager.swift#L551) vẫn set `connectedPeripherals[identifier] = peripheral` và tiếp tục `discoverServices` **mà không kiểm tra** liệu pending đã bị timeout tiêu thụ hay chưa; [`didDiscoverCharacteristicsFor`](ios/Classes/BLEManager.swift#L612) cũng gán `writableCharacteristics[identifier]` vô điều kiện. Nếu GATT kết nối hoàn tất đúng lúc timeout cũng fire, Dart có thể đã nhận `false` trong khi native state ngay sau đó trở thành "đã kết nối thật + có characteristic ghi được" — lệch state này không tự phát hiện được cho tới lần gọi `connect`/`disconnect` kế tiếp. *Gợi ý: trong closure timeout, sau khi lấy `pending`, chủ động dọn luôn `connectedPeripherals`/`writableCharacteristics` cho identifier đó thay vì chỉ dựa vào `didDisconnectPeripheral` sẽ tới sau.*
- **[`resetSignals(for:)`](ios/Classes/BLEManager.swift#L97) trong [`writeData`](ios/Classes/BLEManager.swift#L293) chạy TRÊN THREAD GỌI, trước khi enqueue vào [`writeQueue(for: identifier).async`](ios/Classes/BLEManager.swift#L368)** ([dòng 363](ios/Classes/BLEManager.swift#L363) gọi trước dòng 368) — tức là không được serialize cùng hàng đợi ghi riêng của peripheral. Nếu Dart gọi in 2 lần liên tiếp cho **cùng một identifier** trước khi lần đầu hoàn tất (dễ xảy ra hơn vì mục 13.8 khiến Dart tưởng lệnh trước đã xong và gọi tiếp ngay), lần gọi thứ 2 tạo lại semaphore trong dictionary trong khi lần ghi thứ nhất vẫn đang `wait()` trên instance cũ đã capture cục bộ — khi `didWriteValueFor` fire, nó signal instance MỚI chứ không phải instance đang chờ → lần ghi thứ nhất treo tới hết timeout 5s rồi báo `WRITE_TIMEOUT` giả dù máy in đã ack thật. *Gợi ý: dời `resetSignals(for: identifier)` vào bên trong `writeQueue(for: identifier).async {}`, ngay trước vòng lặp ghi.*
- **In BLE dài có thể tốn hàng chục giây pause thuần (~86µs/byte, [dòng 413-415](ios/Classes/BLEManager.swift#L413-L415)), không có `beginBackgroundTask`** — hóa đơn 80mm dài ~3000 dòng raster có thể tốn ~18.6 giây chỉ riêng thời gian `Thread.sleep`. Nếu người dùng khóa màn hình/chuyển app giữa lúc đó, GCD queue bị suspend hoàn toàn; khi resume, các deadline `wait(timeout:)` đã trôi qua trong lúc suspended nên trả `.timedOut` ngay lập tức → báo `WRITE_TIMEOUT` giả, cắt cụt bản in giữa chừng. *Gợi ý: bọc vòng ghi bằng `UIApplication.shared.beginBackgroundTask` để có thêm ~30s hoàn tất khi app vừa xuống nền.*
- Đã kiểm tra và xác nhận **an toàn** (không phải bug): mọi lời gọi `result(...)`/`scanEventSink(...)` từ `bleQueue` đều được bọc qua `onMain {}` trước khi chạm Flutter; `DispatchSemaphore.signal()` gọi trước một `wait()` không gây crash và mọi `wait()` đều có timeout hữu hạn nên không có deadlock vô hạn khi disconnect đúng lúc semaphore đang chờ.
- **Popup xin bật Bluetooth tự động ngay lúc mở app, dù chưa thao tác gì liên quan tới in ấn (2026-08-27)** — [`PrinterLabelPlugin.init()`](ios/Classes/PrinterLabelPlugin.swift#L59) chạm `_ = BLEManager.shared` để "khởi tạo `BLEManager` sớm cho `CBCentralManager` sẵn sàng" ngay khi Flutter đăng ký plugin (tức là ngay cold start, trước cả khi code Dart/`main()` chạy). Lần đầu chạm `.shared` chạy `init()` của `BLEManager`, tạo `CBCentralManager(delegate:queue:options: [CBCentralManagerOptionShowPowerAlertKey: true])` ([`BLEManager.swift:152`](ios/Classes/BLEManager.swift#L152)). Cờ `CBCentralManagerOptionShowPowerAlertKey: true` là API chính thức của Apple để **chủ động** yêu cầu hệ thống hiện popup cảnh báo nếu Bluetooth đang tắt — kích hoạt ngay tại thời điểm tạo `CBCentralManager`, không phụ thuộc việc có `scan`/`connect` hay không. Hệ quả: mọi lần mở app (cold start) trên máy đang tắt Bluetooth đều bị hỏi bật Bluetooth, kể cả khi người dùng chỉ định dùng máy in LAN/USB hoặc chưa vào màn hình in nào cả. Chỉ xảy ra trên iOS — Android không có cơ chế tương đương (không có API nào ép hệ thống hiện dialog bật Bluetooth ngay lúc khởi tạo). *Fix: đổi `CBCentralManagerOptionShowPowerAlertKey` từ `true` → `false` tại [`BLEManager.swift:152`](ios/Classes/BLEManager.swift#L152) — `CBCentralManager` vẫn được tạo sớm như thiết kế ban đầu (để sẵn sàng theo dõi trạng thái Bluetooth qua `centralManagerDidUpdateState`), chỉ không còn ép hệ thống hiện popup ngay lúc khởi tạo; popup vẫn xuất hiện đúng lúc khi người dùng chủ động `scan_bt`/`connect_bt` và hệ thống cần hỏi quyền/trạng thái Bluetooth theo đúng luồng tương tác đó.*

---

## 12. iOS — Kết nối LAN: giải thích cơ chế xác nhận & retry

### 12.1 Nền tảng: `Network.framework`, không phải `Socket`/`CFStream` cũ

`LANPrinterConnection` dùng `NWConnection` (API hiện đại từ iOS 12) thay vì BSD socket thô hoặc `Stream` cũ — `Network.framework` cung cấp `stateUpdateHandler` (callback trạng thái kết nối rõ ràng: `.ready`, `.failed`, `.cancelled`...) giúp code xử lý lỗi mạch lạc hơn so với việc tự poll trạng thái socket.

### 12.2 Vì sao completion phải "xếp hàng" khi đang connecting?

Nếu `connect(completion:)` được gọi lần 2 trong khi lần 1 vẫn đang `.connecting` (ví dụ 2 lệnh in gọi gần như đồng thời tới cùng IP), code **không tạo kết nối thứ 2** mà đẩy completion mới vào `connectCompletions` — khi kết quả (thành công/thất bại) của lần connect đang chạy tới, **tất cả** completion đang xếp hàng được gọi cùng lúc. Nếu không làm vậy, completion của lệnh gọi thứ 2 sẽ bị "ghi đè" bởi lệnh gọi thứ 1 (tùy cách implement) và không bao giờ được gọi — y hệt lý do `pendingConnects` tồn tại bên Android.

### 12.3 `isFirstJobOnSocket` — vì sao cần chèn `ESC @` cho job đầu tiên trên socket mới?

Khi một socket vừa `.ready` (mới mở), plugin đặt cờ `isFirstJobOnSocket = true`. Lệnh in đầu tiên gửi trên socket này sẽ tự động được chèn thêm `ESC @` (`0x1B 0x40` — initialize) ở đầu dữ liệu. Lý do: nếu lần in trước đó bị ngắt giữa đường (mất mạng, lỗi ứng dụng) và máy in **đang chờ đủ số byte của một lệnh `GS v 0` bị cắt ngang**, việc mở socket mới và gửi lệnh in tiếp theo (không có `ESC @`) có thể bị máy in hiểu nhầm là "phần còn thiếu" của lệnh cũ, gây in sai/lệch hoàn toàn. `ESC @` buộc máy in quay về trạng thái sạch trước khi xử lý lệnh mới.

### 12.4 Vì sao "gửi thành công ở tầng TCP" chưa đủ — cần thêm 0.4s xác nhận?

Đây là phần tinh vi nhất của tầng LAN iOS. Khi `connection.send(content:completion: .contentProcessed(...))` gọi callback **không có lỗi**, điều đó chỉ có nghĩa **dữ liệu đã được đẩy xuống tầng TCP của iOS** — không có nghĩa máy in đã thực sự nhận và xử lý nó. Lý do cụ thể (đã giải thích ở mục 6 phần Android, áp dụng y hệt ở đây): máy in nhiệt LAN có thể **accept** một socket phụ ở tầng TCP (bắt tay 3 bước thành công) nhưng sau đó **đóng nó ngay khi có byte dữ liệu thực tới** — vì máy in chỉ thực sự phục vụ 1 socket "chính". Nếu coi `contentProcessed` không lỗi là "thành công", ứng dụng sẽ báo in thành công giả trong những trường hợp máy in đang bận với thiết bị khác.

Giải pháp: sau khi gửi không lỗi, đặt `pendingConfirmJob` và **chờ thêm 0.4s** (`acceptConfirmDelay`) — nếu sau khoảng đó socket **vẫn còn `.connected`** (máy in không bất ngờ đóng nó), mới coi là thành công thật và tiếp tục job kế trong hàng đợi. Đây là một "phép đo gián tiếp" hợp lý: máy in đóng socket giả-thành-công thường xảy ra gần như ngay lập tức sau khi nhận byte, nên một khoảng chờ ngắn đủ để phân biệt 2 trường hợp.

### 12.5 Retry với backoff — khác biệt so với Android

`scheduleRetryOrFail`: tối đa **4 lần** thử, backoff `0.4s × 2^(n-1)` (0.4s → 0.8s → 1.6s → …) — **công thức giống Android** (cùng đội ngũ phát triển áp dụng cùng chiến lược trên 2 nền tảng để hành vi người dùng nhất quán). `classify(_:)` map các mã lỗi POSIX cụ thể từ `NWError`: `ECONNREFUSED/ECONNRESET/ETIMEDOUT/EBUSY/EADDRINUSE` → `.busy` (máy in đang bị chiếm bởi thiết bị khác — nên retry có ý nghĩa); `EHOSTDOWN/EHOSTUNREACH/ENETDOWN/ENETUNREACH` → `.unreachable` (vấn đề mạng nghiêm trọng hơn — máy in có thể đã tắt hoặc đổi IP). Việc phân loại lỗi giúp phía Dart có thể hiển thị thông báo khác nhau ("máy in đang bận, đang thử lại" vs "không tìm thấy máy in trên mạng").

### 12.6 Idle-close — đóng "nhẹ nhàng" bằng FIN, không phải RST

Sau khi hàng đợi rỗng **0.6s** (`idleCloseDelay`), connection tự đóng để nhường máy in cho thiết bị khác — cùng lý do với Android mục 6. Điểm kỹ thuật đáng chú ý: iOS đóng bằng `connection.send(content: nil, contentContext: .finalMessage, isComplete: true, ...)` — gửi gói FIN "đúng chuẩn" TCP, cho phép dữ liệu còn trong buffer gửi kịp flush hết trước khi đóng — **thay vì** `connection.cancel()` (đóng cứng bằng RST). Dùng RST có rủi ro cắt cụt phần cuối bản in vẫn còn nằm trong buffer gửi của hệ điều hành nhưng chưa kịp truyền hết qua mạng.

### 12.7 `LANPrinterManager` — quản lý theo IP, giống triết lý Android

`registeredPrinters: Set<String>` đóng vai trò tương tự `registeredLanPrinters` bên Android — phân biệt "đã ghép nối" (dùng cho `isConnected(ip:)`, không chặn nhầm việc in khi socket vừa tự nhả) với `hasLiveSocket` (socket vật lý đang mở thật). `getConnectedPrinters()` trả **union** của cả hai, dùng khi in broadcast (không chỉ định deviceId) tới mọi máy in LAN đã biết.

### 12.8 Phân tích cải thiện — `pendingConfirmJob` dùng chung có thể làm mất completion (2026-08-22)

- **[`pendingConfirmJob`](ios/Classes/LANPrinterConnection.swift#L73) là MỘT Ô NHỚ dùng chung cho mọi job, không phải hàng đợi theo id** — trong [`flushQueue()`](ios/Classes/LANPrinterConnection.swift#L294), `isWriting = false` được set ngay khi TCP nhận xong ([dòng 334](ios/Classes/LANPrinterConnection.swift#L334)), **trước khi** biết máy in có ack thật hay không — nghĩa là `flushQueue()` có thể chạy tiếp cho job kế tiếp trong lúc job trước còn đang ở trạng thái "chờ xác nhận 0.4s" ([`acceptConfirmDelay`](ios/Classes/LANPrinterConnection.swift#L77), gán `pendingConfirmJob` ở [dòng 364](ios/Classes/LANPrinterConnection.swift#L364)). Nếu job2 cũng gửi xong không lỗi trong cửa sổ 0.4s đó, dòng 364 **ghi đè** tham chiếu tới job1. Khi closure xác nhận của job1 (đặt lịch sớm hơn) tới hạn trước ([dòng 365-368](ios/Classes/LANPrinterConnection.swift#L365-L368)), nó đọc `pendingConfirmJob` — lúc này đã là **job2** — gọi nhầm completion của job2, còn completion thật của job1 **không bao giờ được gọi**. Nếu tầng gọi đang chờ (`await`) completion đó, lệnh in đó **treo vĩnh viễn** — không lỗi, không timeout, khó phát hiện qua log vì không có gì báo sai. Đây là hệ quả nặng hơn một race lệch-thứ-tự thông thường: mất hẳn 1 callback. *Gợi ý: gắn id cho từng job khi đặt lịch xác nhận, so khớp đúng id khi closure fire thay vì đọc biến scalar dùng chung; hoặc không set `isWriting=false` cho tới khi xác nhận 0.4s xong.*
- Đã kiểm tra và xác nhận **an toàn** (không phải bug): [`isFirstJobOnSocket`](ios/Classes/LANPrinterConnection.swift#L69) không có race vì mọi thao tác đọc/ghi cờ này cùng chạy trên một serial `queue` duy nhất của connection — không thể có 2 "job đầu tiên" cùng lúc trên một socket.

---

## 13. iOS — Cách lệnh ESC/POS được build từ ảnh

### 13.1 `ESCPosPrinter.swift` — chỉ xử lý ảnh, không xử lý text/barcode "gốc"

Cần phân biệt rõ: file này **chỉ** build lệnh cho (a) in một ảnh bitmap hoàn chỉnh (`printImageESC`, dùng cho method `print_image_esc` — toàn bộ nội dung hóa đơn đã được Flutter render sẵn thành ảnh) và (b) mở két. Các lệnh ESC/POS "gốc" thao tác trực tiếp text/barcode/QR (không qua ảnh) nằm ở `PrinterLabelPlugin.swift`, dùng SDK `PTCommandESC` — không liên quan tới `ESCPosPrinter`.

### 13.2 Gộp nhiều bản in thành một job — cùng lý do với Android

`printImageESC` nhân dữ liệu ESC/POS theo `quantity` rồi gửi 1 lần duy nhất (không lặp lại toàn bộ hàm build+gửi N lần) — tránh khoảng dừng giữa các bản in kích hoạt cơ chế tự nhả socket LAN (mục 12.6) giữa 2 bản, gây gián đoạn không cần thiết.

### 13.3 Quy trình build (`buildAndSendESC`)

1. Decode `UIImage` từ data ảnh.
2. Tính `targetWidth` theo khổ giấy đã chọn: 58mm → 384 dots, 80mm → 576 dots (mặc định 576 nếu không rõ khổ) — đây là độ phân giải chuẩn ngành cho 2 khổ giấy nhiệt phổ biến nhất.
3. Resize ảnh giữ nguyên tỷ lệ về `targetWidth`.
4. Build byte raster bằng `escPosRasterBytes(from:bandHeight:)`, `bandHeight = 128` dòng.
5. Ghép gói lệnh cuối: `ESC @` (initialize) → `ESC a 1` (căn giữa) → raster data → `LF ×5` (feed) → `GS V 66 1` (cắt giấy) — **thứ tự và ý nghĩa từng lệnh giống hoàn toàn Android** (mục 8.2), vì cả 2 nền tảng nhắm tới đúng cùng loại máy in ESC/POS chuẩn Epson.

### 13.4 Lịch sử: vì sao lại là 128 dòng, không phải 1 lệnh cho cả bill?

Comment trong code kể lại một vòng lặp sửa lỗi đáng chú ý: ban đầu, để "tránh lỗi firmware in ra chuỗi debug khi các dải tới không đồng bộ", nhóm phát triển đã thử dùng **1 lệnh `GS v 0` duy nhất cho toàn bộ bill** (không chia dải). Nhưng cách này gây ra lỗi **còn nặng hơn**: với đơn hàng dài (vượt giới hạn chiều cao/lệnh mà firmware một số máy in chấp nhận), máy in sẽ **hủy chế độ raster mode giữa đường** và diễn giải phần dữ liệu ảnh còn lại như là văn bản thô → in ra một đoạn ký tự rác thay cho phần cuối bill. Giải pháp đúng cuối cùng: **quay lại chia dải 128 dòng** (giống Android — 2 nền tảng đã hội tụ về cùng một con số qua kinh nghiệm thực tế độc lập), và xử lý đúng gốc rễ của vấn đề "dải tới không đồng bộ" ban đầu bằng cách **sửa nhịp gửi dữ liệu** trong `BLEManager.writeData` (thêm backpressure/pause đúng cách) thay vì né tránh bằng cách gộp lệnh.

### 13.5 `escPosRasterBytes` — chi tiết build byte & một bẫy bộ nhớ Swift cụ thể

Hàm đọc pixel ảnh bằng `CGContext` với buffer cấp phát **thủ công** (`UnsafeMutablePointer<UInt8>.allocate(...)`) — **cố ý không dùng** `&pixels` của một Swift Array. Lý do kỹ thuật quan trọng: khi truyền `&array` vào một API C (như khởi tạo `CGContext`), Swift chỉ đảm bảo con trỏ đó hợp lệ **trong đúng lời gọi hàm đó** — nếu `CGContext` giữ tham chiếu tới buffer lâu hơn (ví dụ để dùng lại ở các lời gọi `draw`/đọc pixel sau), Swift có thể đã di chuyển hoặc giải phóng bộ nhớ của array đó ở hậu trường, dẫn tới `EXC_BAD_ACCESS` (crash truy cập bộ nhớ đã giải phóng) — một lớp bug rất khó debug vì crash xảy ra "sau" thời điểm nhìn có vẻ hợp lý trong code. Cấp phát thủ công bằng `UnsafeMutablePointer.allocate` tránh hoàn toàn rủi ro này vì bộ nhớ do lập trình viên tự quản lý vòng đời (và tự `deallocate` sau khi dùng xong).

Chi tiết build: `widthBytes = (width + 7) / 8` (đóng gói 8 pixel/byte, quy tắc chuẩn của ESC/POS raster); mỗi dải có header `[0x1D, 0x76, 0x30, 0x00, widthBytes%256, widthBytes/256, bandRows%256, bandRows/256]` (chính là cấu trúc lệnh `GS v 0 m xL xH yL yH` với `m=0` — raster mode bình thường); mỗi pixel tính `gray = 0.299R + 0.587G + 0.114B`, `alpha ≤ 50` (gần trong suốt) coi là trắng, `gray < 200` → bit đen — **hoàn toàn khớp công thức và ngưỡng của Android**, một chỉ dấu rõ ràng cho thấy 2 team đã cố ý đồng bộ hành vi hiển thị giữa 2 nền tảng để khách hàng dùng chung ứng dụng không thấy sự khác biệt khi in trên iOS vs Android.

### 13.6 Kẹp giá trị an toàn — khác biệt ngôn ngữ Swift vs Kotlin cần lưu ý

`escPosRasterBytes` chủ động giới hạn `bandHeight` trong khoảng `[1, 65535]` **trước khi** ép kiểu về `UInt8` cho các byte header. Lý do: `UInt8(someInt)` trong Swift sẽ **crash cứng ngay lập tức** (runtime trap) nếu giá trị đầu vào vượt phạm vi 0-255 — khác hẳn Kotlin, nơi `.toByte()` **âm thầm cắt bit** (wrap around) mà không ném exception. Đây là một khác biệt ngôn ngữ tinh vi: code Kotlin tương tự có thể "chạy được nhưng cho kết quả sai" khi giá trị vượt phạm vi, còn code Swift tương tự sẽ **crash ứng dụng ngay lập tức** nếu không có bước kẹp giá trị (clamp) tường minh này — vì vậy đoạn code này không thể bỏ qua khi port logic tương tự sang Swift.

### 13.7 `openDrawer` và `ImageUtils.binarized`

`openDrawer` gửi cứng `[0x1B,0x70,0x00,0x19,0xFA, 0x1B,0x70,0x01,0x19,0xFA]` — 2 biến thể lệnh `ESC p 0`/`ESC p 1`, giống lý do Android (mục 8.2): các hãng két khác nhau đấu vào chân khác nhau của cổng RJ11/RJ12, gửi cả 2 để tương thích rộng.

`ImageUtils.binarized(threshold: 200)` — dùng cho luồng **TSPL** (khác `escPosRasterBytes` dùng cho luồng ESC), cùng chung công thức luminance và ngưỡng 200, cùng chung kỹ thuật cấp phát buffer thủ công để tránh `EXC_BAD_ACCESS`, nhưng **không có dithering** (không dùng thuật toán Floyd–Steinberg hay tương tự để mô phỏng sắc độ trung gian bằng mẫu điểm) — chỉ là ngưỡng cứng 1-bit đơn giản, nhất quán với cách Android xử lý ảnh TSPL (`AlgorithmType.Threshold`).

### 13.8 Phân tích cải thiện — `printImageESC` báo thành công giả, bất kể gửi thật thành hay bại (2026-08-22)

- **[`printImageESC`](ios/Classes/ESCPosPrinter.swift#L8-L46) gọi [`plugin?.sendToPrinter(...)`](ios/Classes/ESCPosPrinter.swift#L43) rồi bỏ qua kết quả trả về, gọi [`result(true)`](ios/Classes/ESCPosPrinter.swift#L44) ngay lập tức.** Đây là method in ảnh hóa đơn phổ biến nhất trên iOS. Theo thiết kế đã nêu ở mục 14.2, `routeToBLE` là fire-and-forget có chủ đích (để không chặn UI chờ tới khi in xong thật) — nhưng hệ quả cụ thể ở đây là: toàn bộ cơ chế xác nhận tinh vi của `LANPrinterConnection` (0.4s chờ xác nhận máy in không tự đóng socket, retry 4 lần backoff) và mọi lỗi ghi BLE (DISCONNECTED/WRITE_TIMEOUT/WRITE_FAILED) chỉ được `print()` ra console, **không bao giờ tới được Dart** qua chính con đường in phổ biến nhất. Nếu máy in tắt nguồn giữa lúc in, rớt kết nối, hoặc `print_image_esc` được gọi khi chưa hề `connect_bt`/`connect_lan`, Dart vẫn nhận `true` — không có cách nào ở tầng ứng dụng biết đã in được bao nhiêu phần trăm hay in đã thất bại hoàn toàn. *Gợi ý: cho `sendToPrinter`/`routeToBLE`/`LANPrinterManager.send` một completion thật, trả kết quả về Dart sau khi biết chắc gửi thành công/thất bại — cần cân nhắc thêm timeout hợp lý phía Dart thay vì chờ vô hạn, vì gửi qua BLE chậm có thể mất vài giây.*

---

## 14. iOS — Định tuyến lệnh in & cấu hình mạng

### 14.1 Bảng method → handler trong `PrinterLabelPlugin.swift`

| Method | Tham số chính | Xử lý / route tới |
|---|---|---|
| `scan_bt` | — | `BLEManager.shared.startScan()`; trả `false` nếu quyền Bluetooth bị từ chối |
| `stop_scan_bt` | — | `BLEManager.shared.stopScan()` |
| `connect_bt` | `mac_address`/`identifier` | `BLEManager.shared.connect` |
| `get_bluetooth_devices` | — | `BLEManager.shared.getDiscoveredDevices()` |
| `disconnect` | `device_id?`, `connection_type?` | Suy luận BLE/LAN/cả hai |
| `connect_lan` | `ip_address` | `LANPrinterManager.shared.connect(ip:port:9100)` |
| `print_label` | `images[]`, `size`, `gap`, `use_home`, ... | TSPL qua `PTCommandTSPL` |
| `print_text` / `print_barcode` / `print_qrcode` | — | TSPL text/barcode/QR |
| `print_text_esc` / `print_barcode_esc` / `print_qrcode_esc` | — | ESC/POS qua `PTCommandESC` |
| `print_image` | `image, x, y, width, height` | TSPL bitmap, dùng `binarized(threshold:200)` |
| `print_image_esc` | `image, device_id, connection_type, size, quantity` | `escPrinter.printImageESC` |
| `open_drawer` | `device_id, connection_type` | `escPrinter.openDrawer` |
| `identify_lan_printer` | `ip_address, bytes` | Gửi bytes tùy ý trực tiếp qua `LANPrinterManager.shared.send` |
| `checkConnect` / `check_printer_status` | `device_id?` | Kiểm tra BLE/LAN |
| `bluetooth_enabled` | — | `BLEManager.shared.isBluetoothEnabled` |
| `scan_net_printers` | — | `PTDispatcher` (SDK) + `POSNetConfigHelper.scanUdpPrinters` chạy song song, hợp nhất theo `ip|mac` |
| `set_net_ip` | `ip, mask, gateway, dhcp, mac, current_ip` | Ưu tiên UDP (`POSNetConfigHelper.sendUdpNetConfig`) nếu có `mac`; fallback TCP ESC qua port 9100 |

### 14.2 `sendToPrinter` — điểm định tuyến trung tâm, giải thích 4 nhánh quyết định

```
1. connectionType == "Bluetooth"
     → route BLE theo deviceId (hoặc broadcast tới thiết bị BLE đầu tiên nếu không có id)
2. Không có connectionType, nhưng deviceId trích được UUID (tiền tố "BT:")
     → cũng route BLE (suy luận từ hình dạng deviceId khi Dart không truyền connectionType)
3. deviceId có (không rơi vào case BLE) → trích IP (tiền tố "LAN:") → gửi qua LANPrinterManager
4. Không có deviceId nào cả
     → BROADCAST tới TẤT CẢ: mọi peripheral BLE đang connected + mọi IP LAN đã ghép nối
```

Nhánh 4 (broadcast không điều kiện) tồn tại để hỗ trợ kịch bản "in ra tất cả máy in đang kết nối" (ví dụ in phiếu bếp ra mọi máy in bếp cùng lúc) mà không cần Dart tự liệt kê từng deviceId.

`routeToBLE` là **fire-and-forget**: chỉ log lỗi ra console, không trả `FlutterError` về Dart. Điều này phản ánh một quyết định thiết kế có chủ đích: các hàm `print*` coi việc in là một **tác vụ bất đồng bộ đã được xếp hàng thành công** (trả `result(true)` ngay sau khi enqueue vào `BLEManager`/`LANPrinterManager`), không phải một tác vụ đồng bộ chờ tới khi giấy ra khỏi máy in mới coi là xong — vì việc chờ thật sự có thể mất vài giây (đặc biệt qua BLE chậm) và sẽ khiến UI Flutter cảm giác "treo" nếu await tới lúc đó.

### 14.3 `POSNetConfigHelper.swift` — cấu hình IP tĩnh, độc lập hoàn toàn với Bluetooth

Đây **không liên quan gì tới Bluetooth** — là cơ chế cấu hình **địa chỉ IP tĩnh cho máy in LAN** (đổi từ DHCP sang IP cố định, hoặc đổi IP tĩnh khác) qua **UDP broadcast**, tách biệt hoàn toàn khỏi kênh in TCP 9100.

`buildUdpSavePacket`: dựng gói đúng **34 byte** theo giao thức độc quyền `XP0001SAVE` (của dòng máy in Xprinter) — layout cố định: header ASCII 10 byte, MAC 6 byte, magic `0x22 0x00`, IP mới 4 byte, mask 4 byte, gateway 4 byte, port 9100 dạng little-endian 2 byte, cờ DHCP 1 byte, padding 1 byte. Cấu trúc này **khớp bit-for-bit** với SDK chính thức của hãng (POSWIFIManager trên iOS, PosUdpNet trên Android AAR) — nghĩa là gói được build thủ công thay vì gọi SDK, có thể vì SDK gốc không expose đủ tùy chọn cấu hình cần thiết, hoặc để giảm phụ thuộc thêm một SDK khác chỉ cho một tác vụ.

`sendUdpNetConfig`: mở UDP socket, set cờ `SO_BROADCAST` (bắt buộc để hệ điều hành cho phép gửi tới địa chỉ broadcast), gửi gói tới `255.255.255.255` (broadcast toàn mạng) **cộng thêm** mọi địa chỉ broadcast riêng của từng network interface đang hoạt động **cộng thêm** `currentIp` (nếu Dart cung cấp, gửi trực tiếp unicast tới đúng máy in) — gửi lặp 3 lần, cách nhau 30ms, tới mỗi đích. Gửi lặp nhiều lần và tới nhiều đích cùng lúc là chiến lược bù cho **UDP không đảm bảo gói tin tới đích** (không có handshake, không có retransmit tự động như TCP) — tăng xác suất ít nhất 1 gói tới đúng máy in trong môi trường mạng WiFi có thể mất gói ngẫu nhiên. Cổng đích cố định **9000** (khác cổng in 9100) để máy in phân biệt rõ "đây là gói cấu hình" và không hiểu nhầm là dữ liệu cần in.

`getBroadcastAddresses`: dùng `getifaddrs` (API BSD chuẩn) để liệt kê địa chỉ broadcast của mọi network interface đang `UP`+`RUNNING`+hỗ trợ `BROADCAST` (loại trừ loopback) — cần thiết vì thiết bị iOS có thể có nhiều interface hoạt động cùng lúc (WiFi + Hotspot cá nhân...), và địa chỉ broadcast toàn cục `255.255.255.255` không phải lúc nào cũng được router chuyển tiếp đúng trong mọi cấu hình mạng.

`scanUdpPrinters`: gửi `"XP0001FIND"` broadcast tới cổng 9000, sau đó `recvfrom` lặp trong khoảng timeout (thường gọi với 1.0-1.3s từ `PrinterLabelPlugin`), với mỗi lần chờ tối đa 200ms (`SO_RCVTIMEO`) — chờ theo từng vòng ngắn thay vì một timeout dài duy nhất để có thể nhận nhiều phản hồi từ nhiều máy in khác nhau trả về ở các thời điểm khác nhau. Parse phản hồi có header `"XP0001FOUND"` để lấy MAC/IP/mask/gateway/DHCP, loại trùng theo MAC.

**Khác biệt quan trọng so với Android cần lưu ý khi bảo trì**: SDK máy in cho iOS (`PTDispatcher`) **không có API cấu hình IP theo MAC** như SDK Android (`POSPrinter.udpNetConfig` nhận `mac` trực tiếp). Do đó `PrinterLabelPlugin` phải tự cache `mac -> ip` (`lastScannedMacToIp`) từ lần `scan_net_printers` gần nhất, để khi Dart gọi `set_net_ip` chỉ với `mac` (không kèm `current_ip`), plugin vẫn tra được IP hiện tại cần gửi gói cấu hình tới.

### 14.4 Phân tích cải thiện — quét UDP chồng lấn có thể chia nhau gói phản hồi (2026-08-22)

[`scanUdpPrinters`](ios/Classes/POSNetConfigHelper.swift#L203) set cả `SO_REUSEADDR` lẫn [`SO_REUSEPORT`](ios/Classes/POSNetConfigHelper.swift#L218) rồi bind cổng 9000 cố định. Nếu `scan_net_printers` được gọi 2 lần liên tiếp (ví dụ người dùng bấm "quét lại" trước khi lần trước hết 1.0-1.5s timeout), 2 socket cùng bind cổng 9000 nhờ `SO_REUSEPORT` — hệ điều hành **phân phối ngẫu nhiên** từng datagram `XP0001FOUND` đến một trong hai socket, không phải cả hai, nên mỗi lần scan chỉ nhận được một tập con máy in trên mạng, kết quả không xác định giữa các lần gọi. *Gợi ý: chặn scan chồng lấn bằng một cờ "đang scan" (tương tự cơ chế `isScanning` của `BLEManager`), hoặc bỏ `SO_REUSEPORT` và để lần gọi sau chờ lần trước đóng socket.*

---

## 15. So sánh Android vs iOS

| Khía cạnh | Android | iOS |
|---|---|---|
| SDK kết nối | `net.posprinter` (thương mại, đóng gói sẵn abstraction) | Tự viết (CoreBluetooth + Network.framework) |
| SDK lệnh TSPL/ESC gốc (text/barcode/QR) | `net.posprinter.TSPLPrinter`/`POSPrinter` | `PrinterSDK` (`PTCommandTSPL`/`PTCommandESC`) |
| Build lệnh raster ảnh ESC | Tự build trong `PrinterThermal.getEscPosRasterBytes` | Tự build trong `ESCPosPrinter.escPosRasterBytes` |
| Ngưỡng nhị phân hóa ảnh | `gray < 200` | `gray < 200` (đồng bộ có chủ đích) |
| Band height raster | 128 dòng | 128 dòng (cả 2 hội tụ về cùng số qua kinh nghiệm thực tế độc lập) |
| Bluetooth | Classic SPP (qua SDK) | BLE (CoreBluetooth GATT) — do giới hạn của Apple |
| Chunk gửi Bluetooth | 120 bytes cố định, sleep 4ms/gói, nghỉ 80ms/1500 bytes | Theo `maximumWriteValueLength` (MTU thật, biến động) + pause ~86µs/byte |
| USB | Có, đầy đủ (permission, attach/detach, stable id) | Không hỗ trợ (Apple không cho phụ kiện USB máy in thông thường) |
| LAN — cổng in | TCP 9100 | TCP 9100 |
| LAN — chia sẻ socket cho nhiều thiết bị | Có (`registeredLanPrinters`, đếm job theo `AtomicInteger`, idle-close 800ms, watchdog 15s) | Có (`registeredPrinters`, idle-close 0.6s, xác nhận thêm 0.4s sau khi gửi) |
| LAN — retry gửi dữ liệu | Không có tầng retry riêng (dựa vào `sendAllSync` báo lỗi tường minh, retry ở tầng connect) | Có tầng retry riêng cho cả gửi dữ liệu (`maxAttempts=4`, backoff 0.4s×2ⁿ) |
| Quét máy in LAN | ARP/`ip neigh` (không mở socket) + UDP broadcast SDK | UDP broadcast tự viết (`POSNetConfigHelper`) + SDK `PTDispatcher` |
| Cấu hình IP máy in LAN | UDP (SDK, nhận mac trực tiếp) ưu tiên, fallback TCP ESC port 9100 | UDP tự viết (phải tự cache mac→ip vì SDK không hỗ trợ) ưu tiên, fallback TCP ESC port 9100 |
| Máy in tích hợp (built-in) | Có (Sunmi/iMin/Pax qua Bluetooth nội bộ, hoặc Urovo qua reflection riêng) | Không có khái niệm built-in riêng biệt |
| Két tiền (cash box) | `CashBoxManager` — reflection/AIDL/broadcast theo hãng POS (iMin/Sunmi/Urovo) | Không có — chỉ mở két qua lệnh `ESC p` gửi tới máy in |
| Đồng bộ hóa gửi dữ liệu | Lock theo connection (`synchronized`) + `awaitLabelSent`/`awaitFlush` (callback SDK) | Serial GCD queue theo connection/peripheral + semaphore ack |
| Timeout connect | 5000ms (mọi loại) | 5.0s (BLE) / 4s (LAN) |
| Auto-reconnect sau khi mất kết nối | LAN: có (tự mở lại khi cần gửi); Bluetooth: không | LAN: có (tự mở lại khi cần gửi); BLE: không |
| Rủi ro đặc thù ngôn ngữ | Kotlin `.toByte()` cắt bit âm thầm nếu tràn kiểu (rủi ro ẩn) | Swift `UInt8(...)` crash cứng nếu tràn kiểu (đã được kẹp giá trị tường minh để phòng) |

---

## 16. Luồng ví dụ end-to-end

### 16.1 In tem TSPL qua LAN (Android)

1. Dart gọi `connect_lan` → `PrinterMethodCallHandler` → `plugin.connectNet(ip, result)` → `POSConnect.createDevice(DEVICE_TYPE_ETHERNET)` → `device.connect(ip, makeConnectListener)`.
2. `makeConnectListener` nhận `CONNECT_SUCCESS` → lưu `connections["LAN:$ip"]`, thêm ip vào `registeredLanPrinters`, `pending.complete(true)`.
3. Dart render label thành PNG bytes, gọi `print_label` với `images`, `size`, `gap`.
4. `runPrintJob` → `resolveConnectionsForPrint` tìm/mở lại connection LAN (`ensureLanConnectedSync` nếu socket đã nhả) → `retainLanSocket` (tăng bộ đếm job) → spawn thread → `printLabel(call, conn, jobResult)`.
5. `printLabel` decode/scale/dịch bitmap, `synchronized(lockFor(conn))` build lệnh TSPL, gửi qua `TSPLPrinter`, `awaitLabelSent(conn)` chờ xác nhận đã ghi ra socket, `recycle()` bitmap **chỉ sau khi** xác nhận này về.
6. `jobResult.success(true)` → `releaseOnce()` → `releaseLanSocket(conn, closeWhenIdle=true)` (giảm bộ đếm, về 0 thì hoãn 800ms rồi đóng socket TCP thật) → máy khác có thể dùng lại máy in.
7. Kết quả trả về Dart qua `result.success(true)`.

### 16.2 In hóa đơn ESC qua Bluetooth (iOS)

1. Dart gọi `connect_bt` với `mac_address`/UUID → `BLEManager.shared.connect(identifier:)` → tìm trong scan cache/`retrievePeripherals` → `centralManager.connect` → `didConnect` → `discoverServices`/`discoverCharacteristics` (chờ hết toàn bộ service) → fire kết quả `true`.
2. Dart chụp widget hóa đơn thành ảnh (`WidgetCaptureHelper`), resize tối ưu Bluetooth (`resizeThermalImage` — giảm dung lượng vì băng thông BLE hạn chế), gọi `printESC` (method `print_image_esc`) với `quantity`.
3. `PrinterLabelPlugin` dispatch tới `escPrinter.printImageESC` → nhân dữ liệu theo `quantity` (gộp thành 1 job liên tục), gọi `buildAndSendESC` → decode ảnh, resize theo khổ giấy (384/576 dots), `escPosRasterBytes` chia dải 128 dòng (tránh lỗi firmware với đơn dài), ngưỡng `gray<200` (giữ nét chữ nhỏ) → gói lệnh `ESC @ + ESC a 1 + raster + feed + cut`.
4. `plugin.sendToPrinter(data, deviceId, "Bluetooth")` → `routeToBLE` (fire-and-forget) → `BLEManager.writeData` — chunk theo MTU thật, pause ~86µs/byte (mô phỏng tốc độ đầu in vật lý), chờ `waitUntilReadyToWrite`/ack tùy write type (hoặc `.withResponse` bắt buộc nếu là máy in "yếu nguồn" trong danh sách cứng).
5. Nếu ứng dụng yêu cầu mở két (`ESCPrintServiceImpl.printWidgetToDevices`), lệnh `openDrawer` đã được gọi **riêng, trước khi** gửi bill, và chỉ trên các máy đang thực sự in lượt đó — tránh vô tình mở két ở quầy khác.
