# Mẹo kết nối máy in

Ghi chú nhanh cho dev và đội triển khai: đặc điểm từng hãng máy in, mẹo kết nối LAN / USB / Bluetooth, và cách đọc
trạng thái máy in.

> Cập nhật 2026-10-10. Ký hiệu: **✔ đã kiểm chứng** trên máy thật · **◐ đã thấy một phần** · **? chưa test**, theo tài liệu lệnh.
> Rủi ro kỹ thuật xem [RUI_RO_IN_LAN_USB.md](RUI_RO_IN_LAN_USB.md); in LAN khi Wi-Fi đông xem [IN_LAN_ON_DINH.md](IN_LAN_ON_DINH.md).

---

## 1. Theo hãng máy in

### Xprinter

| Mẹo | Trạng thái |
|---|---|
| Nhận diện qua MAC: OUI `00:61:7B`, `00:61:1B`, `00:61:1D` | ✔ |
| Gói UDP `XP0001FIND` gửi tới `IP:9000` → máy trả `XP0001FOUND` kèm MAC, IP, mask, gateway, DHCP. Gửi **unicast** nên chạy được cả trên iPhone | ✔ |
| Đổi IP máy in từ app qua UDP (`changeLanPrinterIp`), không cần phần mềm Windows | ✔ |
| **USB:** 2 máy cùng model có **serial khác nhau**, nên phân biệt được | ✔ (test 2 máy) |
| **USB:** Vendor ID hay gặp: `0x0483` (= `1155` thập phân), `0x1FC9` (= `8137`). `deviceId` của plugin ghi số **thập phân** | ◐ |
| Trả lời `DLE EOT` (hỏi trạng thái). Lúc bình thường trả `0x12` | ◐ đã thấy trả lời |
| Báo **hết giấy / mở nắp** qua `DLE EOT` | ? cần rút giấy / mở nắp để xác nhận |
| Một số máy tự trả `CHINA GB18030` khi hỏi tên model, nên nhận diện là Xprinter | ◐ |

### PDIT

| Mẹo | Trạng thái |
|---|---|
| OUI `00:1A:EF`. Đây thực ra là mã của **Loopcomm** (hãng làm module mạng), nên máy hãng khác dùng module này cũng hiện "PDIT" | ✔ |
| Trả lời `XP0001FIND` giống Xprinter (cùng firmware mạng) | ✔ |

### Epson (TM-series)

| Mẹo | Trạng thái |
|---|---|
| Nhận diện qua MAC (nhiều OUI của Seiko Epson, xem bảng trong `printer_label.dart`) | ✔ |
| Hỗ trợ `DLE EOT`, theo tài liệu thì vẫn trả lời khi đang dừng vì hết giấy | ? |
| Có lệnh `GS ( H` (process ID): máy trả lại mã **sau khi in xong**. Đây là cách xác nhận "đã in xong" tốt nhất | ? |
| Nếu không trả lời qua LAN: kiểm tra chế độ truyền hai chiều trong công cụ cấu hình của Epson. **Chưa xác định tên mục cài đặt cụ thể** | ? |

### Máy POS tích hợp (Sunmi, iMin, Urovo…)

- Kết nối qua **Bluetooth nội bộ**, dùng chung chip Bluetooth với máy in Bluetooth ngoài. Plugin đã khoá để gửi lần lượt, tránh in nhầm máy.
- **Không** hỏi hết giấy qua `DLE EOT`.
- **POS cầm tay in ra 2 bill.** Máy in tích hợp hiện ra với hệ điều hành như một thiết bị Bluetooth đã ghép nối sẵn, tên thường là **`InnerPrinter`** (Sunmi). Nếu trong danh sách máy in của quán có **cả "Máy in tích hợp" lẫn "InnerPrinter (Bluetooth)"** và cả hai cùng được gán chức năng in hoá đơn, thì **cùng một máy in vật lý nhận 2 lệnh**, nên ra 2 bill.
  - **Cách xử lý:** xoá máy "InnerPrinter" kiểu Bluetooth, chỉ giữ "Máy in tích hợp". Nếu muốn giữ cả hai thì gán chức năng khác nhau.
  - **Nên cải thiện trong app:** khi thiết bị có máy in tích hợp, ẩn `InnerPrinter` (và các tên máy tích hợp khác) khỏi danh sách quét Bluetooth, hoặc cảnh báo khi thêm.

---

## 2. Theo kiểu kết nối

### LAN

- **Máy in chỉ nhận MỘT kết nối in tại một thời điểm.** App nhả kết nối ngay sau khi in để máy khác dùng. Thấy lỗi "máy in bận" thì chờ vài giây rồi in lại.
- **Đặt IP cố định** cho máy in (DHCP reservation trên router theo MAC, hoặc IP tĩnh ngoài dải DHCP).
- **Máy in đổi IP:** app tự tìm lại theo MAC lúc mở app, nhưng **chỉ khi máy in đã có MAC**. MAC được lưu tự động sau lần kết nối thành công đầu tiên.
- **Wi-Fi không có Internet + bật 4G (Android):** Android có thể đẩy kết nối sang 4G. Đường in chính đã gắn kết nối vào Wi-Fi nên vẫn in được. Nhưng **quét LAN và nút nhận diện máy** vẫn có thể lỗi, khi đó tắt 4G rồi quét.
- **In trang tự kiểm tra (self-test)** để xem IP hiện tại của máy in: thường là giữ nút FEED khi bật nguồn.
- **Chọn máy trong danh sách quét** thì máy in kêu bíp. Dùng cách này để biết đúng máy, không nhả giấy.
- **Bộ đệm gửi giữ 512 byte** như SDK cũ. Để hệ điều hành tự chọn bộ đệm lớn thì đã thấy **in ra ký tự rác** trên máy thật. **Không đổi lại.**

### USB (Android)

- **Lần cấp quyền đầu tiên, tích ô "Luôn mở EasyPOS khi kết nối".** Nếu không tích, mỗi lần tắt/bật máy in hoặc máy POS sẽ phải cấp quyền lại.
- **Nhiều máy USB:** app xin quyền **lần lượt từng máy**. Tạo xong máy này mới hiện popup của máy sau.
- **Máy không tự hiện khi cắm:** plugin chỉ nhận thiết bị khai báo class máy in (`7`). Máy khai báo `0xFF` (vendor-specific) thì không tự nhận.
- **Lần in đầu ngay sau khi cắm** có thể lỗi vì driver chưa sẵn sàng. Plugin đã tự thử lại gói đầu khoảng 2,4 giây.

### Bluetooth

- **Không hỏi hết giấy.** Nhiều máy Bluetooth không trả lời, nên hỏi chỉ làm in chậm thêm.
- Mọi lần gửi Bluetooth (kể cả máy POS tích hợp) chạy **tuần tự** để không lẫn dữ liệu giữa các máy.
- Gửi gói nhỏ (120 byte, nghỉ 4ms, cứ 1500 byte nghỉ 80ms). Đây là cấu hình cân bằng giữa tốc độ và độ ổn định, đã thử trên nhiều máy.

---

## 3. Đọc trạng thái máy in (`DLE EOT`)

Plugin gửi `10 04 04` (cuộn giấy) rồi `10 04 02` (nguyên nhân dừng) **trước khi in hoá đơn / phiếu bếp**, chỉ qua LAN và USB.

Byte trả lời hợp lệ luôn có dạng `0x12` cộng thêm các bit báo lỗi:

| Lệnh | Byte trả về | Nghĩa |
|---|---|---|
| `DLE EOT 4` | `0x12` | Bình thường |
| `DLE EOT 4` | `0x1E` (bit 2–3) | **Giấy sắp hết.** Hiện chưa báo cho người dùng |
| `DLE EOT 4` | `0x72` (bit 5–6) | **Hết giấy.** Không gửi phiếu, báo `PRINTER_OUT_OF_PAPER` |
| `DLE EOT 2` | `0x16` (bit 2) | **Đang mở nắp.** Không gửi phiếu, báo `PRINTER_COVER_OPEN` |
| `DLE EOT 2` | `0x32` (bit 5) | Dừng in vì hết giấy |
| Không trả lời trong 0,8s (LAN) / 0,3s (USB) | – | Máy không hỗ trợ, **vẫn in bình thường** |

**Muốn biết "đã in xong"** (chưa làm, cần test theo model):
- `DLE EOT` gửi **sau** bill: có trả lời nghĩa là máy **đã nhận đủ**, chưa chắc đã in xong.
- `GS r 1` sau bill: máy trả lời khi đã xử lý tới đó, thường là đã in.
- `GS ( H` (Epson): máy trả lại mã sau khi **in xong**.

---

## 4. Mã lỗi plugin trả về

| Mã | Nghĩa | Đã ra giấy chưa? |
|---|---|---|
| `NO_CONNECTION` + `LAN_BUSY` | Máy in đang in cho thiết bị khác | Chưa |
| `NO_CONNECTION` + `LAN_TIMEOUT` | Mạng yếu / máy in tắt / đổi IP | Chưa |
| `NO_CONNECTION` + `LAN_UNREACHABLE` | Thiết bị khác mạng với máy in | Chưa |
| `PRINTER_OUT_OF_PAPER` | Hết giấy, phiếu **không** được gửi | Chưa |
| `PRINTER_COVER_OPEN` | Mở nắp, phiếu **không** được gửi | Chưa |
| `PRINT_ERROR` / `LAN_SEND_FAILED` | Đứt khi đang gửi | **Có thể in dở**, hỏi bếp trước khi in lại |

---

## 5. Gỡ lỗi nhanh

```bash
adb logcat -s LAN_SOCKET PRINTER_LOG USB_CONNECT PAPER_STATUS
```

| Tag | Xem gì |
|---|---|
| `LAN_SOCKET` | Kết nối LAN thất bại và lý do, ghi kẹt, không gắn được vào Wi-Fi |
| `PRINTER_LOG` | Thử lại kết nối, nhả socket |
| `USB_CONNECT` | Id USB (có `_s<serial>` hay không), cấp quyền, kết nối lại |
| `PAPER_STATUS` | Chỉ hiện khi **không hỏi được** trạng thái giấy |

**iOS:** trong Xcode lọc `LANPrinterConnection`. Dòng `🧻 ... không gửi job` xuất hiện khi phát hiện hết giấy / mở nắp.

**Lưu ý:** code native (Kotlin/Swift) **không** áp dụng khi hot reload / hot restart. Phải chạy lại `flutter run`.
