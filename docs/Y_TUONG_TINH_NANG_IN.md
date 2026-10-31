# Ý tưởng phát triển tính năng in cho EasyPOS

Tài liệu tham khảo để chọn hướng phát triển tiếp cho mảng in (hoá đơn, bếp, tem) của EasyPOS.

> Cập nhật 2026-10-10.
>
> **Nguồn ý tưởng:** các tính năng phổ biến ở hệ thống POS bán lẻ / F&B trong và ngoài nước (iPOS, KiotViet, Sapo,
> CukCuk, Toast, Square, Lightspeed…). Đây là tổng hợp **theo nhóm nhu cầu**, không phải bảng so sánh từng hãng: mình
> **chưa kiểm chứng** hãng nào có chính xác tính năng nào. Trước khi chốt làm, nên dùng thử bản demo của đối thủ.
>
> Rủi ro kỹ thuật còn tồn tại của phần in hiện tại xem [RUI_RO_IN_LAN_USB.md](RUI_RO_IN_LAN_USB.md).

---

## Mục lục

1. [EasyPOS đã có gì](#1-easypos-đã-có-gì)
2. [Độ tin cậy và vận hành](#2-độ-tin-cậy-và-vận-hành)
3. [Bếp / bar](#3-bếp--bar)
4. [Hoá đơn cho khách](#4-hoá-đơn-cho-khách)
5. [Mẫu in](#5-mẫu-in)
6. [Phần cứng và cài đặt](#6-phần-cứng-và-cài-đặt)
7. [Quản trị và chống gian lận](#7-quản-trị-và-chống-gian-lận)
8. [Tốc độ và chất lượng in](#8-tốc-độ-và-chất-lượng-in)
9. [Bảng ưu tiên đề xuất](#9-bảng-ưu-tiên-đề-xuất)

Mỗi tính năng ghi: **Giá trị** (lợi ích cho quán), **Độ khó** (Thấp / Trung bình / Cao), **Ghi chú** (điểm kỹ thuật
đáng chú ý trong code hiện tại).

---

## 1. EasyPOS đã có gì

| Nhóm | Đã có |
|---|---|
| Kết nối | LAN, Bluetooth (BLE/Classic), USB (Android), máy POS tích hợp (Sunmi, iMin, Urovo…) |
| Loại phiếu | Tạm tính, thanh toán, chế biến, huỷ món, cung ứng, QR thanh toán, tem nhãn, tem dán ly |
| Định tuyến | In theo khu vực chế biến, mỗi máy in gán chức năng + khu vực |
| LAN | Nhiều thiết bị dùng chung máy in, đo chất lượng mạng, tự tìm lại máy in đổi IP theo MAC, đổi IP máy in từ app, quét + nhận diện hãng |
| USB | Tự phát hiện khi cắm, xin quyền theo hàng đợi, banner hướng dẫn cấp quyền |
| Khác | Mẫu in web (HTML) cache offline, mở két theo máy đang in, telemetry lỗi in, nhãn "Đã kết nối" khi quét |

Phần **kết nối** đã khá đầy đủ. Khoảng trống lớn nằm ở **vận hành khi có lỗi**, **trải nghiệm bếp** và **quản trị**.

---

## 2. Độ tin cậy và vận hành

### 2.1. Trung tâm lệnh in (hàng đợi + lịch sử)

- **Mô tả:** mỗi lệnh in thành một bản ghi: trạng thái (đang chờ / đang in / thành công / lỗi), máy in, phiếu nào, thời điểm. Có màn xem các lệnh lỗi, bấm "In lại" hoặc "In sang máy khác".
- **Giá trị:** **Rất cao.** Đây là điểm đau số 1 giờ cao điểm: in lỗi thì nhân viên không biết phiếu nào đã ra, phiếu nào chưa, nên bấm lại và ra trùng phiếu bếp.
- **Độ khó:** Trung bình–Cao.
- **Ghi chú:** tương ứng R9 trong [IN_LAN_ON_DINH.md](IN_LAN_ON_DINH.md#6-lộ-trình-sửa-code).
  - Lỗi **trước khi gửi byte** (`NO_CONNECTION`, `LAN_BUSY`, `LAN_TIMEOUT`) thì tự thử lại.
  - Lỗi **giữa chừng** (`LAN_SEND_FAILED`) thì **không** tự in lại, mà đánh dấu "cần kiểm tra".

### 2.2. Máy in dự phòng (failover)

- **Mô tả:** mỗi máy in khai báo một máy dự phòng. Máy chính lỗi hoặc offline thì tự in sang máy dự phòng, kèm dòng "IN THAY CHO: Bếp 1".
- **Giá trị:** Cao. Bếp không bị "mất phiếu" khi một máy kẹt giấy hay mất mạng.
- **Độ khó:** Trung bình.

### 2.3. Theo dõi trạng thái máy in

- **Mô tả:** biểu tượng trạng thái (🟢 / 🟡 / 🔴) trên thanh trên cùng màn bán hàng. Báo ngay khi máy bếp mất kết nối, **hết giấy** hoặc **mở nắp**, trước khi tới lượt in.
- **Giá trị:** Cao. Phát hiện lỗi sớm thay vì đợi khách hỏi món.
- **Độ khó:** Trung bình.
- **Ghi chú:**
  - Hỏi trạng thái bằng `DLE EOT` theo chu kỳ dài (30–60s), và **chỉ khi rảnh**, vì máy LAN chỉ nhận một kết nối tại một thời điểm.
  - Phải sửa lỗi A1 trước (hỏi trạng thái mở socket mà không nhả).

### 2.4. Chống in trùng

- **Mô tả:** mỗi phiếu có mã lệnh in. In lại cùng mã thì phiếu ghi **"BẢN IN LẠI (lần 2)"** và giờ in lại.
- **Giá trị:** Cao. Bếp biết đây là phiếu in lại, không làm món hai lần.
- **Độ khó:** Thấp–Trung bình.

**Luồng khi mạng kém, in lỗi:**

1. **Huỷ hẳn lệnh in lỗi, không âm thầm thử lại sau.** Nếu để lệnh nằm chờ rồi tự in khi mạng có lại, phiếu sẽ ra trễ, và nếu người dùng đã bấm in lại thì ra **2 phiếu**. Đây chính là lỗi iOS cũ ("gửi rồi quên").
2. **Báo người dùng đúng nguyên nhân** (máy in bận / mạng yếu / khác mạng Wi-Fi), kèm nút **"In lại"**.
3. **Người dùng bấm "In lại"**: in với cùng mã lệnh. Có ghi "BẢN IN LẠI" hay không tuỳ vào **lần trước đã có thể ra giấy chưa**, theo bảng dưới.

**Bẫy cần tránh:** nếu lần trước chắc chắn chưa ra giấy mà lần này vẫn ghi "BẢN IN LẠI", bếp tưởng đã làm món nên **bỏ qua phiếu**. Hậu quả còn tệ hơn in trùng.

Chỉ đếm những lần in **có thể đã ra giấy**:

| Kết quả lần in trước | Ví dụ mã lỗi | Đã ra giấy? | Lần in kế tiếp ghi |
|---|---|---|---|
| Lỗi **trước khi gửi** dữ liệu | `NO_CONNECTION`: `LAN_BUSY`, `LAN_TIMEOUT`, `LAN_UNREACHABLE`; USB chưa có quyền | **Chắc chắn chưa** | In như **bản gốc**, không tăng số lần |
| Lỗi **giữa chừng** | `PRINT_ERROR` / `LAN_SEND_FAILED` | **Có thể in dở** | "IN LẠI – lần trước có thể in dở" |
| **Thành công** | – | Có | "BẢN IN LẠI (lần N) – HH:mm" |

**Ghi chú kỹ thuật:**
- **Mã lệnh in:** `mã đơn + loại phiếu + đợt gửi bếp`. Mỗi lần gọi thêm món là một đợt mới, có mã riêng, để phiếu bổ sung không bị nhầm là in lại.
- **Nơi lưu số lần in:** lưu cục bộ (Hive) để dùng được khi offline, và đồng bộ lên server nếu nhiều máy cùng in một đơn.
- **Plugin đã trả đủ thông tin để phân loại** (mã lỗi + lý do trong `details`, xem RUI_RO_IN_LAN_USB.md). App chỉ cần đọc mã lỗi thay vì gộp tất cả thành "Máy in chưa sẵn sàng".
- **Trường hợp báo "thành công" nhưng không ra giấy vẫn có thể xảy ra** (bộ đệm gửi lớn trên Android, rủi ro chưa ghi trong tài liệu). Khi đó lần bấm lại sẽ bị ghi "BẢN IN LẠI" dù bếp chưa nhận phiếu. Muốn chắc chắn phải làm thêm **R7**: sau mỗi phiếu hỏi `DLE EOT` để xác nhận máy in đã nhận đủ.

### 2.5. Máy chủ in trung gian (print server)

- **Mô tả:** một thiết bị cố định (máy POS quầy) nhận lệnh in từ các điện thoại phục vụ rồi in xuống máy in.
- **Giá trị:** Trung bình–Cao.
  - Điện thoại không còn tranh nhau socket LAN.
  - Đơn đặt qua **QR tại bàn** hoặc **đơn online** in được xuống bếp kể cả khi không có ai cầm máy (xem 3.6).
- **Độ khó:** Cao. Cần kênh đẩy lệnh (server / MQTT; app đã có `mqtt_client`) và một thiết bị luôn bật.

---

## 3. Bếp / bar

### 3.1. Màn hình bếp (KDS) kết hợp máy in

- **Mô tả:** bếp xem món trên tablet thay cho giấy, bấm "Đã xong" để báo phục vụ. Có thể chạy song song với máy in.
- **Giá trị:** Rất cao với nhà hàng lớn. Đây gần như là tính năng tiêu chuẩn của các hệ thống F&B lớn.
- **Độ khó:** Cao (một tính năng riêng).
- **Ghi chú:** dùng lại định tuyến theo khu vực chế biến đã có.

### 3.2. Phiếu chế biến dễ đọc hơn

- **Mô tả:**
  - Tên món và số lượng **chữ to**; ghi chú / topping **in đậm hoặc đảo màu** (nền đen chữ trắng).
  - Món huỷ hoặc giảm số lượng in **gạch ngang** hoặc ghi "HUỶ".
  - Hiện số bàn, số khách, tên nhân viên và **thời gian chờ** ở đầu phiếu.
- **Giá trị:** Cao, chi phí thấp. Giảm làm sai món.
- **Độ khó:** Thấp (chủ yếu sửa mẫu in).

### 3.3. Tách / gộp phiếu theo món

- **Mô tả:** tuỳ chọn theo khu vực:
  - **Mỗi món một phiếu:** bar pha chế, mỗi ly một phiếu để dán.
  - **Gộp cả bàn một phiếu:** bếp nóng.
- **Giá trị:** Trung bình–Cao.
- **Độ khó:** Thấp–Trung bình.

### 3.4. Lên món theo đợt (course / "giữ món")

- **Mô tả:** gọi món khai vị in ngay, món chính "giữ lại" và chỉ in xuống bếp khi phục vụ bấm "Lên món chính".
- **Giá trị:** Trung bình–Cao với nhà hàng phục vụ bàn.
- **Độ khó:** Trung bình (đụng tới nghiệp vụ order).

### 3.5. Báo bếp bằng âm thanh

- **Mô tả:** máy in bếp kêu bíp khi có phiếu mới, hoặc kích chuông ngoài qua cổng két (RJ11).
- **Giá trị:** Trung bình. Bếp ồn, dễ bỏ sót phiếu.
- **Độ khó:** Thấp. Đã có sẵn bộ lệnh còi trong `PrinterLabel._identifyPayload`, chỉ cần thêm tuỳ chọn theo máy in.

### 3.6. Đơn QR tại bàn / đơn online tự in xuống bếp

- **Mô tả:** khách tự gọi món qua QR hoặc đơn từ app giao hàng. Hệ thống tự in phiếu bếp, không cần nhân viên xác nhận (hoặc xác nhận một chạm).
- **Giá trị:** Cao, đang là xu hướng.
- **Độ khó:** Cao. Cần máy chủ in (2.5).

---

## 4. Hoá đơn cho khách

### 4.1. QR tra cứu hoá đơn điện tử trên bill

- **Mô tả:** in mã QR / mã tra cứu hoá đơn điện tử ngay trên hoá đơn thanh toán.
- **Giá trị:** **Rất cao và là lợi thế riêng.** Softdreams làm hoá đơn điện tử, nên tích hợp sâu ở đây là điểm khác biệt so với đối thủ. Nhiều quán cũng cần đáp ứng quy định xuất hoá đơn điện tử từ máy tính tiền.
- **Độ khó:** Trung bình (phụ thuộc API hoá đơn điện tử).

### 4.2. QR thanh toán động

- **Mô tả:** QR VietQR có sẵn số tiền + nội dung chuyển khoản theo đúng đơn; khách quét là đúng số tiền. Tự đối soát khi tiền về.
- **Giá trị:** Rất cao.
- **Độ khó:** Trung bình.
- **Ghi chú:** đã có loại phiếu `paymentQR`. Cần kiểm tra đã là QR động theo đơn và đã đối soát tự động chưa.

### 4.3. Hoá đơn điện tử thay giấy (e-receipt)

- **Mô tả:** gửi hoá đơn qua Zalo / SMS / email, hoặc khách quét QR trên màn hình phụ để xem. Có tuỳ chọn "không in giấy".
- **Giá trị:** Trung bình–Cao. Tiết kiệm giấy, có kênh chăm sóc khách hàng.
- **Độ khó:** Trung bình.

### 4.4. Nội dung marketing trên bill

- **Mô tả:**
  - Logo, chân trang theo chương trình khuyến mãi.
  - QR đánh giá / feedback, QR tích điểm thành viên.
  - Voucher cho lần sau in kèm hoá đơn.
- **Giá trị:** Trung bình.
- **Độ khó:** Thấp–Trung bình (nếu mẫu in hỗ trợ biến và khối điều kiện).

### 4.5. Đánh dấu bản in lại và tạm tính

- **Mô tả:** hoá đơn in lại có dòng **"BẢN SAO"**. Tạm tính ghi rõ **"CHƯA THANH TOÁN"**.
- **Giá trị:** Trung bình. Tránh khách hoặc nhân viên dùng tạm tính như hoá đơn.
- **Độ khó:** Thấp.

### 4.6. In song ngữ

- **Mô tả:** mẫu hoá đơn Việt–Anh cho quán có khách du lịch.
- **Giá trị:** Thấp–Trung bình (tuỳ tập khách).
- **Độ khó:** Thấp.

---

## 5. Mẫu in

### 5.1. Trình chỉnh mẫu kéo-thả có xem trước

- **Mô tả:** chủ quán tự bật/tắt và sắp xếp khối (logo, thông tin quán, bảng món, QR, chân trang), chỉnh cỡ chữ, xem trước đúng khổ 58/80mm.
- **Giá trị:** Cao. Giảm phụ thuộc đội hỗ trợ khi khách muốn sửa mẫu.
- **Độ khó:** Cao.
- **Ghi chú:** hiện đã có mẫu in web (HTML). Có thể làm trình chỉnh trên web admin trước.

### 5.2. Mẫu theo chi nhánh / theo kênh bán

- **Mô tả:** mỗi chi nhánh, hoặc mỗi kênh (tại quán / mang về / giao hàng), một mẫu khác nhau.
- **Giá trị:** Trung bình với chuỗi.
- **Độ khó:** Trung bình.

### 5.3. Nút "In thử" mọi mẫu

- **Mô tả:** in thử với dữ liệu mẫu ngay trong màn cài đặt, không phải tạo đơn giả.
- **Giá trị:** Trung bình. Giúp đội triển khai cài đặt nhanh.
- **Độ khó:** Thấp.

---

## 6. Phần cứng và cài đặt

### 6.1. Trình hướng dẫn cài máy in

- **Mô tả:** luồng từng bước: chọn loại kết nối → quét → kêu bíp xác nhận đúng máy → chọn chức năng / khu vực → in thử. Phát hiện sẵn các lỗi thường gặp (khác mạng, máy in chưa có IP cố định, USB chưa cấp quyền).
- **Giá trị:** Cao. Giảm cuộc gọi hỗ trợ.
- **Độ khó:** Trung bình. Phần lớn chức năng đã có, chủ yếu là ghép luồng.

### 6.2. Cấu hình Wi-Fi cho máy in Wi-Fi

- **Mô tả:** nhập SSID / mật khẩu từ app để máy in Wi-Fi vào mạng quán, không cần phần mềm Windows.
- **Giá trị:** Trung bình.
- **Độ khó:** Cao. Mỗi hãng một giao thức, phải test từng model.

### 6.3. In tem mã vạch hàng loạt (bán lẻ)

- **Mô tả:** từ phiếu nhập kho hoặc danh sách sản phẩm, in tem giá / mã vạch theo số lượng nhập. Chọn khổ tem, mẫu tem.
- **Giá trị:** Cao với shop bán lẻ.
- **Độ khó:** Trung bình. Đã có in tem TSPL, cần màn chọn sản phẩm và mẫu tem.

### 6.4. Tem cân điện tử / tem hạn sử dụng

- **Mô tả:** in tem có trọng lượng, giá theo kg, ngày sản xuất / hạn dùng (đồ ăn sẵn, bánh, thực phẩm tươi).
- **Giá trị:** Trung bình (tuỳ ngành hàng).
- **Độ khó:** Trung bình–Cao (nếu nối cân).

### 6.5. Nhận diện máy in chính xác hơn

- **Mô tả:** tự nhận hãng / model / khổ giấy để điền sẵn cấu hình.
- **Giá trị:** Trung bình.
- **Độ khó:** Thấp. Đã phân tích: cho `PrinterHardwareDetector` tra theo MAC, sửa tra VID USB (hex/thập phân), không cache kết quả "Chưa xác định".

---

## 7. Quản trị và chống gian lận

### 7.1. Nhật ký in và phân quyền in lại

- **Mô tả:**
  - Ghi ai in, in lúc nào, in lại mấy lần.
  - Phân quyền: nhân viên in tạm tính tối đa N lần; in lại hoá đơn cần quản lý duyệt.
  - Báo cáo "phiếu tạm tính in nhiều lần nhưng đơn bị huỷ".
- **Giá trị:** Cao với chủ quán. Đây là kiểu gian lận phổ biến: in tạm tính thu tiền khách rồi huỷ đơn.
- **Độ khó:** Trung bình.

### 7.2. Báo cáo sức khoẻ máy in

- **Mô tả:** thống kê tỉ lệ in lỗi theo máy in / chi nhánh / giờ, để đội CSKH chủ động liên hệ quán có mạng kém.
- **Giá trị:** Trung bình–Cao (nội bộ Softdreams).
- **Độ khó:** Thấp. Đã có `PrinterTelemetryService`, cần dashboard.

### 7.3. Đồng bộ cấu hình máy in giữa các thiết bị

- **Mô tả:** cài máy in một lần, mọi thiết bị trong chi nhánh dùng được. Riêng USB / Bluetooth gắn theo thiết bị.
- **Giá trị:** Trung bình.
- **Độ khó:** Thấp–Trung bình. Danh sách máy in đã lưu trên server; cần làm rõ máy nào dùng chung, máy nào gắn theo thiết bị.

---

## 8. Tốc độ và chất lượng in

### 8.1. In bằng chữ (text mode) thay vì ảnh

- **Mô tả:** phiếu bếp in bằng lệnh chữ ESC/POS thay vì ảnh raster.
- **Giá trị:** Cao.
  - Dữ liệu nhỏ hơn hàng chục lần (vài KB thay vì 70–150KB), in tức thì.
  - Ít lỗi trên Wi-Fi yếu và Bluetooth.
- **Độ khó:** Trung bình–Cao. Tiếng Việt có dấu phụ thuộc bảng mã của máy in (nhiều máy Trung Quốc không có), nên cần chế độ lai: chữ không dấu hoặc font hỗ trợ, ảnh cho logo / QR.

### 8.2. Giảm dung lượng ảnh

- **Mô tả:** cắt dải trắng đầu/cuối, thay dải trắng bằng lệnh đẩy giấy (R10).
- **Giá trị:** Trung bình.
- **Độ khó:** Thấp.

### 8.3. Chỉnh độ đậm theo máy in

- **Mô tả:** thanh trượt độ đậm / ngưỡng đen-trắng cho từng máy in (máy cũ in nhạt, máy mới in đậm).
- **Giá trị:** Trung bình.
- **Độ khó:** Thấp. Hiện ngưỡng 200 đang cố định trong `getEscPosRasterBytes`.

---

## 9. Bảng ưu tiên đề xuất

Tiêu chí: giá trị cho quán so với công sức, và có tận dụng được thứ đã có không.

| Đợt | Tính năng | Giá trị | Độ khó | Lý do |
|---|---|---|---|---|
| **1. Làm ngay** | 2.4 Chống in trùng / "BẢN IN LẠI" | Cao | Thấp | Ít việc, giảm sai món ngay |
| | 3.2 Phiếu bếp dễ đọc | Cao | Thấp | Chủ yếu sửa mẫu in |
| | 3.5 Báo bếp bằng âm thanh | Trung bình | Thấp | Lệnh còi đã có sẵn |
| | 4.5 Đánh dấu bản sao / tạm tính | Trung bình | Thấp | Chống nhầm hoá đơn |
| | 6.5 Nhận diện máy in | Trung bình | Thấp | Đã phân tích xong |
| **2. Ngắn hạn** | 2.1 Trung tâm lệnh in | Rất cao | Trung bình–Cao | Điểm đau lớn nhất giờ cao điểm |
| | 2.3 Theo dõi trạng thái máy in | Cao | Trung bình | Báo hết giấy / mất kết nối sớm |
| | 4.1 QR hoá đơn điện tử | Rất cao | Trung bình | Lợi thế riêng của Softdreams |
| | 7.1 Nhật ký in + phân quyền | Cao | Trung bình | Chủ quán rất quan tâm |
| | 6.1 Trình hướng dẫn cài máy in | Cao | Trung bình | Giảm tải CSKH |
| **3. Trung hạn** | 2.2 Máy in dự phòng | Cao | Trung bình | Cần 2.1 trước |
| | 3.3 Tách / gộp phiếu, 3.4 Lên món theo đợt | Trung bình–Cao | Trung bình | Nhà hàng phục vụ bàn |
| | 6.3 In tem mã vạch hàng loạt | Cao (bán lẻ) | Trung bình | Mở rộng sang bán lẻ |
| | 8.1 In text mode cho phiếu bếp | Cao | Trung bình–Cao | Nhanh, chịu mạng yếu tốt |
| **4. Dài hạn** | 3.1 Màn hình bếp (KDS) | Rất cao | Cao | Tính năng riêng, cạnh tranh trực tiếp |
| | 2.5 Máy chủ in + 3.6 Đơn QR / online tự in | Cao | Cao | Nền tảng cho gọi món tự phục vụ |
| | 5.1 Trình chỉnh mẫu kéo-thả | Cao | Cao | Có thể làm trên web admin |

**Song song với mọi đợt:** xử lý các rủi ro mức Cao trong [RUI_RO_IN_LAN_USB.md](RUI_RO_IN_LAN_USB.md) (A1–A4, U2, U3).
Tính năng mới xây trên phần in chưa ổn định sẽ khuếch đại lỗi.
