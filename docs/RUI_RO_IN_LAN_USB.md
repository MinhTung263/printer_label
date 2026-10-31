# Rủi ro còn tồn tại khi in LAN và USB

Dành cho dev của plugin `printer_label`. Phân tích đi từ API `PrinterLabel` (Dart), qua method channel, xuống native
Android (`PrinterMethodCallHandler`, `PrinterLabelPlugin`, `PrinterThermal`, `LanSocketConnection`) và iOS
(`LANPrinterConnection`).

> Cập nhật 2026-10-10. Bổ sung cho [IN_LAN_ON_DINH.md](IN_LAN_ON_DINH.md): mục 6 của tài liệu đó ghi R1–R3 đã làm,
> R4–R10 chưa làm. Tài liệu này **không lặp lại** phần giải thích R4–R10, chỉ liệt kê và tham chiếu.
>
> Cột **Xác nhận**: **Code** = đọc code thấy rõ; **Cần test** = suy ra từ code/SDK, chưa tái hiện trên thiết bị.

---

## Mục lục

1. [Tóm tắt theo mức ưu tiên](#1-tóm-tắt-theo-mức-ưu-tiên)
2. [Lỗi thật dùng chung LAN + USB (nhóm A)](#2-lỗi-thật-dùng-chung-lan--usb-nhóm-a)
3. [Rủi ro riêng của USB (nhóm U)](#3-rủi-ro-riêng-của-usb-nhóm-u)
4. [Độ tin cậy LAN còn lại (nhóm B)](#4-độ-tin-cậy-lan-còn-lại-nhóm-b)
5. [Hợp đồng API của `PrinterLabel` (nhóm C)](#5-hợp-đồng-api-của-printerlabel-nhóm-c)
6. [Dọn dẹp và hiệu năng (nhóm D)](#6-dọn-dẹp-và-hiệu-năng-nhóm-d)
7. [Thứ tự đề xuất](#7-thứ-tự-đề-xuất)

---

## 1. Tóm tắt theo mức ưu tiên

| Mã | Rủi ro | Kết nối | Mức | Xác nhận |
|---|---|---|---|---|
| A1 | `check_printer_status` mở socket LAN mà không bao giờ nhả | LAN | **Cao** | Code |
| A2 | `printImage` trên Android ném `MissingPluginException` | Cả hai | **Cao** | Code |
| A3 | Lệnh nhỏ (text/barcode/QR/mở két) báo OK trước khi gửi thật | Cả hai | **Cao** | Code |
| A4 | In tem TSPL qua USB có thể báo OK giả / in ra ký tự rác | USB | **Cao** | Code + Cần test |
| A5 | `print_all` "gửi rồi quên", không giữ/nhả socket LAN | Cả hai | Trung bình | Code |
| U1 | Hai máy in cùng model không có serial bị gộp chung một `deviceId` | USB | Thấp | Code; Xprinter đã test: có serial riêng |
| U2 | `connectUsb` có thể treo Future vô hạn (không có timeout) | USB | **Cao** | Code |
| U3 | Đứt giữa chừng (hết giấy, rút dây) để lại lệnh raster dở dang | USB | Cao | Cần test |
| U4 | Kết nối USB rớt thì lệnh in không tự kết nối lại | USB | Trung bình | Code |
| U5 | Sự kiện ATTACHED/quét lại đóng kết nối USB đang in | USB | Trung bình | Code |
| U6 | Đổi owner giữa nhiều FlutterEngine cắt kết nối đang in | USB | Trung bình | Code |
| U7 | Máy in tắt/bật nguồn mất quyền USB, popup giữa ca bán | USB | Trung bình | Code (hành vi Android) |
| U8 | Máy in dùng interface class `0xFF` không được tự nhận | USB | Thấp | Code |
| U9 | Báo "kết nối thành công" dù chưa ghi thử được | USB | Thấp | Code |
| U10 | Map trạng thái USB không thread-safe | USB | Thấp | Code |
| B1–B6 | R4–R10 chưa làm + `identify_lan_printer` dùng socket thô | LAN | Cao → Thấp | Xem mục 4 |
| C1–C4 | API Dart nuốt kết quả `false`, lỗi không có kiểu | Cả hai | Trung bình | Code |
| D1–D3 | Code chết, status trả sai, bill nặng | Cả hai | Thấp | Code |

---

## 2. Lỗi thật dùng chung LAN + USB (nhóm A)

### A1. `check_printer_status` mở socket LAN mà không bao giờ nhả

- **Vị trí:** [PrinterMethodCallHandler.kt](../android/src/main/kotlin/com/printer/printer_label/PrinterMethodCallHandler.kt), nhánh `check_printer_status`.
- **Hiện tượng:** nhánh này gọi `plugin.ensureLanConnectedSync(ip)` để mở lại socket, nhưng không gọi `retainLanSocket` / `releaseLanSocket` như `runPrintJob`. Socket bị giữ tới lần in kế tiếp của chính thiết bị này.
- **Hậu quả:** mỗi lần app hỏi trạng thái (mở màn chọn máy in, kiểm tra trước khi in), các thiết bị khác báo "máy in bận" cho tới khi máy này in lại.
- **Sửa:** `retainLanSocket(conn)` trước khi hỏi trạng thái, rồi `releaseLanSocket(conn)` sau khi trả kết quả, kể cả nhánh timeout `"unknown"`.

### A2. `PrinterLabel.printImage` không chạy trên Android

- **Vị trí:** Dart gọi method `print_image` ([printer_label_method_channel.dart](../lib/src/platform/printer_label_method_channel.dart)). iOS có xử lý ([PrinterLabelPlugin.swift](../ios/Classes/PrinterLabelPlugin.swift), `case "print_image"`), còn `when` của Android không có nhánh này nên rơi vào `notImplemented()`.
- **Hậu quả:** gọi trên Android là ném `MissingPluginException`.
- **Sửa:** thêm nhánh `print_image` (dùng lại `printLabel` với một ảnh), hoặc đánh dấu API chỉ dành cho iOS.

### A3. Lệnh nhỏ báo thành công trước khi gửi thật

- **Vị trí:** `printTextESC`, `printBarcodeESC`, `printQRCodeESC`, `openDrawer` trong [PrinterThermal.kt](../android/src/main/kotlin/com/printer/printer_label/PrinterThermal.kt), cùng `printText`, `printBarcode`, `printQRCode` (TSPL) trong plugin.
- **Hiện tượng:** các hàm này dùng `POSPrinter` / `TSPLPrinter` / `sendData` của SDK. Những API đó chỉ xếp lệnh vào hàng đợi rồi return, sau đó code gọi `result.success(true)` ngay.
- **Hậu quả:**
  - **LAN:** `runPrintJob` nhả socket 800ms sau đó, và `LanSocketConnection.close()` xoá hàng đợi. Mạng yếu thì lệnh mở két hoặc in text có thể mất mà app vẫn nhận OK.
  - **USB:** báo OK trong lúc dữ liệu còn nằm trong hàng đợi SDK. Rút dây hoặc hết giấy ngay lúc đó thì mất lệnh mà không có lỗi nào.
- **Sửa:** tự dựng byte ESC/POS rồi gửi bằng `PrinterThermal.sendAllSync`, giống đường in bill `printImageESC`.

### A4. In tem TSPL qua USB có thể báo OK giả hoặc in ra ký tự rác

- **Vị trí:** `printLabel` trong [PrinterLabelPlugin.kt](../android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt) và `PrinterThermal.awaitLabelSent`.
- **Hiện tượng:** LAN đã dùng `LanSocketConnection.awaitIdle` (chờ thật). USB vẫn đi qua `TSPLPrinter` của SDK và chỉ chờ callback trong **300ms**. SDK chỉ gọi callback tối đa 1 lần mỗi 2s, nên khoảng một nửa số tem in liên tiếp không bao giờ được xác nhận.
- **Hậu quả:**
  - Hết 300ms thì code chạy tiếp `shifted.recycle()` trong lúc luồng consumer của SDK có thể vẫn đang encode bitmap. Chú thích trong code đã ghi nhận đúng lỗi này: tem ra **ký tự rác**.
  - Lỗi ghi của SDK không ném lên được, nên tem hỏng vẫn báo thành công.
- **Sửa:** tự dựng lệnh TSPL (`SIZE`, `GAP`, `CLS`, `BITMAP`, `PRINT`) thành `ByteArray` rồi gửi bằng `sendAllSync`, bỏ hàng đợi SDK cho cả USB lẫn LAN. Cách khác: bọc USB bằng một lớp `IDeviceConnection` riêng (`UsbDeviceConnection.bulkTransfer` có timeout), giống `LanSocketConnection`.

### A5. `print_all` gửi rồi quên

- **Vị trí:** nhánh `print_all` trong [PrinterMethodCallHandler.kt](../android/src/main/kotlin/com/printer/printer_label/PrinterMethodCallHandler.kt).
- **Hiện tượng:** nhánh này dùng `NoOpResult`, trả `true` ngay và không gọi `retainLanSocket`/`releaseLanSocket`.
- **Hậu quả:** Dart không biết máy nào lỗi. Socket LAN có thể bị đóng giữa chừng (job khác nhả), hoặc bị giữ mãi.
- **Sửa:** cho từng kết nối đi qua `runPrintJob`, hoặc gom kết quả rồi trả về danh sách máy lỗi.

---

## 3. Rủi ro riêng của USB (nhóm U)

### U1. Hai máy in cùng model không có serial bị gộp chung một `deviceId`

- **Vị trí:** `stableUsbId` / `usbModelId` trong [PrinterLabelPlugin.kt](../android/src/main/kotlin/com/printer/printer_label/PrinterLabelPlugin.kt).
- **Hiện tượng:** id có dạng `USB:v{vid}_p{pid}_s{serial}`. Nhiều máy in giá rẻ **không có serial**, hoặc mọi máy trong lô đều mang cùng một serial cố định. Khi đó hai máy cùng model có cùng id: `USB:v1155_p22304`.
- **Hậu quả:**
  - `connections[deviceId]` chỉ giữ được một máy. Máy kết nối sau ghi đè máy trước (`tryConnectWithDelay` còn `close()` máy cũ).
  - `connectUsb` dùng `attached.find { ... }` nên luôn lấy máy đầu danh sách.
  - Bill bếp và bill quầy có thể ra **cùng một máy**. Đây đúng là trường hợp quán có 2 máy in USB cùng model cắm vào một máy POS.
- **Kết quả test (2026-10-10):** 2 máy Xprinter cùng model có **serial khác nhau**, nên id khác nhau và không bị gộp. Rủi ro chỉ còn với hãng/model không khai serial hoặc khai serial giống nhau cho cả lô. Hạ mức xuống **Thấp**.
- **Không dùng số đếm hay số ngẫu nhiên để tách id:** id phải ổn định qua rút/cắm lại và khởi động lại thì cấu hình máy in đã lưu mới khớp được.
  - Số ngẫu nhiên: mỗi lần cắm ra id mới, nên máy đã lưu không bao giờ khớp lại.
  - Số đếm: Android liệt kê thiết bị không theo thứ tự cố định, nên bếp/quầy có thể bị đổi chỗ mà không báo lỗi.
- **`device.deviceName` cũng không dùng được:** dạng `/dev/bus/usb/001/00X`, trong đó số cuối tăng mỗi lần cắm lại, không phải số cổng vật lý.
- **Hướng xử lý nếu gặp model không có serial:**
  1. Thử đọc đường dẫn cổng vật lý trong `/sys/bus/usb/devices/` (dạng `1-1.2`). Đường dẫn này chỉ đổi khi cắm sang cổng khác. Android 10+ thường chặn app đọc thư mục này, nhưng máy POS chuyên dụng có thể vẫn đọc được, nên cần test trên máy thật.
  2. Đặt serial / số hiệu USB riêng cho từng máy bằng phần mềm cấu hình của hãng, nếu model có hỗ trợ.
  3. Khi phát hiện hai thiết bị đang cắm có cùng id: không tự chọn máy nào, mà cho từng máy kêu bíp (`identifyUsbPrinter`) để người dùng chỉ định Bếp hay Quầy.
  4. Khuyên dùng hai model khác nhau, hoặc chuyển một máy sang LAN.

### U2. `connectUsb` có thể treo Future vô hạn

- **Vị trí:** `connectUsb`, `tryConnectWithDelay`, `makeConnectListener`.
- **Hiện tượng:** LAN và Bluetooth đều gọi `scheduleConnectTimeout`, còn USB thì không. Future của Dart chỉ hoàn thành khi:
  - SDK gọi listener (`CONNECT_SUCCESS` / `CONNECT_FAIL`),
  - hết 4 lần thử, hoặc
  - người dùng trả lời hộp thoại quyền / rút dây.
- **Hậu quả:**
  - Driver USB treo, hoặc SDK không gọi listener (đã thấy ở các ROM POS lạ), thì `connectUsb` không bao giờ trả về và màn in đứng ở "đang kết nối".
  - Với `holdUsbPermissionQueue = true`: nếu Dart không bao giờ gọi `releaseUsbPermissionQueue` (màn tạo máy bị đóng bất thường), hàng đợi xin quyền của các máy sau cũng bị giữ mãi.
- **Sửa:**
  - Gọi `scheduleConnectTimeout(deviceId, USB_CONNECT_TIMEOUT_MS)` trong `tryConnectWithDelay` (khoảng 8s, tính cả bước "chờ sẵn sàng ghi").
  - Thêm timeout dự phòng cho trạng thái giữ hàng đợi xin quyền (ví dụ 60s thì tự nhả).

### U3. Đứt giữa chừng để lại lệnh raster dở dang

- **Vị trí:** `PrinterThermal.sendAllSync`.
- **Hiện tượng:** giống #5 trong IN_LAN_ON_DINH, nhưng với USB. Từ gói 4KB thứ hai trở đi, nếu `sendSync` trả `<= 0` thì ném lỗi ngay. Các nguyên nhân gặp với USB:
  - **Hết giấy / mở nắp:** máy in ngừng đọc, `bulkTransfer` của SDK hết giờ.
  - **Rút dây / chạm cáp:** ghi thất bại.
- **Hậu quả:** máy in vẫn chờ đủ số byte mà lệnh `GS v 0` đã khai báo, nên **nuốt phần đầu bill sau** và in ra rác hoặc không cắt giấy.
- **Chưa rõ:** timeout `bulkTransfer` mà SDK dùng (cần dịch ngược `printer-lib-3.2.0`). Nếu timeout bằng 0 (chờ vô hạn) thì hết giấy sẽ **treo luồng in và giữ `lockFor(conn)`**, kéo theo mọi bill sau tới máy đó treo theo.
- **Sửa:**
  - Áp dụng R6 cho cả USB: nhớ số byte raster còn thiếu theo `deviceId`. Lần gửi sau, bù đủ byte `0x00` trước rồi mới gửi `ESC @`.
  - Trước mỗi bill, hỏi trạng thái giấy bằng `DLE EOT 4` và báo "Hết giấy" thay vì gửi vào máy đang dừng.
  - Nếu tự quản kết nối USB (xem A4), đặt timeout cho `bulkTransfer` (ví dụ 5s cho mỗi gói).

### U4. Kết nối USB rớt thì lệnh in không tự kết nối lại

- **Vị trí:** `resolveConnectionsForPrint`.
- **Hiện tượng:** với LAN, khi socket đã nhả thì `ensureLanConnectedSync` tự mở lại. USB thì không có bước tương tự. Sau `CONNECT_INTERRUPT`, hoặc sau khi app bị kill rồi mở lại, `connections` không còn kết nối USB và lệnh in trả `NO_CONNECTION`, trừ khi Dart đã gọi `connectUsb` trước.
- **Hậu quả:** lỗi phụ thuộc việc app host có nhớ gọi `connectUsb` hay không. Doc của `PrinterLabel.connectUsb` có nhắc, nhưng rất dễ quên ở luồng in mới.
- **Sửa:** trong `resolveConnectionsForPrint`, nếu `deviceId` bắt đầu bằng `USB:`, thiết bị vẫn đang cắm và đã có quyền thì kết nối đồng bộ, chờ tối đa vài giây (tương tự `ensureLanConnectedSync`).

### U5. Sự kiện cắm / quét lại đóng kết nối USB đang in

- **Vị trí:** `handleUsbDeviceAttached` → `tryConnectWithDelay`.
- **Hiện tượng:**
  - `handleUsbDeviceAttached` gọi `tryConnectWithDelay` mỗi khi máy đã có quyền mà **không kiểm tra kết nối đang sống**. `tryConnectWithDelay` thì `close()` kết nối cũ trước khi tạo kết nối mới.
  - Hàm này chạy khi có broadcast ATTACHED, và khi `scanAndConnectExistingUsbDevices` chạy lúc `usbDeviceStream` có listener đầu tiên.
- **Hậu quả:**
  - Dart huỷ rồi nghe lại `usbDeviceStream`, hoặc hot restart, thì mọi máy in USB bị ngắt rồi nối lại. Bill đang gửi dở bị cắt và thiếu kết nối trong khoảng 1.2s.
  - App hiện tại chỉ `listen` một lần trong `print_service.dart` và không huỷ, nên **rủi ro thấp ở app**. Nhưng đây là bẫy cho người dùng plugin khác.
- **Sửa:** trong `handleUsbDeviceAttached`, nếu `isConnectionActive(deviceId)` thì chỉ cập nhật `usbDevicePaths` và phát lại sự kiện connected, không kết nối lại.

### U6. Đổi owner giữa nhiều FlutterEngine cắt kết nối đang in

- **Vị trí:** `takeUsbOwnership` → `releaseUsbConnections`.
- **Hiện tượng:** owner là engine nghe `usbDeviceStream` gần nhất. Khi engine mới nghe stream (ví dụ engine màn hình phụ `dual_screen_view`, hoặc `MainActivity` mới mở bằng intent USB_DEVICE_ATTACHED), engine cũ bị `close()` mọi kết nối USB ngay lập tức, không chờ job đang in.
- **Hậu quả:** bill đang in trên engine cũ bị cắt giữa chừng (rơi vào U3). Lệnh in tiếp theo từ engine cũ báo `NO_CONNECTION`.
- **Sửa:**
  - Khi nhả kết nối, chờ `lockFor(conn)` (job đang gửi xong) rồi mới đóng.
  - Ghi rõ trong doc: engine phụ **không được** nghe `usbDeviceStream`.

### U7. Máy in tắt/bật nguồn mất quyền USB

- **Hiện tượng:** Android cấp quyền USB theo từng lần thiết bị được nhận diện. Máy in tắt/bật hoặc chạm cáp làm thiết bị được nhận diện lại, nên quyền mất, trừ khi người dùng đã tick "Luôn mở … khi kết nối" (đường `UsbAttachActivity`).
- **Hậu quả:** popup hệ thống bật lên giữa ca bán. Bấm "Huỷ" thì máy in không dùng được tới khi cấp lại quyền. Popup không tuỳ biến được.
- **Đã có:** `setAutoRequestUsbPermission`, `getUsbPrintersNeedingPermission`, `requestUsbPermissions`, hàng đợi xin quyền lần lượt, chờ hệ thống tự cấp quyền (`USB_SYSTEM_GRANT_WAIT_MS`).
- **Còn thiếu:**
  - Hướng dẫn triển khai: bắt buộc tick "Luôn mở" ở lần cấp quyền đầu tiên.
  - Khi in lỗi do thiếu quyền, trả mã riêng (ví dụ `USB_NO_PERMISSION`) thay cho `NO_CONNECTION` để app hiện banner xin quyền.

### U8. Máy in dùng interface class `0xFF` không được tự nhận

- **Vị trí:** `isUsbPrinter` chỉ nhận `deviceClass == 7` hoặc interface class `7`.
- **Hậu quả:** một số máy in (một vài model Xprinter/Gprinter đời cũ, máy in tem) khai báo class vendor-specific `0xFF`. Những máy này không được quét lúc mở app, không có trong `getUsbPrintersNeedingPermission`, và không phát sự kiện tạo máy in.
- **Sửa:** thêm danh sách cho phép theo vendor id (Xprinter, Gprinter, HPRT, Rongta…) hoặc theo interface có endpoint bulk OUT. Phải tránh nhận nhầm máy quét mã vạch hay ngăn kéo USB.

### U9. Báo "kết nối thành công" dù chưa ghi thử được

- **Vị trí:** nhánh `CONNECT_SUCCESS` của `makeConnectListener` cho USB.
- **Hiện tượng:** ghi thử `0x00` tối đa 5 lần. Nếu vẫn hỏng thì chỉ log rồi vẫn `complete(true)`.
- **Hậu quả:** Dart tưởng sẵn sàng, đến lần in đầu mới lỗi. Mức thấp, vì `sendAllSync` còn retry gói đầu (khoảng 2.4s).
- **Sửa:** trả `true` kèm cờ `warmUp: false`, hoặc ghi log ra Dart để chẩn đoán.

### U10. Trạng thái USB không thread-safe

- **Hiện tượng:** `usbDevicePaths`, `permissionWaiters`, `usbAttachedAt` là `mutableMapOf`, nhưng `rawId()` được đọc từ luồng in nền trong lúc main thread ghi. Còn `isDelivered` trong `checkStatus*` thì không `@Volatile`.
- **Hậu quả:** hiếm khi xảy ra, nhưng có thể gây `ConcurrentModificationException` hoặc đọc sai đường dẫn khi cắm/rút đúng lúc in.
- **Sửa:** đổi sang `ConcurrentHashMap`, dùng `AtomicBoolean` cho `isDelivered`.

---

## 4. Độ tin cậy LAN còn lại (nhóm B)

Chi tiết từng mục R ở [IN_LAN_ON_DINH.md mục 6](IN_LAN_ON_DINH.md#6-lộ-trình-sửa-code).

| Mã | Nội dung | Ưu tiên |
|---|---|---|
| B1 | **R6** – chống in rác sau khi đứt giữa chừng: bù `0x00` cho lệnh `GS v 0` gửi dở. Nên làm chung với U3 | Cao |
| B2 | **R7** – xác nhận máy in đã nhận đủ bằng `DLE EOT 1`. iOS hiện chỉ chờ 0.4s xem có bị reset không (`acceptConfirmDelay`); Android coi việc đẩy được vào buffer kernel là xong | Trung bình |
| B3 | **R5** – socket chỉ giữ 800ms (Android) / 0.6s (iOS) sau khi in. Nên tăng lên khoảng 2–3s và mở `set_lan_socket_policy` | Cao |
| B4 | **R4** – không có sự kiện tiến trình. Mạng yếu thì một lần in có thể mất 6s × 2 lần thử cộng backoff, UI im lặng nên nhân viên bấm in lại và ra 2 bill | Trung bình |
| B5 | **R9** – không có hàng đợi in bền vững phía Dart | Trung bình |
| B6 | `identify_lan_printer` (Android) dùng `java.net.Socket` thô: không `bindToLocalNetwork` (Wi-Fi không có Internet thì đi nhầm 4G), không phân loại lỗi. Nên dùng lại `LanSocketConnection` | Thấp |

---

## 5. Hợp đồng API của `PrinterLabel` (nhóm C)

| Mã | Vấn đề | Sửa |
|---|---|---|
| C1 | `printESC` / `printLabel` / `printImage` trả `Future<void>`. Native trả `false` khi sai `type`, ảnh rỗng hoặc không decode được, nhưng Dart bỏ qua giá trị đó nên app tưởng đã in | Trả `Future<bool>`, hoặc ném `PrinterException` |
| C2 | Lý do lỗi LAN (`LAN_TIMEOUT`, `LAN_BUSY`, `LAN_UNREACHABLE`, `LAN_SEND_FAILED`) chỉ nằm trong `message` / `details["reason"]` dạng chuỗi. USB không có mã riêng | `PrinterException { kind, retryable }`. Thêm `USB_NO_PERMISSION`, `USB_DETACHED`, `OUT_OF_PAPER` |
| C3 | `printESC(openDrawer: true)` gọi native hai lần riêng (mở két rồi mới in). Socket chưa mở thì phải bắt tay hai lần, và két vẫn mở dù bill lỗi | Gộp `ESC p` vào đầu dữ liệu bill trong một lần gọi `print_image_esc` |
| C4 | `openDrawer` truyền `connectionType.name`, các hàm khác truyền `.value`. Android hiện chỉ đọc `connection_type` ở `print_all` nên chưa gây lỗi | Thống nhất dùng `.value` |

---

## 6. Dọn dẹp và hiệu năng (nhóm D)

| Mã | Vấn đề |
|---|---|
| D1 | Nhánh `print_barcode_esc` / `print_qrcode_esc` bị khai báo lặp lần hai cuối `when` trong `PrinterMethodCallHandler.kt`. Đây là code chết vì `when` luôn khớp nhánh đầu |
| D2 | `checkStatusESC` / `checkStatusTSPL` trả `"normal"` khi gặp exception hoặc mã lạ; nên trả `"unknown"`. Hàm hỏi trạng thái của SDK `sleep 2000ms` trước khi đọc, trùng đúng timeout 2s của mình, nên **với LAN nhiều khả năng luôn ra `"unknown"`** (cần test) |
| D3 | **R10** – bill là ảnh raster nguyên khối. Cắt dải trắng đầu/cuối và thay dải toàn trắng bằng `ESC J n` sẽ giảm khoảng 20–40% số byte, có lợi cho cả LAN yếu lẫn USB chậm |

---

## 7. Thứ tự đề xuất

1. **Sửa nhỏ, lỗi rõ ràng:** A1, A2, U2 (timeout connect USB), U5 (không reconnect khi đang sống), D1.
2. **Bỏ hàng đợi SDK, gửi đồng bộ cho mọi lệnh:** A3, A4, A5. Sau bước này mọi đường in đều đi qua `sendAllSync`, báo đúng thành công/thất bại.
3. **Chống in rác + hết giấy:** U3 + B1 (R6), thêm hỏi `DLE EOT 4` trước khi in.
4. **Phân biệt máy in cùng model:** U1. Xprinter đã có serial riêng, chỉ làm khi gặp model không có serial.
5. **API Dart:** C1, C2, rồi U4 / U7 (mã lỗi USB, tự kết nối lại).
6. **Tối ưu LAN:** B3 (R5), B4 (R4), B2 (R7), D3 (R10), B5 (R9).

### Cách kiểm tra cho các mục USB

| Mục | Cách test |
|---|---|
| U1 | Cắm 2 máy in cùng model vào một máy POS (qua hub). Gửi bill tới từng `deviceId`, xem có ra đúng máy không |
| U2 | Cắm máy in, bấm in rồi rút dây ngay trong 1s đầu của `connectUsb`. Future phải trả `false` trong khoảng 8s |
| U3 | In bill dài rồi mở nắp hoặc kéo hết giấy giữa chừng. Đóng nắp, in bill khác: không được ra ký tự rác, và lệnh in không được treo |
| U5 | Huỷ và nghe lại `usbDeviceStream` trong lúc đang in bill dài: bill phải in trọn |
| U6 | Mở màn hình phụ có engine riêng trong lúc in: bill phải in trọn |
| A4 | In 10 tem liên tiếp qua USB: đủ 10 tem, không tem nào ra nhiễu |
