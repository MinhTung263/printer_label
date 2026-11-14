## Unreleased (dự kiến 2.5.0)

* **Chạy nền (Android):** `startKeepAlive` / `stopKeepAlive` / `isKeepAliveRunning` /
  `keepAliveStoppedByUser` — `startKeepAlive(requestPermission: true)` tự xin quyền
  thông báo (Android 13+); foreground service kiểu `connectedDevice` với thông báo cố
  định (có nút dừng), giữ CPU và Wi-Fi thức để vẫn in được khi tắt màn hình. Manifest
  plugin thêm `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `CHANGE_NETWORK_STATE`,
  `ACCESS_WIFI_STATE`, `POST_NOTIFICATIONS`.
* **`isUsbAttached(deviceId)` (Android):** biết máy in USB có đang cắm mà không kết nối /
  không hỏi quyền; nhận cả id kiểu cũ `USB:<vendor>_<product>`.
* **Quét LAN:** `discoverLanPrinters` / `discoverLanDevices` nhận `extraSubnets` để quét
  thêm dải khác; bỏ qua interface VPN (tun, ppp, ipsec, utun, wg, tap).
* **Nhận diện tên:** `discoverLanDevices(nameWait:)` chờ có tên rồi mới phát máy mới;
  `knownLanDevices` / `rememberLanDevices` để app lưu tên qua các lần mở.
* **`findLanPrinterIssues()`:** máy in lệch dải (`otherSubnet`) và IP tĩnh sai gateway
  (`wrongGateway`, kèm `suggestedGateway`). `scanNetPrinters` dùng chung kết quả
  broadcast trong 5 giây.
* **`shrinkLabelImage`:** thu ảnh hàng tem về đúng số chấm máy in (8 chấm/mm).
* **iOS — socket tới máy in không đi qua 4G:** IP nội bộ (10.x, 172.16–31.x, 192.168.x,
  169.254.x) cấm interface cellular (`prohibitedInterfaceTypes`), để Wi-Fi quán không có
  internet vẫn in được khi máy đang dùng 4G. Không ép `.wifi` để iPad cắm mạng dây vẫn in.
* **Tìm máy in Epson / Star (`scanVendorBroadcast`):** broadcast ENPC (UDP 3289) và StarIO
  (UDP 22222) và gói chung `FIND_POS_PRINTER` (UDP 3000/4000/1460/5000), gộp vào `scanNetPrinters` nên `discoverLanDevices` / `findLanPrinterIpByMac`
  dùng được cho cả hai hãng. Chưa thử trên máy thật.
* **`LanSelfTestInfo.parse`:** đọc IP / mask / gateway / MAC / DHCP từ chữ trên tờ self-test
  (VD kết quả OCR), chịu lỗi OCR thường gặp.
* **In qua trạm in (relay):** in tới máy in LAN khác mạng / máy in USB cắm ở máy khác.
  - `PrintRelay`: gói sẵn cho app — bật/tắt trạm (`setStation`, `restore`, `isStation`),
    tự chạy nền + cập nhật thông báo + nút "Dừng" (Android), phía gửi `willRelay` /
    `relay`. App chỉ cung cấp hàng đợi, cách in một lệnh và chữ trên thông báo.
  - `PrintRelayPrinter`: máy in đích (LAN/USB, `usbDeviceId`).
  - `PrintRelayJob`: lệnh in hoá đơn / tem và định dạng lưu trên hàng đợi.
  - `PrintRelayTransport`: interface kênh trao đổi; app tự cài với dịch vụ của mình
    (Firebase, server riêng...).
  - `PrintRelayStation`: nghe hàng đợi, giành lệnh (một lệnh chỉ một trạm in), bỏ lệnh
    quá hạn, bỏ qua lệnh trạm không in được (`canHandle`), đếm số lệnh đã in.
  - `PrintRelayClient`: `canPrintDirectly` (cùng dải /24, USB đang cắm), theo dõi trạm
    trực tuyến, `send` lệnh và chờ kết quả (`PrintRelayResult`).
  - `PrintRelayLanServer` / `PrintRelayLanClient`: đường nội bộ nhanh — trạm mở cổng TCP
    9101 có token ngẫu nhiên (báo qua hàng đợi), máy gửi cùng LAN gửi thẳng, không được
    thì đi hàng đợi. `PrintRelay.relay(force: true)` gửi qua trạm sau khi in thẳng lỗi.
  - `PrintRelayTransport.watchStations()` (thay `watchStationsOnline`) trả thông tin trạm.
  - `MqttPrintRelayTransport`: kênh MQTT không cần backend (mặc định `broker.emqx.io`,
    topic `easypos/print_relay/{băm}`), nội dung mã hoá AES-256-GCM, Last Will xoá trạm
    khi rớt mạng, giành lệnh theo gói `claims` đầu tiên. Đã thử thật với broker.emqx.io.
  - `PrintRelay` nhận nhiều kênh (`queues`): trạm nghe mọi kênh, máy gửi dùng kênh đầu
    tiên có trạm, lỗi thì sang kênh kế. `relayEnabled` / `setRelayEnabled` /
    `hasOnlineStation` cho nút "In qua máy trạm".
  - Máy in tích hợp của trạm: `PrintRelayPrinter.stationBuiltIn(stationId)` — lệnh mang
    `targetStation`, chỉ đúng trạm đó in (trạm khác bỏ qua, kể cả qua mạng nội bộ).
    `PrintRelay(stationId:)` + `onlineStations()` để app liệt kê trạm có máy in tích hợp.
  - Chống in trùng khi nhiều trạm: MQTT nghe gói giành lệnh ngay từ lúc lên mạng, không
    xác định được trạm thắng thì không in; đường nội bộ đã gửi lệnh thì không gửi lại
    qua hàng đợi. Đã thử 2 trạm trên broker thật: mỗi lệnh in đúng 1 lần.
* **Phụ thuộc mới:** `mqtt_client`, `encrypt`, `crypto`; Dart SDK tối thiểu 3.8.

## [2.4.1] - 2026-11-10

### 🛡️ Reliability

- **Label guard on busy printers (Android)**: When a LAN/USB printer does not answer the language probe (often because it is still busy with the previous job), the guard waits 400 ms and asks again instead of treating it as "unknown" forever. An unknown result is now only cached for 60 s, so a single missed answer no longer lets every later TSPL label job print garbage on a receipt printer.
- **Receipt-only vendors**: LAN printers from vendors that only make ESC/POS receipt printers (Epson, detected by MAC) are blocked from TSPL label commands even when they do not answer the probe.

## [2.4.0] - 2026-11-09

### 🚀 Performance

- **Faster ESC/POS raster encoding**: Integer grayscale threshold on pre-binarized rows (Android & iOS); iOS skips redrawing images that already match the printer width.
- **Faster LAN sending**: Socket send buffer raised from 512 B to 16 KB — long bills are sent about 20x faster.
- **Stable Bluetooth printing**: Data is rate-paced (120 B chunks at ~11 KB/s) so low-cost handheld printers no longer overflow and print garbage characters.
- **Quicker LAN printer names**: `getLanPrinterName` returns on the first valid answer instead of waiting for every source to time out; the ARP/OUI lookup runs in parallel. `discoverLanDevices` emits the name before the MAC, remembers names per IP for later scans, and no longer drops names of printers found at the end of the scan.

### 🛡️ Reliability

- **Sunmi built-in printer status**: Checks paper, cover and temperature through InnerPrinterService before printing and fails fast with `PRINTER_OUT_OF_PAPER`, `PRINTER_COVER_OPEN` or `PRINTER_OVERHEATED`.
- **Label commands on receipt printers**: `printLabel` refuses to send TSPL to receipt-only printers (built-in, or LAN/USB printers that answer ESC/POS but not TSPL) and returns `PRINTER_NOT_LABEL`, instead of printing garbage and feeding the whole roll. Print the label as an image instead.
- **iOS Bluetooth**: Briefly scans for peripherals with an unknown UUID before connecting.

## [2.3.0] - 2026-10-11

### 🚀 New Features & Enhancements

- **LAN Paper Status Verification**: Added `checkPaperStatus` before sending print jobs via LAN connections to detect out-of-paper or printer error conditions early.
- **LAN Socket Lifecycle Optimization**: Automatically releases and closes LAN printer sockets upon print job completion to prevent "printer busy" errors on subsequent prints.
- **Raw Byte Transmission**: Introduced `sendRawBytes` method across platforms to allow transmitting raw ESC/POS or TSPL byte buffers directly to printers.
- **USB Permission Management**: Added native USB permission checking and requesting APIs (`requestUsbPermission`, `hasUsbPermission`, `checkUsbPermission`) with improved device discovery and product name mapping on Android.
- **Network Diagnostics & Quality Check**: Introduced `checkLanQuality` and `LanQuality` model to measure latency, packet loss, and network reliability prior to transmitting print jobs.
- **Dynamic IP & Vendor Detection**: Enhanced LAN printer discovery with SNMP/NetBIOS MAC extraction, dynamic IP resolution by MAC address (`findPrinterIpByMac`), and vendor detection for Xprinter and PDIT hardware.
- **Connection Optimization**: Fine-tuned socket connection timeouts and improved error handling for concurrent and multi-printer environments.

## [2.2.3] - 2026-08-28

### 🐛 Bug Fixes & Stability Improvements

- **iOS Bluetooth Alert Handling**: Disabled automatic system Bluetooth power alert popup (`CBCentralManagerOptionShowPowerAlertKey: false`) during central manager initialization to prevent unexpected system dialogs.
- **iOS Build Optimization**: Enhanced example Xcode project settings to reduce build conflicts and improve compilation reliability.

## [2.2.2] - 2026-08-25

### 🚀 New Features & Stability Enhancements

- **In-App Bluetooth Enable Request**: Added `PrinterLabel.requestBluetoothEnable()` for Android to trigger the system dialog requesting users to turn on Bluetooth directly within the app without navigating away to Settings.
- **Concurrent Bluetooth Print Serialization**: Introduced a global Bluetooth transmission lock on Android to serialize concurrent print requests across physical Bluetooth channels, preventing data collisions when printing to built-in and external Bluetooth printers simultaneously.
- **Built-in Printer Isolation**: Refined device matching logic so external Bluetooth printers with generic names (e.g., "BluetoothPrinter") do not conflict with or override built-in POS printers (Sunmi, iMin, Pax, etc.).
- **USB Disconnection Cleanup**: Implemented automatic cleanup of pending USB permission requests and active connection state when a USB printer is disconnected (`ACTION_USB_DEVICE_DETACHED`).

## [2.2.1] - 2026-08-20

### 🐛 Bug Fixes & iOS Build Enhancements

- **iOS Build Architecture**: Removed `EXCLUDED_ARCHS` from podspec to fully support modern Xcode (Xcode 26+) builds without architectural warnings.
- **Apple Silicon Simulator Support**: Added `arm64` slice to `PrinterSDK.xcframework` simulator framework for seamless debugging on Apple Silicon Macs.
- **Runtime Class Conflict**: Removed unused `PTSettings.o` object file from `PrinterSDK` to resolve class collision with iOS system framework `PrototypeTools`.

## [2.2.0] - 2026-08-19

### 🚀 New Features & Enhancements

- **USB Printing Improvements**: Enhanced native USB printer connectivity and high-speed image printing on Android.
- **LAN Printer Network Configuration**: Added support for discovering LAN printers and configuring printer IP address, subnet mask, and gateway directly from the app (supporting POS/Xprinter network configuration protocols on both Android and iOS).
- **Multiple Copies Printing**: Added support for printing multiple copies (`copies` parameter) in ESC/POS thermal printing service and native platforms.
- **Multi-Device & Cash Drawer Enhancements**:
  - Enhanced `openDrawer()` API to return execution status (`Future<bool>`).
  - Added target `deviceId` parameter and support for broadcasting drawer open commands across all connected LAN and Bluetooth printers.
  - Added `openDrawerMultiDevices` in `ESCPrintService`.
- **LAN & Bluetooth Stability**:
  - Enhanced LAN printing with socket connection pooling and batch image data transmission.
  - Improved Bluetooth BLE streaming and long-ticket print flow pacing.
  - Refined image binarization threshold for crisp print output across both iOS and Android.

## [2.1.1] - 2026-07-03

### 🚀 Core Architecture & Package Restructuring

- **PlatformInterface Restructuring**: Redesigned and restructured package services to align with Flutter's recommended `PlatformInterface` layout for clean separation of concerns and stable cross-platform method channel behavior.
- **Modular Native Code**: Modularized native Android side, simplified the MethodChannel enum, and added multi-brand POS device detection/support.
- **API Simplifications**: Simplified `printLabels` API signature and cleaned up compiler warnings across the codebase. Removed the redundant `Dimensions` helper class.

### 📶 Connection Management & Discovery

- **Connection Diagnostics**: Implemented `checkPrinterStatus` and added connection verification for LAN and Bluetooth devices prior to actual print actions.
- **Smart BLE Features**: Added Bluetooth enabled checks across platforms. On iOS, implemented reconnect functionality for BLE printers without needing a full device scan. Optimized BLE connection timeout to 5s.
- **Reliable USB Discovery**: Implemented automatic USB device scanning at app startup and improved USB identification by saving and mapping raw USB device IDs.
- **Error Isolation & Retry**: Implemented automatic retry on LAN/Wi-Fi socket write failure and isolated connection failures when using concurrent multiple printer execution.

### 🖨️ Android & iOS Native Printing Optimizations

- **Automatic Command Set Detection**: Implemented automatic printer command set validation and detection (e.g. automatically verifying ESC/POS vs TSPL) to prevent corrupt commands.
- **BLE Write Flow Pacing (iOS)**: Optimized iOS Bluetooth print flow by restricting write chunk sizes to a safe limit of 180 bytes and implementing a dynamic pacing delay (16 KB/s) to prevent printer buffer overflows and motor starvation.
- **High-Contrast Binarization**: Developed custom integer-based luminance algorithm (threshold 200) to force light/transparent pixels to white and dark pixels to solid black, resolving blurry text/barcodes on iOS and Android.
- **Image Resizing & Precision Mapping**:
  - Android: Enabled dynamic target width calculation based on physical dot calculations (`sizeWidth * 8`).
  - iOS: Implemented native `CGImage` scaling/resizing to fit exact physical print width. Adjusted `startX` coordinate (subtracted 20 dots) on iOS to prevent right-shifting on 1-label templates.
  - Corrected gap size and bitmap width on TSPL printing to eliminate label misalignment.

### ⚡ Performance & Rendering Speed

- **Parallel Image Capture**: Drastically improved print rendering performance by capturing multiple widget layouts in parallel using `Future.wait`.
- **Pixel-Perfect Widget Capturing**: Optimized pixel-perfect 1:1 widget capturing and stabilized Bluetooth delays.
- **Direct Widget Printing**: Improved widget capture and added support for direct widget printing.

### 📱 Example App Redesign & Documentation

- **UX & UI Redesign**: Fully overhauled and split the example dashboard app features into separate modular tab files.
- **Instant Preview**: Implemented instant widget print preview to see layout changes before printing.
- **Interactive Redesigns**: Redesigned the Cup Sticker tab UI, merged bluetooth scan/connect flows into a smart single-entry button, unified top-sliding snackbars, and optimized Bluetooth filtering.
- **Documentation**: Overhauled `README.md` with updated screenshots (devices, labels, receipts, cup stickers) hosted directly on raw GitHub for pub.dev compatibility.

## [2.1.0] - 2026-05-25

- Add Bluetooth connection support for iOS
- Support multiple printer connections

## [2.0.9] - 2026-04-9

- Fix connect USB

## [2.0.8] - 2026-01-22

- Fixed app crash when connecting to printer on Android 6

## [2.0.7] - 2026-01-19

- Fixed app crash when connecting to printer on Android

## [2.0.6] - 2026-01-15

- Bug fixes and minor improvements

## [2.0.5] - 2026-01-15

- Bug fixes and minor improvements

## [2.0.4] - 2026-01-15

- Bug fixes and minor improvements

## [2.0.3] - 2026-01-12

- Bug fixes and minor improvements

## [2.0.2] - 2026-01-12

- Fixed issue where printing two labels in one row did not work correctly

## [2.0.1] - 2026-01-08

- Add run with Simulator
- Config print Cup Sticker
- Fix other bug

## [2.0.0] - 2026-01-07

New Features

- Added support for printing on iOS.

- Improvements

- Refactored and reconfigured print styles.

Added print size configuration options.

## [1.0.10] - 2025-10-03

- Upgrade fvm 3.35.4, intl 0.20.2

## [1.0.9] - 2025-09-22

Network Connectivity

- Fixed LAN connection issues on Android devices.

## [1.0.8] - 2025-06-28

- Fixed installation issue on devices that do not support USB host feature.

## [1.0.7] - 2025-03-11

- downgrade intl: ^0.19.0

## [1.0.6] - 2025-03-11

- Fix print only android

## [1.0.5] - 2025-03-07

- Added thermal printer result output.

## [1.0.4] - 2025-03-05

- Fix connect USB

## [1.0.3] - 2025-02-26

Bug Fixes

- Fixed USB connection issues.
- Added automatic USB connection configuration.

- Implemented connection status checking.

## [1.0.0] - 2025-02-05

Initial Release

- First public release.
