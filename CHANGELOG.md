## [2.5.5] - chưa phát hành pub.dev (dùng qua git master)

* **`lastPaperStatus(deviceId)` (Android): trạng thái giấy máy in báo ở lần in gần nhất** (`PaperSensorState`: còn,
  gần hết, hết, mở nắp, không trả lời). Native vốn hỏi `DLE EOT 4` trước mỗi lần in, giờ ghi lại để app báo "sắp hết
  giấy" mà không hỏi thêm. **Máy in LAN chưa nhận kết nối sau ~15s báo `PRINTER_BUSY`** (phiếu chưa vào máy) thay
  vì thử tới quá hạn phía app.
* **Android: biết máy in Bluetooth tắt sau ~2s thay vì ~20s.** Bắt `ACTION_ACL_DISCONNECTED` để đóng kết nối ngay, và
  thêm `probeBluetooth(macAddress)`: hỏi trạng thái ESC/POS (DLE EOT, không in ra giấy). Máy từng trả lời mà nay im
  lặng thì đóng kết nối chết và trả `false`. Các nền tảng khác dùng `checkConnect`.
* **Android: nhả socket LAN đúng một lần cho mỗi kết nối.** Đếm lệnh in theo từng kết nối, không còn rò bộ đếm làm máy in
  "đã nối mà không in". Kết nối mồ côi được đóng, kể cả kết nối cũ bị thay giữa hai lô in. Máy Bluetooth chưa từng trả
  lời lệnh hỏi trạng thái chỉ bị hỏi một lần mỗi lượt.
* **Dò máy in LAN (`scanXpPrinters`): bỏ dòng trùng theo MAC, không theo IP.** Hai máy in khác nhau bị đặt trùng một IP
  giờ đều có mặt trong kết quả dò (trước đây máy Gprinter trùng IP với máy Xprinter bị bỏ), nên app nhận ra được trùng IP.
* **`GprinterUdp.queryAt(ip)`: hỏi nhanh máy Gprinter ở một IP** (thường < 100ms). Dùng để kiểm tra "IP này còn
  đúng máy in này không" trước khi in.
* **`discoverLanDevices`: mỗi máy chỉ chờ hỏi tên / MAC tối đa 4s, bản quét SDK tối đa 3s.** Trước đây một máy không
  trả lời giữ cả lượt dò tới 30s.
* **`discoverLanDevices` ổn định hơn: máy in đang bận vẫn hiện.** Máy in trả lời broadcast (Xprinter `XP0001FIND`,
  Gprinter `B[]G`, Epson / Star) mà cùng dải với thiết bị được thêm vào kết quả, kể cả khi cổng 9100 đang bận nên lượt dò
  TCP bỏ sót. Gọi lại trong lúc đang dò thì dùng chung lượt đó (nhận lại máy đã thấy) thay vì chạy hai lượt tranh nhau
  kết nối tới máy in.

## [2.5.4] - 2026-11-23

* **Android: nhận diện máy in Bluetooth chắc hơn (MINJCODE MJ5803...).** Máy in tự khai lớp IMAGING/PRINTER (Class of
  Device) được nhận ngay; tên có `minjcode` hoặc model trần `mj` + số (không dính Xiaomi Mijia `MJYD`...) cũng được nhận.
  Loại bỏ bản BLE trùng của máy dual-mode, thiết bị chắc chắn không phải máy in (điện thoại, máy tính, tai nghe, đồng hồ…)
  và máy dual-mode lớp UNCATEGORIZED (tai nghe, TV box). Máy chưa có tên lúc quét thấy được giữ lại, hiện khi
  `ACTION_NAME_CHANGED` báo tên. Từ khoá / regex tạo một lần (không tạo lại cho mỗi thiết bị quét thấy).
* **iOS: cùng quy tắc tên** (`minjcode`, `mj` + số) và nhận máy quảng bá dịch vụ BLE 0x18F0 dù tên lạ.
* **Android: hết máy in "bận mãi" sau khi nối LAN quá hạn.** Kết nối bị huỷ do quá hạn vẫn có thể nối xong muộn và giữ
  máy in (máy in nhiệt chỉ nhận MỘT kết nối) -> mọi lần in sau báo bận. Giờ `close()` đánh dấu huỷ, vòng nối dừng lại và
  socket nối xong muộn bị đóng ngay. `reopen()` đánh dấu sổ "in dở" để lần gửi sau xả trước.
* **Android: khai báo `BLUETOOTH` / `BLUETOOTH_ADMIN` (maxSdkVersion 30)** cho máy Android 11 trở xuống — trước đây
  nhờ plugin khác khai hộ, gỡ plugin đó là mất quyền quét / nối Bluetooth.

* **Hết in ký tự rác sau lần in dở (app bị kill, rớt mạng, tắt máy in giữa chừng):** cờ "máy in có thể đang dở một
  lệnh ảnh" trước đây chỉ nằm trong bộ nhớ và chỉ bật ở đường lỗi ghi, nên app bị kill / crash / ANR / dừng khi
  debug là mất cờ, bill kế tiếp bị máy in nuốt làm dữ liệu ảnh -> ký tự rác, giấy chạy dài. Giờ là sổ LƯU BỀN
  (`PrintDirtyStore`: SharedPreferences trên Android, UserDefaults trên iOS) theo kiểu "ghi trước": ghi sổ TRƯỚC byte
  đầu của lệnh in, chỉ xoá khi cả lệnh đã gửi / máy in đã nhận; mọi gián đoạn ở giữa đều để lại cờ, lần in sau xả
  trước rồi mới gửi bill. Mỗi lệnh in chỉ ghi sổ một lần (không theo từng gói) nên không làm chậm; phần xả chỉ chạy khi
  lần in trước dở.
* **iOS: chỉ xoá sổ khi máy in đã đọc HẾT dữ liệu.** `contentProcessed` + 0,4s chỉ nghĩa là dữ liệu đã xuống TCP của
  iPhone, chưa phải máy in đã nhận (đơn dài còn hàng chục KB trong bộ đệm gửi; máy in ngừng đọc vì hết giấy thì phần đuôi
  nằm đó). Trước đây cờ bị xoá ở bước này nên rớt mạng sau đó vẫn làm bill sau ra rác. Giờ sổ chỉ xoá khi máy in tự đóng
  kết nối sau FIN (`scheduleIdleCloseIfNeeded`); hết hạn chờ hoặc lỗi thì giữ cờ. Cùng một socket còn sống thì job kế
  tiếp không xả thừa (`socketHasConfirmedJob`).
* **iOS: gửi dồn nhiều bill không còn mất lệnh báo hoàn thành.** `LANPrinterConnection` chỉ có MỘT ô job chờ xác nhận
  (`pendingConfirmJob`) nên job gửi sau ghi đè job gửi trước: 4 bill gửi dồn chỉ 1 bill được báo xong, 3 bill kia treo
  "đang in" tới khi hết hạn dù giấy đã ra; máy in reset thì các job bị ghi đè cũng không được thử lại. Giờ là danh sách
  `pendingConfirmJobs`, mỗi job hẹn xác nhận riêng, reset thì cả danh sách đưa lại hàng đợi đúng thứ tự.
* **iOS / Android: xả ở lệnh ESC/POS đầu tiên trên mỗi socket mới, không cần cờ.** Sổ "in dở" nằm trên TỪNG điện thoại;
  cửa hàng nhiều nhân viên thì điện thoại khác có thể vừa để máy in dở lệnh ảnh (rớt Wi-Fi, bị kill) mà điện thoại in
  kế tiếp không hề biết -> rác. iOS: `LANPrinterConnection.flushQueue` (chỉ job ESC/POS, tức bắt đầu bằng `ESC @`; tem
  TSPL vẫn chỉ xả khi chính thiết bị biết là dở). Android: `LanSocketConnection.takeFreshSocket` + `PrinterThermal`.
  Khoá sổ của iOS kèm cổng khi cổng khác 9100.
* **iOS: máy in bận được thử lại kiên nhẫn hơn.** Máy in nhiệt chỉ in MỘT socket, socket khác bị reset (`busy`). Trước đây
  bỏ cuộc sau 4 lần / ~3s nên bill thứ 3-4 của cửa hàng đông báo lỗi dù máy chỉ đang bận. Giờ `busy` thử tối đa 12 lần,
  khoảng cách giãn dần nhưng chặn trên 1,5s, ngẫu nhiên 0,7-1,4 để các điện thoại không thử lại đồng loạt.
* **iOS: nhả socket nhanh hơn và an toàn hơn.** `idleCloseDelay` 0,6s -> 0,25s (kênh in được trả cho điện thoại khác
  sớm hơn); `scheduleIdleCloseIfNeeded` không nhả khi còn job chờ xác nhận (trước đây phụ thuộc `idleCloseDelay` >
  `acceptConfirmDelay`, nếu không job bị gửi lại và in trùng); xác nhận gặp socket đã được nhả có chủ đích thì báo xong,
  không gửi lại.
* **Android: lỗi in trên máy in tích hợp kèm trạng thái thật của dịch vụ máy in.** `PrinterThermal.printImageESC` đính
  `details: {"printer_state": N}` (2 đang khởi động, 3 lỗi giao tiếp, 4 hết giấy, 5 quá nóng, 6 mở nắp, 7 lỗi dao cắt,
  505 không có máy in, 507 lỗi cập nhật firmware; bỏ qua khi bình thường) để app báo đúng nguyên nhân thay vì "đang bận".
  Chỉ thêm `details`, mã lỗi không đổi.
* **Android: lỗi `PRINTER_BUSY` cho biết AI đang giữ khoá in và bao lâu** (`PrinterThermal.withPrintLock`, nhật ký tag
  `PRINT_BUSY`). Khoá Bluetooth dùng chung cho máy in tích hợp và mọi máy Bluetooth ngoài, nên "bận" có thể do máy khác
  hoặc một lệnh in kẹt chứ không phải chính máy này. Chỉ thêm thông tin chẩn đoán, hành vi không đổi.
* **Android: máy KHÔNG có máy in tích hợp không còn bị coi là có.** Dòng máy "đã biết" (iMin, Sunmi, Pax...) trước đây được
  nhận NGAY theo hãng, nhưng hãng bán cả dòng có máy in lẫn không có (VD iMin Swan 2 bản Standard / Dual Screen không máy
  in): máy hiện mục "Máy in tích hợp" 80mm, tự bật Bluetooth, in vào máy in không tồn tại rồi báo "đang bận". Bằng chứng
  thật là MÁY IN ẢO trong danh sách Bluetooth ghép đôi (đã kiểm chứng: Sunmi T1-G có `00:11:22:33:44:55 InnerPrinter`,
  máy iMin-OS không máy in thì danh sách trống). Giờ: (1) với iMin (hãng đã xác nhận bán cả dòng không máy in,
  `BuiltInPrinterRules.requiresVirtualPrinter`) `pick` chỉ nhận thiết bị TRÔNG NHƯ máy in ảo (`VIRTUAL_MIN_SCORE`), không
  còn lấy máy in Bluetooth ngoài làm máy in tích hợp; các hãng khác (Sunmi, Pax, Urovo...) GIỮ cách cũ vì chưa có bằng chứng
  để đổi; (2) đọc danh sách
  ghép đôi hai lần cách 1,5s vẫn không thấy máy in ảo thì kết luận "không có máy in tích hợp"
  (`BuiltInPrinterManager.markNoVirtualPrinterFound`), LƯU BỀN nên từ lần mở app sau biết ngay, không dò / chờ / hỏi lại;
  (3) tự xoá kết luận khi thấy máy in ảo hoặc nối được. Không áp dụng cho Urovo (in bằng SDK riêng). App (`print_config`):
  nối thất bại thì hỏi lại loại máy in và ẩn mục "Máy in tích hợp".
* **Agent máy tính (`lib/desktop.dart`, `TcpPrinterPort`): cùng các sửa lỗi in rác / mất phiếu như native.** Đo trên máy in
  giả: bản cũ ra rác khi (X) một thiết bị KHÁC để máy in dở lệnh ảnh rồi Agent in tiếp, và khi (K) Agent bị rớt giữa bill rồi
  khởi động lại; còn khi tranh máy in thì bill của Agent BỊ MẤT mà vẫn báo "ok". Giờ: (1) sổ "in dở" LƯU BỀN xuống đĩa
  (`DirtyStore`, đổi đường dẫn bằng `TcpPrinterPort.dirtyStore.path`), ghi TRƯỚC byte đầu, chỉ xoá sau khi đóng êm;
  (2) phần xả 16384 byte `0x00` + `ESC @` (trước 1024 byte); (3) lệnh ESC/POS (mở đầu `ESC @`) LUÔN được xả ở kết nối
  mới, không phụ thuộc Agent này có biết máy in còn dở hay không; (4) phần xả kiêm THĂM DÒ: máy in bận reset socket ngay khi
  có byte tới -> chưa gửi byte bill nào nên thử lại an toàn, tối đa `busyMaxAttempts` (12) lần, giãn dần chặn trên
  `busyMaxDelay` (1,5s), ngẫu nhiên 0,7-1,4 lần. Chi phí: mỗi lần in thêm `busyProbe` (30ms).
* **Đổi tên hàm test sang tiếng Anh** (`RasterBinarizerTest`, `ThinStrokeBoosterTest`, `BuiltInPrinterRulesTest`).
* **Xả cho cả Bluetooth và USB:** trước đây chỉ LAN có xả. Android: `PrinterThermal.flushPrinterIfDirty` chạy đầu lệnh
  in, TRƯỚC cả lệnh hỏi trạng thái giấy (lệnh đó cũng bị máy đang kẹt nuốt); Bluetooth gửi phần xả theo đúng tốc độ in.
  iOS: `BLEManager.writeData` xả trước khi gửi, `LANPrinterConnection` xả theo sổ bền ở mọi job (không chỉ job đầu
  socket). Máy in tích hợp (Sunmi) không đi qua cổng ngoài nên không ghi sổ.
* **Phần xả đủ lấp mọi dải ảnh:** 16384 byte 0x00 + `ESC @` (trước là 10240 byte), tính theo dải `GS v 0` tối đa
  128 dòng × 128 byte/dòng (máy tới 112mm).

## [2.5.3] - 2026-11-21

* **Nhận biết máy in tem / máy in hoá đơn (LAN, USB):** `detectLanPrinterLanguage` (cùng quy tắc với trạm in trên máy
  tính): điều đã biết, model tự khai qua gói dò (Gprinter `DEVICENAME`), hãng chỉ làm máy hoá đơn, rồi hỏi máy bằng
  lệnh trạng thái TSPL / ESC/POS trên MỘT kết nối (`TcpPrinterPort.exchangeMany`). Máy hai chế độ (hiểu cả hai) trả
  `PrinterLanguage.both`. `rememberPrinterLanguage` để app ghi nhận. Xuất `PrinterLanguage`, `PrinterLanguageProbe`.
  USB: `getUsbPrinters()` kèm chuỗi IEEE 1284 máy tự khai (`CMD:TSPL` / `CMD:ESC/POS`) và trạng thái quyền.
* **Cấu hình sai vẫn không in rác:** gửi TSPL tới máy đã biết là máy hoá đơn báo `PRINTER_NOT_LABEL`; gửi ESC/POS tới
  máy đã biết là máy tem (kể cả máy hai chế độ) báo `PRINTER_NOT_RECEIPT` — nơi gọi in dạng ảnh bằng đúng lệnh.
* **Không in ký tự rác khi kết nối đứt giữa bill:** lần gửi trước tới máy bị đứt giữa chừng thì lần sau xả bộ đệm
  máy in bằng 10240 byte 0x00 (đủ lấp một dải `GS v 0` 128 dòng còn dở) rồi `ESC @` — iOS (mới) và Android (trước
  chỉ 1024 byte). iOS: nhả socket sau khi in chờ máy in đọc hết rồi mới huỷ (trước huỷ ngay khi FIN xếp hàng, phần
  chưa gửi bị bỏ -> máy chậm in nửa bill rồi rác).
* **Nối máy in LAN nhanh hơn:** chia lượt bắt tay 6s thành các lượt 1,2s, mỗi lượt một socket mới (Android, iOS).
  Máy Gprinter bỏ qua lượt bắt tay đầu (đo được) nên trước đây mỗi lần in mất thêm 2–3s; máy vừa khởi động lại mạng
  (vừa đổi IP) cũng nối được sớm hơn.
* **Quét broadcast trả sớm:** dò Gprinter (Dart) và quét trên iOS trả kết quả khi các máy đã trả lời xong (0,6s không
  có máy mới), không chờ đủ 1,5s. Sửa đọc gói dò Gprinter có đuôi rác lặp khoá (`...;T:30;IP:1`) làm máy bị bỏ qua.
  MAC `00:47:50` là Gprinter; tên model Gprinter lấy ngay từ gói dò; bỏ gói dội lại khi hỏi tên HPRT.
* **Máy in không treo "đang bận":** Android dùng khoá có hạn (20s, báo `PRINTER_BUSY`) thay cho `synchronized`, canh
  giờ lần gửi kẹt (`PRINTER_STALLED`) trên Android và iOS; kết nối Bluetooth chờ lượt đang nối thay vì mở trùng.
* **Bỏ toast native:** thông báo từ native chỉ còn ghi log (`[native] ...`), app tự quyết định hiện gì.

## [2.5.2] - 2026-11-20

* **Máy in Gprinter (module Ethernet):** `GprinterUdp` — dò máy (`B[]G`) và đổi IP / netmask / gateway / DHCP qua UDP
  broadcast tới `255.255.255.255:3000`, theo giao thức trong SDK Android chính thức của hãng
  (`com.gprinter.udp.ethernet.*`). `scanXpPrinters` / `scanNetPrinters` / `findLanPrinterIssues` gộp cả máy Gprinter
  (mục kết quả có `proto: gprinter`), `changeLanPrinterIp` tự dùng đúng giao thức theo MAC (tắt DHCP → IP → gateway →
  netmask → khởi động lại mạng) nên "Sửa & thêm" máy lệch dải chạy như Xprinter. Gói dò gửi hai lần để bù UDP mất
  gói. Có test `gprinter_udp_test.dart`; đã thử trên simulator iOS với máy Gprinter thật (đưa sang dải khác rồi tự
  sửa về dải của quán), chưa thử trên iPhone thật (cần quyền multicast của Apple).

* **Đổi IP máy in LAN nhanh hơn:** `changeLanPrinterIp(knownXpPrinter: true)` — máy đã trả lời broadcast
  `XP0001FIND` (nên đã có MAC) chắc chắn nhận `XP0001SAVE` theo MAC, bỏ bước đọc cấu hình unicast và dò hãng qua cổng
  in tới IP cũ (máy ở DẢI KHÁC thì hai bước này chỉ chờ hết hạn, vài giây). Xác minh máy in sau khi đổi: chờ đầu
  1s (trước 2s) và hỏi mỗi 0,7s (trước 1,5s).
* **Quét máy in qua broadcast (Android):** giữ `MulticastLock` trong lúc `scanNetPrinters` (nhả sau 1,5s) và khai báo
  quyền `CHANGE_WIFI_MULTICAST_STATE` — một số máy lọc gói broadcast tới khi tiết kiệm điện Wi-Fi nên không nhận được
  trả lời `XP0001FIND` (không thấy máy in, nhất là máy khác dải IP).

## [2.5.1] - 2026-11-19

* **In ảnh dài không tràn RAM (Android):** `getEscPosRasterBytes` nhị phân hoá ảnh theo từng dải 64 dòng
  (`RasterBinarizer`) thay vì nạp cả ảnh vào mảng điểm ảnh — kết quả byte giống hệt, tiết kiệm hàng chục MB với
  hoá đơn dài trên máy yếu (Android 6 / 2GB). Có test `RasterBinarizerTest`.
* **Quét máy in mạng:** 2 vòng quét + kiểm tra lại, dò máy đã biết trước; nhận diện máy theo payload từng hãng
  (Xprinter UDP, HPRT...), nhớ ngôn ngữ máy in; `resolveLanPrinterMac` (MAC lấy đầu tiên thắng).
* **DHCP máy in LAN:** `LanDevice.dhcp`; `queryHttpNetInfo` / `parseWebNetInfo` đọc trang web máy in,
  `enableLanDhcpViaWeb` bật DHCP để máy không đổi IP khi khởi động lại.
* **Gửi qua LAN ổn định hơn:** flush sau khi ghi và trễ ngẫu nhiên nhỏ giữa các lệnh (Dart, Kotlin, Swift)
  để máy in không bị rớt lệnh khi in dồn.

## [2.5.0] - 2026-11-18

* **In trên máy tính (Windows / Linux / macOS)** — entrypoint riêng `package:printer_label/desktop.dart`
  (app điện thoại KHÔNG import file này nên không đổi gì): ESC/POS + TSPL qua LAN, USB (Windows `usbprint` không
  cần driver, Linux `usblp` / CUPS, macOS CUPS), dò máy in mạng + USB, nhận loại máy in (tem / hoá đơn) và khổ
  giấy, bíp nhận máy, căn chỉnh tem, tự cắt giấy. Thêm phụ thuộc `image` và `ffi` (chỉ dùng bởi `desktop.dart`);
  `sdk` tối thiểu nâng lên `>=3.8.0`.
* **Linux:** máy in tem không khai tên USB (4BARCODE...) lấy tên + loại máy từ chuỗi IEEE 1284 của `usblp`;
  `UsbPrinters.issues()` báo vì sao máy in thấy mà chưa dùng được (thiếu `usblp`, driver khác giữ, thiếu quyền ghi).
* **Quét máy in mạng:** `LanPrinterScanner.scan(onFound:)` báo từng máy ngay khi thấy; thứ tự dò ưu tiên máy đã
  trả lời ARP và cùng dải.
* **Bíp:** `PrinterBeep.plan` — nhiều cách bíp (còi tem, nhích tem, ESC/POS) để thử lần lượt.

### Các thay đổi khác của 2.5.0

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
