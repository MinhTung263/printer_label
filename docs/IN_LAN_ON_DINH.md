# In LAN ổn định khi Wi-Fi quán đông khách

Tài liệu này dành cho hai nhóm người đọc:

- **Đội triển khai / CSKH**: đọc mục 1–4, gồm nguyên nhân, checklist hạ tầng tại quán, cách kiểm tra nhanh khi khách báo lỗi.
- **Dev của plugin**: đọc thêm mục 5–7, gồm chẩn đoán trong code, lộ trình sửa và cách giả lập mạng xấu để test.

> Quy ước: tên hàm và hằng số tham chiếu theo mã nguồn tại thời điểm viết (cập nhật 2026-09-30). Cơ chế chia sẻ socket LAN đã có
> được giải thích kỹ ở [PRINTING_FLOW.md mục 6](PRINTING_FLOW.md#6-android--kết-nối-lan-giải-thích-cơ-chế-chia-sẻ-socket)
> (Android) và [mục 12](PRINTING_FLOW.md#12-ios--kết-nối-lan-giải-thích-cơ-chế-xác-nhận--retry) (iOS).

---

## Mục lục

1. [Tóm tắt](#1-tóm-tắt)
2. [Vì sao Wi-Fi đông làm in LAN hỏng](#2-vì-sao-wi-fi-đông-làm-in-lan-hỏng)
3. [Checklist hạ tầng tại quán](#3-checklist-hạ-tầng-tại-quán)
4. [Kiểm tra nhanh khi khách báo lỗi](#4-kiểm-tra-nhanh-khi-khách-báo-lỗi)
5. [Chẩn đoán kỹ thuật trong code](#5-chẩn-đoán-kỹ-thuật-trong-code)
6. [Lộ trình sửa code](#6-lộ-trình-sửa-code)
7. [Giả lập mạng xấu để test](#7-giả-lập-mạng-xấu-để-test)

---

## 1. Tóm tắt

- Giờ cao điểm, rất nhiều điện thoại của khách cùng dùng một Wi-Fi. Sóng bị chiếm dụng, gói tin rớt hoặc trễ hàng giây, nên kết nối từ điện thoại/tablet POS tới máy in LAN bị đứt quãng.
- Để **nhiều thiết bị dùng chung một máy in**, app mở kết nối mới cho mỗi lần in rồi nhả ra. Vì vậy mạng càng chập chờn thì càng dễ lỗi ở bước kết nối.
- **Cách hiệu quả nhất là xử lý hạ tầng** (mục 3). Phần mềm chỉ giúp app chịu được mạng chập chờn tốt hơn (mục 6), chứ không làm Wi-Fi quá tải hết quá tải.

---

## 2. Vì sao Wi-Fi đông làm in LAN hỏng

Giải thích bằng lời thường, để CSKH nói lại với khách:

1. **Mỗi lần in, điện thoại phải "bắt tay" lại với máy in.** Máy in LAN chỉ cho một thiết bị in tại một thời điểm. App phải kết nối, in xong rồi buông ra ngay để thiết bị khác còn in được. Khi Wi-Fi nghẽn, cái bắt tay đầu tiên hay bị rớt. Điện thoại phải chờ khoảng 1 giây mới gửi lại lời bắt tay. Trên **Android**, thư viện máy in chỉ chờ đúng **1 giây**, nên chưa kịp gửi lại đã coi là lỗi. Mạng chỉ cần trễ quá 1 giây một lúc là không kết nối được, dù mạng vẫn dùng được.
2. **Hai thiết bị in cùng lúc thì một thiết bị phải xếp hàng.** Mạng chậm thì thiết bị đang in giữ máy in lâu hơn, thiết bị kia chờ lâu hơn và dễ báo "máy in bận".
3. **Đứt mạng giữa chừng thì bill sau có thể in ra ký tự rác.** Bill được gửi dưới dạng ảnh, khoảng 100–200KB. Nếu đứt giữa chừng, máy in vẫn đứng chờ nốt phần ảnh còn thiếu và "ăn" luôn phần đầu của bill tiếp theo.
4. **App báo in thành công nhưng không ra giấy, hoặc giấy ra trễ.** App chỉ biết dữ liệu đã rời khỏi điện thoại, chứ chưa chắc máy in đã nhận đủ. Trên **iPhone/iPad**, app báo "in xong" **ngay khi bấm**, rồi mới âm thầm thử gửi trong khoảng 20 giây. Mạng có lại trong khoảng đó thì bill **ra trễ**; nhân viên đã bấm in lại thì ra **2 bill**; mạng mất lâu hơn thì bill **mất hẳn** mà không ai biết.
5. **Điện thoại Android tự làm khó thêm.** Chế độ tiết kiệm pin cho Wi-Fi "ngủ" giữa các lần gửi. Khi thấy Wi-Fi "không có Internet", máy còn tự chuyển sang 4G, và lúc đó không tới được máy in trong mạng nội bộ.

---

## 3. Checklist hạ tầng tại quán

Mức độ: **[BẮT BUỘC]** là không làm thì gần như chắc chắn lỗi giờ cao điểm. **[NÊN]** là cải thiện rõ rệt.

| # | Việc cần làm | Mức |
|---|---|---|
| 1 | **Máy in cắm dây LAN** thẳng vào router/switch. Không dùng Wi-Fi của máy in. | BẮT BUỘC |
| 2 | **Tách Wi-Fi**: một mạng riêng cho POS/nhân viên (có mật khẩu, không đưa khách, ưu tiên băng **5GHz**) và một mạng riêng cho khách. | BẮT BUỘC |
| 3 | Trên mạng khách: **giới hạn băng thông mỗi thiết bị** (ví dụ 2–5 Mbps) và **bật cách ly client** (client isolation / AP isolation). | NÊN |
| 4 | Nếu router hỗ trợ: tách **VLAN** cho POS và cho khách. | NÊN |
| 5 | **Gán IP cố định cho máy in**: đặt DHCP reservation trên router theo MAC máy in, hoặc đặt IP tĩnh **ngoài** dải DHCP. Như vậy máy in không đổi IP sau khi khởi động lại. | BẮT BUỘC |
| 6 | Quán rộng, nhiều tầng hoặc có bếp riêng: dùng **AP riêng hoặc mesh** cho quầy và bếp. Không đặt router trong tủ kim loại, sát lò vi sóng hay tủ lạnh. | NÊN |
| 7 | Máy POS cố định (quầy thu ngân): **cắm dây LAN**, hoặc in qua **USB** nếu máy in đặt ngay cạnh. | NÊN |
| 8 | Trên điện thoại/tablet Android dùng để in: **tắt tối ưu pin** cho app bán hàng; **tắt "tự chuyển sang dữ liệu di động"** (tên khác nhau theo hãng: "Wi-Fi+", "Chuyển mạng thông minh", "Adaptive Wi-Fi"...). Nếu Wi-Fi POS không có Internet thì chọn "Giữ kết nối" khi máy hỏi. | BẮT BUỘC |
| 9 | Giới hạn số thiết bị cùng in vào **một** máy in. Bếp/bar đông thì dùng 2 máy in tách theo khu. | NÊN |

---

## 4. Kiểm tra nhanh khi khách báo lỗi

### 4.1. Ping máy in từ đúng vị trí thiết bị POS

Dùng laptop cùng mạng (`ping -c 100 <IP máy in>`) hoặc app **PingTools** / **Fing** trên điện thoại. Nên đo **vào giờ cao điểm**.

| Kết quả ping | Đánh giá |
|---|---|
| Trễ trung bình < 50ms, max < 200ms, mất gói 0% | Mạng tốt. Lỗi có thể nằm ở máy in, IP hoặc app. |
| Trễ trung bình 50–200ms hoặc mất gói 1–5% | Mạng yếu, sẽ lỗi lác đác giờ cao điểm. Làm mục 3. |
| Trễ > 200ms, max > 1000ms hoặc mất gói > 5% | Mạng quá tải, in LAN sẽ lỗi thường xuyên. **Bắt buộc** làm mục 3 #1, #2, #5. |
| Không ping được | Sai IP, máy in tắt, hoặc thiết bị không cùng mạng với máy in. |

### 4.2. Kiểm tra IP máy in

- In **trang tự kiểm tra (self-test)**: thường là giữ nút FEED khi bật nguồn. Trang này in ra IP hiện tại của máy in. So với IP đang cài trong app.
- Dùng tính năng quét / nhận diện máy in LAN có sẵn trong app (`PrinterLabel.identifyLanPrinter`). Máy in đúng IP sẽ in ra một mẩu giấy nhận diện.

### 4.3. Triệu chứng → nguyên nhân → cách xử lý

| Triệu chứng | Nguyên nhân thường gặp | Xử lý |
|---|---|---|
| "Máy in đang bận" | Thiết bị khác đang in, hoặc mạng chậm làm thiết bị kia giữ máy in lâu | Chờ vài giây rồi in lại; giảm số thiết bị dùng chung (mục 3 #9); làm mục 3 #2 |
| "Không kết nối được máy in" | Sai IP (máy in đổi IP), máy in tắt, điện thoại đã chuyển sang 4G hoặc đang ở mạng khách | Kiểm IP (4.2); gán IP cố định (3 #5); kiểm điện thoại đang ở đúng Wi-Fi POS; tắt tự chuyển mạng (3 #8) |
| Bill in ra ký tự rác, **thường là bill ngay sau một lần lỗi** | Lần in trước bị đứt giữa chừng, máy in còn dữ liệu dở | Tắt/bật máy in để xóa bộ đệm; xử lý mạng (mục 3) để hết đứt giữa chừng |
| App báo in OK nhưng không ra giấy | Dữ liệu chưa tới được máy in (mạng đứt ngay sau khi gửi), hoặc thiết bị khác đang giữ máy in | Kiểm mạng (4.1); in lại |
| Giờ vắng in tốt, giờ cao điểm lúc được lúc không | Wi-Fi quá tải | Mục 3 #1, #2, #3 |
| Bấm in không thấy ra, lúc sau ra **2 bill** (hay gặp trên iPhone/iPad) | Mạng mất vài giây; app vẫn âm thầm gửi lại bill đầu, trong khi nhân viên đã bấm in lại | Dặn nhân viên chờ khoảng 20–30 giây trước khi bấm in lại; xử lý mạng (mục 3). Lỗi phần mềm, đang sửa (mục 6, R2) |
| In được một lúc thì mất hẳn, khởi động lại máy in mới in được | Máy in đổi IP (DHCP) hoặc máy in bị treo | Gán IP cố định (3 #5); cập nhật firmware máy in nếu có |

---

## 5. Chẩn đoán kỹ thuật trong code

### 5.1. Tổng hợp vấn đề

| # | Vấn đề | Vị trí | Vì sao Wi-Fi đông làm hỏng | Mức |
|---|---|---|---|---|
| 1 | **iOS "gửi rồi quên": báo thành công ngay khi bấm in** (xem 5.4) | `ESCPosPrinter.swift` (`printImageESC`), `PrinterLabelPlugin.swift` (`sendToPrinter`) | Báo OK giả; bill in trễ, in trùng, hoặc mất âm thầm sau khoảng 23s | **Rất cao** |
| 2 | **SDK Android chỉ chờ kết nối 1 giây, mỗi lần thử chỉ gửi được 1 SYN** (xem 5.2, T1–T2) | `printer-lib-3.2.0.aar` (`net/posprinter/a/b.class`), `PrinterLabelPlugin.kt` (`ensureLanConnectedSync`) | Mất một gói SYN, hoặc mạng trễ vọt quá 1 giây, là lần thử đó hỏng | **Rất cao** |
| 3 | **SDK Android bóp bộ đệm gửi còn 512 byte; lệnh ghi không có giới hạn thời gian** (xem 5.2, T3–T4) | như trên | Mạng trễ thì gửi rất chậm, dễ đứt giữa chừng; mạng chết lúc đang gửi thì luồng in có thể treo, kéo theo mọi bill sau | Cao |
| 4 | **Mở socket TCP mới cho mỗi lần in.** `releaseLanSocketAfterPrint = true`; socket đóng sau `LAN_IDLE_CLOSE_DELAY_MS = 800ms` rảnh. iOS: `releaseSocketWhenIdle = true`, `idleCloseDelay = 0.6s` | `PrinterLabelPlugin.kt` (`releaseLanSocket`), `LANPrinterConnection.swift` | Số lần bắt tay bằng số bill; mỗi lần bắt tay là một lần có thể hỏng như #2 | Trung bình |
| 5 | **Đứt giữa chừng không có bước phục hồi.** `sendAllSync` chỉ retry gói đầu (offset 0); từ gói thứ 2 trở đi thì ném `IOException` ngay | `PrinterThermal.kt` (`sendAllSync`, `retryFirstChunkSync`) | Máy in đang chờ đủ byte của lệnh `GS v 0` nên nuốt phần đầu bill sau. `ESC @` ở đầu bill mới (cả Android lẫn iOS `isFirstJobOnSocket`) **bị nuốt như dữ liệu ảnh**, nên không cứu được | Cao |
| 6 | **Không phát hiện được kết nối đã chết; kết nối nửa mở giữ máy in** (xem 5.2 T5, 5.3) | SDK (`isConnect()`), máy in | App gửi vào socket chết mà vẫn thấy "thành công"; thiết bị khác bị "máy in bận" tới khi tắt/bật máy in | Cao |
| 7 | **Dữ liệu in nặng.** Cả bill là ảnh raster: khổ 80mm = 576 dots = 72 byte/dòng × hàng nghìn dòng, chia dải 128 dòng, gửi gói 4096 byte | `PrinterThermal.kt` (`getEscPosRasterBytes`) | Càng nhiều byte đi trên mạng yếu thì càng dễ đứt và càng chậm | Thấp |
| 8 | **Android: không có WifiLock, không kiểm tra mạng.** Wi-Fi có thể vào chế độ tiết kiệm năng lượng; hệ điều hành có thể chuyển mạng mặc định sang 4G | Không có trong `AndroidManifest.xml` / code | Trễ thêm hàng trăm ms; socket tới `192.168.x.x` đi nhầm mạng rồi thất bại, app vẫn retry vô ích | Trung bình |
| 9 | **Không báo cho người dùng biết mạng yếu.** In chậm hay đang thử lại thì app im lặng | Dart + native | Nhân viên tưởng app treo nên bấm in lại → in trùng | Trung bình |
| 10 | **Không có hàng đợi in bền vững.** In lỗi thì chỉ trả lỗi về Dart | `PrinterMethodCallHandler.kt` (`runPrintJob`) | Nhân viên phải bấm in lại tay, dễ quên hoặc in trùng | Trung bình |

### 5.2. SDK Android đặt cứng thông số socket

Dịch ngược `android/libs/printer-lib-3.2.0/classes.jar` bằng `javap -c -p net/posprinter/a/b.class`. Hàm mở cổng Ethernet làm như sau:

```java
socket = new Socket();
socket.connect(new InetSocketAddress(ip, 9100), 1000);   // chờ kết nối: 1 GIÂY, cổng cố định 9100
socket.setSendBufferSize(512);                            // bộ đệm gửi: 512 BYTE
out = socket.getOutputStream(); in = socket.getInputStream();
// không có setSoTimeout / setKeepAlive / setTcpNoDelay
isConnect() = socket.isConnected()                        // true mãi kể từ khi đã connect được
```

| Mã | Phát hiện | Hệ quả khi Wi-Fi đông |
|---|---|---|
| T1 | **Thời gian chờ kết nối thật là 1s.** `CONNECT_TIMEOUT_MS` của app (lịch sử: 10s → 5s ở `a0cf52d` → 3s ở `409c7ce`) chỉ là lớp chờ bọc ngoài; SDK đã báo `CONNECT_FAIL` sau 1s | Android gửi lại SYN sau khoảng 1s, nên **mỗi lần thử chỉ gửi được đúng 1 gói SYN**. Wi-Fi đông hay có trễ vọt quá 1s, nên **mọi lần thử đều hết giờ** dù không mất gói nào. Đổi `CONNECT_TIMEOUT_MS` **không có tác dụng** với LAN |
| T1b | `CONNECT_TIMEOUT_MS` dùng chung cho BT/USB/LAN | Hạ xuống 3s có thể làm Bluetooth classic (thường mất 2–5s để kết nối) bị báo timeout nhầm. Nên tách hằng số theo loại kết nối |
| T2 | **Retry là tạo device mới, và mỗi lần vẫn chỉ 1 SYN.** 4 lần × 1s cộng backoff 2.8s ≈ 7s | Mất 10% gói thì mỗi lần thử hỏng khoảng 19%, 4 lần đều hỏng khoảng 0.13%. Mất 30% thì khoảng 51% mỗi lần, **khoảng 7% bill không kết nối được**. Trễ vọt quá 1s kéo dài vài giây thì **hỏng 100%** |
| T3 | **Bộ đệm gửi 512 byte.** Linux làm tròn lên mức tối thiểu khoảng 4.6KB | Tốc độ gửi ≈ 4.6KB / RTT. RTT 5ms ≈ 900KB/s; **RTT 300ms ≈ 15KB/s, bill 150KB mất khoảng 10s**. *Ước lượng lý thuyết; đo bằng `lan_relay.py` (cột KB/s) ở kịch bản S2* |
| T4 | **Lệnh ghi không có giới hạn thời gian** (không `setSoTimeout`, không keepalive) | Mạng chết khi bộ đệm đầy thì `OutputStream.write` bị chặn tới khi kernel bỏ cuộc (`tcp_retries2`, cỡ 15 phút). Luồng in treo **và vẫn giữ `synchronized(lockFor(conn))`**, nên mọi bill sau tới máy in đó treo theo. *Cần xác nhận bằng S3/S4* |
| T5 | **`isConnect()` không phát hiện được máy in đã mất** | Socket chết im lặng (máy in rút điện, Wi-Fi rớt mà không có RST) vẫn bị coi là sống. Byte vào bộ đệm vẫn "thành công", dẫn tới báo OK mà không ra giấy |
| T6 | Hàm hỏi trạng thái của SDK `sleep 2000ms` rồi chạy `ping -c 1 -w 5` | Không dùng đường này để kiểm tra kết nối trên mạng yếu: chậm tới 7s |

### 5.3. Kết nối nửa mở

- Máy in chỉ in cho **1 kết nối** tại một thời điểm. Kết nối phụ được accept nhưng bị đóng khi có byte tới.
- Điện thoại mất Wi-Fi hẳn giữa lúc in (rớt sóng, chuyển AP) thì không gửi được FIN/RST. Máy in vẫn tưởng kết nối cũ còn sống và giữ kênh in, vì hầu hết máy in nhiệt không bật keepalive.
- Hậu quả: **mọi thiết bị khác bị "máy in bận" cho tới khi máy in tự hết giờ, hoặc phải tắt/bật máy in**. Khớp với triệu chứng "phải khởi động lại máy in mới in được" ở mục 4.3.

### 5.4. iOS: "gửi rồi quên"

Các lệnh `print_image_esc` (bill), `print_label` (tem), `print_text`, `print_barcode`, `print_qrcode`, `open_drawer` (mở két) đều đi qua `sendToPrinter` ([PrinterLabelPlugin.swift](../ios/Classes/PrinterLabelPlugin.swift)). Hàm này chỉ **xếp job vào hàng đợi** của `LANPrinterConnection`, rồi trả `result(true)` về Dart **ngay lập tức**. Lỗi chỉ được ghi log `❌ LAN write failed`.

```swift
// ESCPosPrinter.swift — in bill
self.plugin?.sendToPrinter(data, deviceId: deviceId, connectionType: connectionType)
result(true)   // báo "in thành công" trước khi biết in được hay không
```

Trong lúc đó `LANPrinterConnection` tự thử lại:

| Thời điểm (mạng mất hẳn) | Chuyện gì xảy ra |
|---|---|
| 0s | Bấm in → Dart nhận `true` ngay → **không báo lỗi** |
| 0–4s | Kết nối lần 1, hết giờ sau `connectionTimeout = 4` |
| … | Thử lại 4 lần nữa, cách nhau 0.4s / 0.4s / 0.8s / 1.6s, mỗi lần chờ 4s |
| **khoảng 23s** | Hết lượt (`maxAttempts = 4`) → **bỏ job**, chỉ ghi log. Mất bill, không ai biết |

- Mạng có lại trước khoảng 23s thì bill **in trễ**. Nếu đã bấm in lại thì ra **2 bill**.
- Chỉ riêng `identify_lan_printer` (nút "In test", "Nhận diện máy") chờ kết quả thật. Nhưng nút đó mất khoảng 23s, cộng thêm 2s dự phòng bằng socket Dart, tức **khoảng 25s** mới báo lỗi.
- Mốc 23s tính từ code. Đã tái hiện hành vi "không báo lỗi, mạng có lại thì in ra" bằng `lan_lab.sh on dead sim` trên iOS Simulator (mục 7.5).

---

## 6. Lộ trình sửa code

Mặc định cho kịch bản **nhiều thiết bị dùng chung một máy in**: vẫn nhả socket sau khi in, nhưng giữ lâu hơn.

> **Trạng thái (2026-09-30):** **R1, R2, R3 đã làm** (build Android/iOS thành công, **chưa test trên thiết bị thật** với `lan_lab.sh`). R4–R10 chưa làm.
> - R1: [`LanSocketConnection.kt`](../android/src/main/kotlin/com/printer/printer_label/LanSocketConnection.kt), kèm WifiLock + `bindSocket` (một phần R8) và RST khi lỗi (một phần R6).
> - R2: `sendToPrinter(..., completion:)` / `sendAndReply` trong [`PrinterLabelPlugin.swift`](../ios/Classes/PrinterLabelPlugin.swift); `connectionTimeout` 6s, hết giờ chỉ thử lại 1 lần, xử lý `.waiting`.
> - R3: [`LanQuality`](../lib/src/models/lan_quality.dart) / `PrinterLabel.checkLanQuality`; app example đo trước khi "In test".

| Mã | Thay đổi | Giải quyết | Ưu tiên | Rủi ro |
|---|---|---|---|---|
| R1 | **Android tự quản lý socket LAN, bỏ qua SDK**: lớp `LanSocketConnection` (`java.net.Socket`), `connect` 6–7s (nhiều SYN mỗi lần thử), `tcpNoDelay`, `keepAlive`, **không** thu nhỏ bộ đệm gửi, watchdog cho lệnh ghi (kẹt quá N giây thì `close()` để nhả khóa), liveness thật (không dựa vào `isConnected()`), gắn socket vào mạng Wi-Fi bằng `network.bindSocket()`. Đường ESC đã tự dựng byte nên đổi dễ; đường TSPL cần bọc `IDeviceConnection` hoặc tự dựng lệnh TSPL. Lớp chờ bọc ngoài (`CONNECT_TIMEOUT_MS` cho LAN) phải **lớn hơn** timeout bên trong, ví dụ 8s | #2, #3, #6, #8 | **Cao nhất** | Trung bình |
| R2 | **iOS trả kết quả thật về Dart**: `sendToPrinter` với LAN chờ completion của `LANPrinterManager.send` rồi mới `result(...)`, giống `identify_lan_printer`. *Hạn tổng cho mỗi job và việc gỡ job quá hạn khỏi hàng đợi (chống in trễ/in trùng) để sau* | #1 | **Cao** | Thấp |
| R3 | **Báo mạng yếu cho người dùng**: `PrinterLabel.checkLanQuality(ip)` viết bằng Dart thuần: đo bắt tay TCP tới 9100 khoảng 5 lần, không gửi byte, chạy cả Android và iOS. Trả mức 🟢 Tốt (trung vị < 100ms, không lỗi) / 🟡 Yếu (100–500ms hoặc 1/5 lỗi) / 🟠 Rất yếu (> 500ms, có lần > 1000ms, hoặc từ 2/5 lỗi) / 🔴 Mất kết nối (5/5 lỗi). Hiện huy hiệu trên thẻ máy in, cảnh báo trước khi in; in quá 3s thì hiện "Đang chờ máy in (mạng yếu)…". **Chỉ đo khi cần** (mở màn in, trước khi in), vì mỗi lần đo chiếm máy in vài chục ms | #9 | **Cao** | Thấp |
| R4 | **Sự kiện tiến trình job** qua `EventChannel` (đang kết nối / thử lại lần n / đã gửi / lỗi) cho cả hai nền tảng, để UI hiện "Đang thử kết nối lại (lần 2/5)". Trên iOS làm được mà chưa cần đổi hành vi "gửi rồi quên" | #1, #9 | Trung bình | Thấp |
| R5 | Tăng thời gian chờ trước khi nhả socket từ 800ms/0.6s lên khoảng **3s**, để bill in liên tiếp dùng lại socket. Mở `set_lan_socket_policy {release, idle_ms}` để quán chỉ có 1 máy POS giữ socket thường trực (khi đó bắt buộc có liveness ở R1/R7) | #4 | Cao | Thấp: thiết bị khác chờ thêm tối đa khoảng 3s |
| R6 | Chặn in rác sau khi đứt giữa chừng: ghi nhớ lệnh `GS v 0` đang gửi dở và số byte còn thiếu (theo IP). Lần kết nối sau thì **gửi bù đủ số byte `0x00`** rồi mới gửi `ESC @` và bill mới. TSPL: gửi `CLS` trước khi in. Đóng socket lỗi bằng RST (`SO_LINGER 0`) để máy in nhả kênh in ngay. *Hành vi xóa bộ đệm khi TCP đóng khác nhau theo model máy in, kiểm bằng S4* | #5, #6 | Cao | Trung bình: chỉ biết số byte thiếu khi chính thiết bị này gửi dở |
| R7 | Sau mỗi bill ESC, gửi `DLE EOT 1` (`10 04 01`) và chờ 1 byte phản hồi (khoảng 1.5–3s tùy RTT). `DLE EOT` là lệnh thời gian thực và TCP giữ đúng thứ tự, nên có phản hồi nghĩa là máy in **đã nhận đủ** mọi byte trước đó (đã nhận, chưa chắc đã in xong). Không có phản hồi thì trả mã `PRINT_UNCONFIRMED`. Tái dùng socket rảnh hơn khoảng 5s thì hỏi `DLE EOT` trước. iOS: thay việc chờ `acceptConfirmDelay = 0.4s` bằng cơ chế này | #1, #6 | Trung bình | Trung bình: vài card mạng không trả lời `DLE EOT`, cần bật/tắt được |
| R8 | Android: giữ `WifiLock` (`WIFI_MODE_FULL_LOW_LATENCY` từ API 29, còn lại `WIFI_MODE_FULL_HIGH_PERF`) trong lúc in LAN, thêm quyền `WAKE_LOCK`. Kiểm IP máy in có cùng subnet với Wi-Fi không; nếu không thì báo "Thiết bị không cùng mạng với máy in" | #8 | Cao | Thấp |
| R9 | `LanPrintQueue` phía Dart, lưu job xuống file. Lỗi kết nối (chưa gửi byte nào) thì **tự retry**. Lỗi giữa chừng hoặc `PRINT_UNCONFIRMED` thì **không tự in lại** (tránh in trùng bill bếp), mà đánh dấu "cần kiểm tra" và cho in lại có ghi chú **"BẢN IN LẠI"** | #10 | Trung bình | Cao: thay đổi lớn |
| R10 | Giảm dung lượng: cắt dải trắng đầu/cuối bill; thay dải toàn trắng bằng lệnh feed `ESC J n` | #7 | Thấp | Thấp |

**Code cải thiện được tới đâu:**

| Mức mạng | Hiện tại | Sau khi sửa |
|---|---|---|
| Tốt | In tốt | In tốt |
| Yếu nhưng còn dùng được (`s1`–`s2`) | Lỗi thường xuyên trên Android | Gần như in được hết, chỉ chậm vài giây (R1). **Đây là khoảng cải thiện lớn nhất** |
| Chập chờn (`flap`) | Mất bill, in rác, in trễ | Không in được trong lúc mất mạng, nhưng không mất bill, không in rác, báo đúng (R2, R4, R6, R9) |
| Quá tải (`s3`, `dead`) | Lỗi hoặc im lặng | Vẫn lỗi, nhưng báo nhanh và rõ (R3). Phải xử lý hạ tầng (mục 3) |

---

## 7. Giả lập mạng xấu để test

Muốn biết một thay đổi có thật sự giúp ích hay không thì phải **tái hiện được lỗi ngay tại văn phòng**. Mục này có lệnh copy chạy được, kèm lệnh **tắt/khôi phục** cho từng cách.

> **Cách nhanh nhất trên Mac:** dùng bộ công cụ [`tools/lan_lab/`](../tools/lan_lab/), xem [7.2-B](#b-mac--bộ-công-cụ-toolslan_lab-android-và-ios-cách-nhanh-nhất). Mac chỉ cần Wi-Fi. Kết quả đã đo ở [7.5](#75-kết-quả-đo-tại-văn-phòng).

### 7.0. Đo mạng thật của quán trước

Nên đo trước để chọn thông số giả lập sát với thực tế. Đo vào **giờ cao điểm** và **giờ vắng**, từ đúng vị trí đặt thiết bị POS:

```bash
ping -c 200 -i 0.2 <IP máy in>
# Ghi lại: avg, max, mdev (độ dao động), % packet loss
# Có chuỗi nhiều gói liên tiếp "Request timeout" nghĩa là mạng chập chờn, không chỉ chậm
```

Quy đổi số đo ra thông số giả lập (tham khảo):

| Số đo ở quán | Mức | Mức `lan_lab.sh` (Mac) | Thông số `netem` (Linux, cách C/D) | Kịch bản |
|---|---|---|---|---|
| avg < 20ms, loss 0% | Tốt | Không cần giả lập | – | – |
| avg 30–100ms, mdev 20–50ms, loss 1–3% | Đông vừa | `s1` | `delay 80ms 40ms distribution normal loss 2%` | S1 |
| avg > 150ms, max > 1000ms, loss 5–15% | Rất đông | `s2` (+ `spike` cho trễ vọt) | `delay 300ms 150ms distribution normal loss 10% 25% rate 2mbit` | S2 |
| avg > 300ms, loss > 15% | Cực đông / quá tải | `s2x`, `s3` | `delay 600ms 300ms loss 20%` | S2x |
| Có đoạn mất liên tiếp vài giây | Chập chờn | `flap` | Script `flap.sh` (7.2-C) | S3 |

### 7.1. Chọn cách giả lập

| Cách | Android | iOS | Trễ | Mất gói | Rớt SYN | Mất mạng hẳn | Độ khó |
|---|---|---|---|---|---|---|---|
| A. Network Link Conditioner trên iPhone | – | ✔ | ✔ | ✔ | – | ✔ | Dễ nhất |
| B. Mac + `tools/lan_lab/` (`dnctl`/`pfctl`) | ✔ | ✔ | ✔ | ✔ | ✔ (`syn`) | ✔ | **Dễ, khuyến nghị để bắt đầu.** Mac chỉ cần Wi-Fi |
| C. Raspberry Pi/Linux làm cầu nối + `tc netem`, chen giữa máy in và switch | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | Trung bình. Sát thực tế nhất: không có bộ chuyển tiếp chen giữa |
| D. Router OpenWrt + `tc netem` | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | Cần router OpenWrt |
| E. Làm nghẽn Wi-Fi thật bằng `iperf3` | ✔ | ✔ | Nghẽn sóng thật | ✔ | ✔ | – | Dễ, cần 3–4 máy |
| F. Máy in giả `fake_printer.py` | ✔ | ✔ | Máy in chậm/bận/reset/cắt giữa chừng | | | | Dễ, không cần máy in thật |

Ghi chú:

- **Android Emulator**: tùy chọn sẵn có `-netdelay`/`-netspeed` không giả lập được mất gói, nhưng dùng `lan_lab.sh on ... sim` thì được. Tuy vậy Emulator đi qua lớp NAT nên chỉ test đúng **bước kết nối**; lỗi bộ đệm 512 byte và đứt giữa chừng phải test trên **Android thật** (xem 7.2-B).
- Các cách A–D làm **mạng chậm/mất gói**. Cách E làm **sóng Wi-Fi bị tranh chấp thật**, là cơ chế gây lỗi ở quán. Nên chạy cả hai loại.
- Cách F kết hợp được với A–E: thay máy in thật bằng máy in giả chạy trên laptop.

### 7.2. Hướng dẫn từng cách

#### A. Network Link Conditioner trên iPhone (chỉ iOS)

1. Cắm iPhone vào máy Mac, mở Xcode một lần để bật **Developer Mode** (Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển).
2. Vào **Cài đặt → Nhà phát triển → Network Link Conditioner**.
3. Chọn profile **Very Bad Network**, hoặc **Add a profile...** để tạo profile riêng:
   - "Quán rất đông": In/Out Delay 300ms, In/Out Packet Loss 10%, In/Out Bandwidth 2000 Kbps.
   - "Mất mạng": dùng profile có sẵn **100% Loss**.
4. Bật công tắc **Enable**. Cài đặt này tác động lên toàn bộ traffic của iPhone.

**Tắt**: gạt Enable về Off. Hãy **nhớ tắt sau khi test**, nếu không iPhone sẽ chậm với mọi app.

#### B. Mac + bộ công cụ `tools/lan_lab/` (Android và iOS, **cách nhanh nhất**)

Dùng `dnctl`/`pfctl` có sẵn trên macOS, không cần cài thêm. **Mac chỉ cần Wi-Fi**, không cần Chia sẻ Internet hay dây LAN. Đã chạy thử trên macOS 26.4.1.

| File | Tác dụng |
|---|---|
| [`lan_lab.sh`](../tools/lan_lab/lan_lab.sh) | Bật/tắt mạng yếu, đổi mức, giả lập chập chờn / trễ vọt / rớt SYN, đo kiểm |
| [`lan_relay.py`](../tools/lan_lab/lan_relay.py) | Bộ chuyển tiếp: điện thoại → Mac:9100 → máy in thật. Log mỗi lần in: thời gian, số byte, **tốc độ gửi KB/s**, phía nào đóng (FIN/RST) |
| [`fake_printer.py`](../tools/lan_lab/fake_printer.py) | Máy in giả (cách F) |

Có hai đích làm yếu:

```
sim  : [iOS Simulator / Android Emulator trên Mac] ──(làm yếu)──> Router ──dây──> Máy in
phone: Điện thoại ──Wi-Fi──> Mac:9100 (làm yếu) ──lan_relay.py──> Router ──dây──> Máy in
```

- **`phone`**: chỉ đoạn điện thoại ↔ Mac bị làm yếu. Đó đúng là đoạn Wi-Fi gây lỗi ở quán, vì máy in đã cắm dây. Đoạn Mac → máy in chạy bình thường nên giấy vẫn ra thật. Trong app **nhập IP của Mac** thay cho IP máy in. Wi-Fi phải **tắt cách ly client**.
- **`sim`**: làm yếu traffic từ Mac tới IP máy in. **iOS Simulator** dùng thẳng mạng của Mac nên sát thực tế. **Android Emulator** đi qua lớp NAT riêng: vẫn tái hiện đúng **bước kết nối** (lỗi chờ 1s của SDK), nhưng **không** tái hiện được việc gửi chậm do bộ đệm 512 byte hay đứt giữa chừng, vì lớp NAT gom và gửi hộ dữ liệu. Các lỗi đó phải test trên **Android thật** (đích `phone`).
- Máy in giả hoặc bộ chuyển tiếp làm máy in thấy kết nối từ Mac chứ không phải từ điện thoại. Vì vậy "máy in bận" / kết nối nửa mở chỉ tái hiện gần đúng; muốn chính xác thì dùng `fake busy`.

Các lệnh (chạy trong `tools/lan_lab`, bằng user thường; script tự gọi `sudo`):

```bash
./lan_lab.sh check                      # đo bắt tay TCP + ping tới máy in
./lan_lab.sh on s2 sim                  # bật mạng yếu cho máy ảo
./lan_lab.sh on s2 phone                # bật mạng yếu cho điện thoại thật
./lan_lab.sh relay                      # (terminal khác) chuyển tiếp tới máy in thật
./lan_lab.sh fake busy                  # hoặc: máy in giả thay cho relay
./lan_lab.sh spike                      # trễ vọt 50–1500ms mỗi 2s, chạy đè lên mức đang bật
./lan_lab.sh flap 20 3                  # 20s có mạng / 3s mất hẳn
./lan_lab.sh syn 0.5                    # rớt thêm 50% gói SYN (syn 0 để bỏ)
./lan_lab.sh status                     # xem đang bật gì
./lan_lab.sh off                        # tắt, mạng trở lại bình thường
PRINTER=192.168.1.22 ./lan_lab.sh on s2 sim   # đổi máy in mà không sửa file
```

Các mức (thông số **một chiều** mỗi pipe; trễ đi–về thêm = 2 × delay; mất gói đi–về ≈ 2 × plr):

| Mức | Thông số `dnctl` | Trễ đi–về thêm | Mất gói (đi–về) | Tương đương |
|---|---|---|---|---|
| `s1` | `delay 40 plr 0.01` | +80ms | khoảng 2% | Quán đông vừa |
| `s2` | `delay 150 plr 0.05 bw 2Mbit/s` | +300ms | khoảng 10% | Quán rất đông |
| `s2x` | `delay 300 plr 0.10 bw 1Mbit/s` | +600ms | khoảng 20% | Cực đông |
| `s3` | `delay 500 plr 0.15 bw 512Kbit/s` | +1000ms | khoảng 30% | Quá tải: vượt ngưỡng 1s của SDK Android |
| `custom` | `DELAY=800 PLR=0.2 BW=256Kbit/s ./lan_lab.sh on custom sim` | 2 × `DELAY` | khoảng 2 × `PLR` | Tự chọn |
| `spike` | delay ngẫu nhiên 50–1500ms mỗi 2s | tới khoảng 3000ms | theo mức đang bật | Wi-Fi nghẽn từng đợt (bufferbloat): **gây lỗi nhiều nhất với SDK Android** |
| `dead` | `plr 1` | – | 100% | Mất mạng hẳn |

Lưu ý:

- Chỉ traffic **cổng 9100** bị làm yếu. Ping (ICMP), Internet và app khác chạy bình thường, nên dùng ping làm mốc so sánh.
- Khi thấy `Password:` thì gõ **mật khẩu đăng nhập Mac** (màn hình không hiện ký tự) rồi Enter. Báo `sudo: a password is required` nghĩa là mật khẩu gửi đi bị trống.
- Chế độ `sim` áp rule theo **IP máy in lúc chạy `on`**. Đổi máy in thì chạy `on` lại.
- Chế độ `phone`, lệnh `check` đo từ Mac tới chính Mac nên có thể không đi qua bộ làm yếu. Đo chính xác từ điện thoại bằng app **PingTools** (TCP ping tới IP của Mac, cổng 9100).
- Rule được nạp vào nhánh riêng `com.apple/lanlab` (dưới `dummynet-anchor "com.apple/*"` có sẵn trong `/etc/pf.conf`), không đụng rule hệ thống. `off` gỡ sạch; khởi động lại Mac cũng xóa hết.

<details>
<summary>Làm tay không dùng script (nếu Mac cắm được dây LAN và muốn dùng Chia sẻ Internet)</summary>

Sơ đồ: `Điện thoại ──Wi-Fi──> Mac (Chia sẻ Internet) ──dây LAN──> switch ──> Máy in`

1. Mac cắm dây LAN vào cùng mạng với máy in.
2. **Cài đặt hệ thống → Cài đặt chung → Chia sẻ → Chia sẻ Internet**: chia sẻ kết nối từ Ethernet cho các máy dùng Wi-Fi, rồi bật lên.
3. Cho điện thoại vào Wi-Fi do Mac phát. Điện thoại nằm sau NAT của Mac, nên **tính năng tự quét máy in LAN không thấy máy in**. Hãy **nhập IP máy in thủ công**.
4. Nạp rule vào `com.apple/lanlab`:

```bash
PRINTER=192.168.1.22
sudo dnctl pipe 1 config delay 150 plr 0.05 bw 2Mbit/s   # chiều điện thoại -> máy in
sudo dnctl pipe 2 config delay 150 plr 0.05 bw 2Mbit/s   # chiều máy in -> điện thoại
echo "dummynet in  quick proto tcp from any to $PRINTER port 9100 pipe 1
dummynet out quick proto tcp from $PRINTER port 9100 to any pipe 2" \
  | sudo pfctl -a com.apple/lanlab -f -
sudo pfctl -E          # in ra "Token : ...", ghi lại để tắt
# Khôi phục:
sudo pfctl -a com.apple/lanlab -F all; sudo dnctl -q flush; sudo pfctl -X <Token>
```

Cách này chưa chạy thử; cú pháp rule giống `lan_lab.sh` (đã kiểm bằng `pfctl -n`).

</details>

#### C. Raspberry Pi / Linux làm cầu nối + `tc netem` (sát thực tế nhất)

Sơ đồ: `Switch ──dây──> [eth0  Pi (bridge br0)  eth1] ──dây──> Máy in`

Pi chen giữa máy in và mạng, nên **mọi thiết bị** (Android, iOS, nhiều điện thoại cùng lúc) đều chịu cùng một điều kiện mạng khi in. Đây là cách sát với tình huống thật ở quán nhất. Pi cần 2 cổng Ethernet: cổng có sẵn cộng một USB-Ethernet.

Dựng cầu nối (chạy một lần sau khi khởi động Pi; nếu NetworkManager đang quản lý eth0/eth1 thì đặt chúng `unmanaged` trước):

```bash
sudo ip link add br0 type bridge
sudo ip link set eth0 master br0
sudo ip link set eth1 master br0
sudo ip link set eth0 up && sudo ip link set eth1 up && sudo ip link set br0 up
sudo dhclient br0      # tùy chọn: để SSH vào Pi qua br0
```

`netem` chỉ tác động lên **chiều gửi ra** của mỗi cổng, nên phải đặt ở **cả hai cổng** thì mới có đủ hai chiều:

```bash
# eth1 hướng về MÁY IN  -> tác động chiều điện thoại -> máy in (chiều gửi bill)
sudo tc qdisc add dev eth1 root netem delay 300ms 150ms distribution normal \
     loss 10% 25% reorder 5% 50% duplicate 1% rate 2mbit
# eth0 hướng về SWITCH -> tác động chiều máy in -> điện thoại (ACK, phản hồi trạng thái)
sudo tc qdisc add dev eth0 root netem delay 300ms 150ms distribution normal loss 10% 25%

# Đổi thông số trong lúc chạy:
sudo tc qdisc change dev eth1 root netem delay 80ms 40ms distribution normal loss 2%
# Xem:
tc -s qdisc show dev eth1
```

Ý nghĩa tham số:
- `delay 300ms 150ms distribution normal`: trễ 300ms, dao động ±150ms theo phân phối chuẩn.
- `loss 10% 25%`: mất 10% gói; gói sau có 25% khả năng mất theo gói trước, tức mất theo cụm như Wi-Fi thật.
- `reorder`: đảo thứ tự gói.
- `duplicate`: nhân đôi gói.
- `rate`: giới hạn băng thông.

**Khôi phục**:

```bash
sudo tc qdisc del dev eth1 root; sudo tc qdisc del dev eth0 root
```

**Rớt riêng gói SYN**, để test đúng bước mở kết nối và timeout mà không làm chậm phần gửi dữ liệu:

```bash
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1   # cho traffic đi qua bridge chịu iptables
sudo iptables -A FORWARD -p tcp --syn --dport 9100 \
     -m statistic --mode random --probability 0.5 -j DROP
# Gỡ:
sudo iptables -D FORWARD -p tcp --syn --dport 9100 \
     -m statistic --mode random --probability 0.5 -j DROP
```

**Script `flap.sh`** giả lập mạng chập chờn: bình thường `UP` giây thì mất hẳn `DOWN` giây, lặp mãi. Ctrl+C sẽ tự khôi phục.

```bash
#!/usr/bin/env bash
# Chạy: sudo UP=20 DOWN=3 ./flap.sh
IFACES="eth0 eth1"
UP=${UP:-20}
DOWN=${DOWN:-3}
NORMAL="delay 80ms 40ms distribution normal loss 2%"

restore() {
  for i in $IFACES; do tc qdisc del dev "$i" root 2>/dev/null; done
  echo "Đã khôi phục mạng"; exit 0
}
trap restore INT TERM

for i in $IFACES; do tc qdisc replace dev "$i" root netem $NORMAL; done
while true; do
  sleep "$UP"
  for i in $IFACES; do tc qdisc change dev "$i" root netem loss 100%; done
  echo "$(date +%T) MẤT MẠNG ${DOWN}s"
  sleep "$DOWN"
  for i in $IFACES; do tc qdisc change dev "$i" root netem $NORMAL; done
  echo "$(date +%T) có mạng lại"
done
```

**Bắt gói để phân tích** (mở bằng Wireshark, lọc `tcp.port == 9100`). Cách này cho thấy SYN bị gửi lại, RST, cửa sổ TCP bằng 0 (máy in đầy bộ đệm):

```bash
sudo tcpdump -i br0 -w lan.pcap port 9100
```

#### D. Router OpenWrt + `tc netem`

```bash
opkg update && opkg install kmod-sched tc-full   # tên gói có thể khác theo phiên bản OpenWrt
```

- Máy in cắm dây vào router: đặt `netem` trên interface LAN của cổng đó (hoặc `br-lan`) và trên `wlan0` / `phy0-ap0`, để có đủ hai chiều.
- Lệnh `tc qdisc add/change/del` giống hệt cách C. Rớt SYN thì dùng `iptables`/`nft` trên chain `forward`.

#### E. Làm nghẽn Wi-Fi thật bằng `iperf3`

Cách này tái hiện **tranh chấp sóng** (nhiều máy cùng phát làm sóng bị chiếm), là điều `netem` không làm được.

1. Một máy **cắm dây** vào router, chạy server: `iperf3 -s`
2. 3–4 laptop/điện thoại vào **cùng AP** với thiết bị POS, mỗi máy chạy:

   ```bash
   iperf3 -c <IP server> -u -b 50M -t 900        # đẩy lên (upload)
   iperf3 -c <IP server> -u -b 50M -t 900 -R     # kéo xuống (download), chạy song song trên máy khác
   ```

3. Đặt thiết bị POS **xa AP, sau 1–2 bức tường** để tín hiệu yếu như ở góc quán.
4. Muốn sóng chiếm dụng nặng hơn: tăng `-b`, thêm máy, hoặc ép AP chạy băng 2.4GHz.

**Tắt**: Ctrl+C trên các máy đang chạy `iperf3`.

#### F. Máy in giả `fake_printer.py`

Chạy trên laptop, lắng nghe cổng 9100 như một máy in ESC/POS. Trong app, nhập IP của laptop thay cho IP máy in. **Không tốn giấy**, và tái hiện được đúng các hành vi khó bắt gặp ở máy in thật:

| Chế độ | Giả lập |
|---|---|
| `ok` | Máy in bình thường |
| `slow` | Máy in đọc chậm, bộ đệm nhỏ (4KB), để test gửi khi máy in đầy bộ đệm |
| `drop` | Đóng kết nối sau `--drop-after` byte, tức đứt giữa chừng |
| `reset` | Như `drop` nhưng gửi RST (`Connection reset by peer`) |
| `busy` | Chỉ một kết nối được in; kết nối thứ hai được accept nhưng bị đóng ngay khi có byte tới. Đây là hành vi đã ghi nhận ở máy in thật (xem chú thích trong `LANPrinterConnection.swift`) |

Máy in giả luôn trả lời `DLE EOT` (`10 04 n`) bằng byte "bình thường" (`0x12`). Mỗi kết nối được lưu thành file `.bin` và được **phân tích luồng ESC/POS**: đếm số dải ảnh `GS v 0`, kiểm dải cuối có đủ byte như đã khai báo không, đếm lệnh cắt `GS V`. Nhờ vậy biết ngay bill có thiếu hoặc sẽ gây in rác hay không.

```bash
python3 fake_printer.py --mode ok
python3 fake_printer.py --mode drop --drop-after 20000
python3 fake_printer.py --mode busy
# Cổng 9100 (> 1024) chạy được bằng user thường, không cần sudo
```

Ví dụ kết quả (đã chạy thử trên macOS, gửi một bill 5 dải ảnh khoảng 46KB):

```
[..] nhận 46134 byte, bands=5 cuts=1 dle=1 -> ĐỦ
[..] CẮT kết nối sau 20000 byte (drop)
[..] nhận 20000 byte, bands=2 cuts=0 dle=0 -> THIẾU 7674 byte ở dải ảnh 3 (máy in thật sẽ nuốt dữ liệu job sau)
[..] BẬN: đóng kết nối phụ          (phía gửi nhận: Broken pipe)
```

<details>
<summary><b>fake_printer.py</b> (bấm để mở)</summary>

```python
#!/usr/bin/env python3
"""Máy in ESC/POS LAN giả lập để test mạng xấu (không tốn giấy).

  python3 fake_printer.py --mode ok
  python3 fake_printer.py --mode slow  --read-delay 0.05
  python3 fake_printer.py --mode drop  --drop-after 30000
  python3 fake_printer.py --mode busy
  python3 fake_printer.py --mode reset --drop-after 5000
"""
import argparse, os, socket, struct, threading, time

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=9100)
ap.add_argument("--mode", choices=["ok", "slow", "drop", "busy", "reset"], default="ok")
ap.add_argument("--drop-after", type=int, default=30000, help="drop/reset: số byte nhận trước khi cắt")
ap.add_argument("--read-delay", type=float, default=0.05, help="slow: giây nghỉ sau mỗi lần đọc")
ap.add_argument("--out", default="dumps", help="thư mục lưu dữ liệu nhận được")
args = ap.parse_args()
os.makedirs(args.out, exist_ok=True)
printing = threading.Lock()  # máy in thật chỉ in cho MỘT kết nối tại một thời điểm


def analyze(data: bytes) -> str:
    """Đếm lệnh GS v 0 / GS V trong luồng ESC/POS, báo dải ảnh cuối có bị thiếu byte không."""
    i, bands, cuts, dle = 0, 0, 0, 0
    while i < len(data):
        if data[i:i + 3] == b"\x1d\x76\x30" and i + 8 <= len(data):
            xl, xh, yl, yh = data[i + 4:i + 8]
            need = (xl + xh * 256) * (yl + yh * 256)
            got = len(data) - (i + 8)
            if got < need:
                return f"bands={bands} cuts={cuts} dle={dle} -> THIẾU {need - got} byte ở dải ảnh {bands + 1} (máy in thật sẽ nuốt dữ liệu job sau)"
            bands += 1
            i += 8 + need
        elif data[i:i + 2] == b"\x1d\x56":
            cuts += 1
            i += 2
        elif data[i:i + 2] == b"\x10\x04":
            dle += 1
            i += 3
        else:
            i += 1
    if cuts == 0:
        return f"bands={bands} cuts=0 dle={dle} -> KHÔNG có lệnh cắt (bill thiếu đuôi)"
    return f"bands={bands} cuts={cuts} dle={dle} -> ĐỦ"


def handle(conn: socket.socket, addr):
    tag = f"{addr[0]}:{addr[1]}"
    got_lock = printing.acquire(blocking=False)
    if args.mode == "busy" and not got_lock:
        # Hành vi đã quan sát ở máy in thật: accept nhưng đóng ngay khi có byte tới
        # (phía gửi nhận "Broken pipe"/"Connection reset").
        conn.recv(1)
        conn.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        conn.close()
        print(f"[{tag}] BẬN: đóng kết nối phụ")
        return
    buf = bytearray()
    try:
        while True:
            size = 1024 if args.mode == "slow" else 65536
            if args.mode in ("drop", "reset"):
                size = min(size, args.drop_after - len(buf))  # cắt đúng tại byte drop-after
            chunk = conn.recv(size)
            if not chunk:
                break
            buf += chunk
            # Trả lời DLE EOT n (hỏi trạng thái) bằng byte "bình thường".
            if b"\x10\x04" in chunk:
                conn.sendall(b"\x12")
            if args.mode == "slow":
                time.sleep(args.read_delay)
            if args.mode in ("drop", "reset") and len(buf) >= args.drop_after:
                if args.mode == "reset":  # SO_LINGER 0 -> close() gửi RST
                    conn.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
                print(f"[{tag}] CẮT kết nối sau {len(buf)} byte ({args.mode})")
                break
    except OSError as e:
        print(f"[{tag}] lỗi socket: {e}")
    finally:
        conn.close()
        if got_lock:
            printing.release()
    path = os.path.join(args.out, f"{int(time.time() * 1000)}_{addr[0]}.bin")
    with open(path, "wb") as f:
        f.write(buf)
    print(f"[{tag}] nhận {len(buf)} byte, {analyze(bytes(buf))}, lưu {path}")


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
if args.mode == "slow":
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)  # bộ đệm nhỏ như máy in thật
srv.bind(("0.0.0.0", args.port))
srv.listen(5)
print(f"Máy in giả chế độ '{args.mode}' đang nghe cổng {args.port}")
while True:
    c, a = srv.accept()
    threading.Thread(target=handle, args=(c, a), daemon=True).start()
```

</details>

Giới hạn của máy in giả:
- Nó không in thật nên không kiểm được chất lượng bản in.
- Việc phát hiện `DLE EOT` chỉ dò chuỗi byte trong gói nhận, nên thỉnh thoảng có thể trả lời nhầm khi dữ liệu ảnh tình cờ chứa `10 04`. Điều này vô hại khi test.
- Không phân tích lệnh TSPL (in tem). Với TSPL thì mở file `.bin` bằng trình soạn thảo văn bản để xem, vì TSPL là lệnh dạng chữ.

### 7.3. Kịch bản test chuẩn

Lệnh trong ngoặc là của `lan_lab.sh` (cách B); dùng cách C/D thì thay bằng thông số `netem` tương ứng ở 7.0.

| Mã | Điều kiện mạng | Thao tác | Kết quả mong đợi (sau khi sửa code) |
|---|---|---|---|
| S1 | Đông vừa (`on s1`) | In 20 bill liên tiếp | 20/20 bill ra đủ, không có bill rác |
| S2 | Rất đông (`on s2`) | In 20 bill; in 10 tem TSPL | Không mất bill nào **mà không báo lỗi**; bill lỗi phải báo lỗi rõ |
| S2x | Cực đông / quá tải (`on s2x`, `on s3`) | In 10 bill | App báo lỗi **nhanh và rõ**, không treo; huy hiệu mạng 🟠/🔴 (R3) |
| S3 | Chập chờn (`flap 20 3`) | In liên tục trong 10 phút | App không treo; lỗi chỉ xảy ra trong khoảng mất mạng và có báo lỗi |
| S4 | Đứt giữa bill dài | In bill dài khoảng 1m; giữa chừng `on dead` 5 giây rồi `on s1`; in bill tiếp theo | Bill tiếp theo **in sạch, không có ký tự rác** |
| S5 | Rớt 50% gói SYN (`syn 0.5`) | In 20 bill | Đo thời gian kết nối; lỗi "máy in bận" càng ít càng tốt |
| S6 | Điều kiện S2 + 2 thiết bị (1 Android, 1 iOS) | Hai máy bấm in cùng lúc, 10 lượt | Cả hai đều in được (xếp hàng); không bill nào bị cắt ngang |
| S7 | Mạng bình thường | Tắt Wi-Fi điện thoại 10 giây rồi bật lại, in ngay | App báo lỗi đúng nguyên nhân (không cùng mạng / không tới được máy in), không báo "máy in bận" |
| S8 | Máy in giả `busy` / `drop` / `reset` | In 10 bill mỗi chế độ | **Không có lần nào báo thành công** khi máy in giả ghi nhận `THIẾU` hoặc `BẬN` |
| S9 | Nghẽn sóng thật (cách E) | In 20 bill trong lúc `iperf3` đang chạy | So sánh với S1/S2 để xem giả lập có sát thực tế không |
| S10 | Mất mạng lâu (`on dead`, giữ hơn 30s) | In **1 bill**, chờ hơn 30s rồi `on s1` | App **báo lỗi**; không có bill nào in ra sau khi mạng có lại. *Hiện tại trên iOS: báo thành công, bill mất âm thầm* |
| S11 | Mất mạng ngắn (`on dead`) | In bill, bấm in lại lần 2, trong khoảng 10s thì `on s1` | Chỉ ra **1 bill**, hoặc bill in lại có ghi chú "BẢN IN LẠI" (R9). *Hiện tại trên iOS: ra 2 bill* |
| S12 | Trễ vọt (`on s1` + `spike`) | In 20 bill | Tỷ lệ in được gần bằng S1. *Hiện tại trên Android: lỗi nhiều do ngưỡng chờ 1s của SDK* |

### 7.4. Ghi nhận kết quả

Mỗi lượt chạy, điền một dòng theo mẫu:

| Ngày | Bản build | Nền tảng | Kịch bản | Số bill gửi | Ra đủ | Rác | Báo OK mà không ra giấy | Báo lỗi | Thời gian/bill (TB / p95) | Mã lỗi gặp |
|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | |

Lấy log:

```bash
# Bộ chuyển tiếp (cách B, đích phone): mỗi lần in một dòng, có thời gian và KB/s
./lan_lab.sh relay
# Android
adb logcat -s PRINTER_LOG PRINT_SEND TSPL_FLUSH
# iOS: Xcode → Console, lọc "[LANPrinterConnection]"
# Bắt gói (cách C): sudo tcpdump -i br0 -w lan.pcap port 9100
```

Chạy từng kịch bản **trước và sau** mỗi thay đổi trong lộ trình (mục 6), để có số liệu so sánh thay vì cảm nhận.

### 7.5. Kết quả đo tại văn phòng

Đo ngày 2026-09-29/30 bằng `lan_lab.sh check` (bắt tay TCP tới cổng 9100, chỉ mở rồi đóng), Mac qua Wi-Fi, máy in cắm dây.

| Điều kiện | Máy in | Bắt tay TCP (10 lần) | Ping (không bị làm yếu) |
|---|---|---|---|
| Mạng bình thường | PDIT `192.168.1.22` | 3–36ms | trung bình 11.6ms, cao nhất 74–79ms, mất 0% |
| `on s2 sim` | PDIT `192.168.1.22` | 305–321ms; **1 lần 1309ms** | không đổi |
| `on s2 sim` | Epson `192.168.1.53` | 304–412ms; **1 lần 1307ms** | trung bình 23ms, cao nhất 232ms, mất 0% |

- Mạng bình thường ở văn phòng đã có **trễ vọt tới khoảng 80ms** dù không đông người. Máy Epson dao động nhiều hơn (tới 232ms).
- Ở mức `s2`, khoảng **1/10 lần kết nối** mất gói SYN, phải chờ 1 giây gửi lại (1307–1309ms). **SDK Android sẽ báo lỗi ở những lần này** (T1), trong khi mạng vẫn dùng được.
- `on dead sim` trên iOS Simulator: bấm In **không báo lỗi**; mạng có lại thì bill mới in ra. Khớp với 5.4.
- Chưa đo: Android thật qua bộ chuyển tiếp (tốc độ KB/s để xác nhận T3), S3/S4 (xác nhận T4), nhiều thiết bị dùng chung (S6).
