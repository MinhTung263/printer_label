# Ý tưởng phát triển tính năng in cho EasyPOS

Tài liệu tham khảo để chọn hướng phát triển tiếp cho mảng in (hoá đơn, bếp, tem) của EasyPOS, dựa trên tra cứu
tài liệu công khai của các hãng POS trong và ngoài nước.

> Tra cứu ngày 2026-10-10.
>
> **Nguồn:** trang tính năng, trang cập nhật và help center chính thức của từng hãng. Link nằm ở [mục 8](#8-nguồn-tham-khảo).
>
> **Giới hạn:**
> - Không truy cập được help center của KiotViet, CukCuk, Sapo và iPOS. Thông tin các hãng Việt Nam lấy từ trang tính năng, blog và hướng dẫn trên site chính. Một số tài liệu đã cũ (2016–2022).
> - Dấu **"?"** chỉ có nghĩa là **không tìm thấy nguồn**, không có nghĩa là hãng đó không có tính năng.
> - Thông tin về Clover phần lớn đến từ cộng đồng hoặc bên thứ ba.
>
> Rủi ro kỹ thuật còn tồn tại của phần in hiện tại xem [RUI_RO_IN_LAN_USB.md](RUI_RO_IN_LAN_USB.md).

---

## Mục lục

1. [Tóm tắt](#1-tóm-tắt)
2. [EasyPOS đã có gì](#2-easypos-đã-có-gì)
3. [So sánh với các hãng](#3-so-sánh-với-các-hãng)
4. [Điểm đáng học từ từng hãng](#4-điểm-đáng-học-từ-từng-hãng)
5. [Danh sách tính năng đề xuất](#5-danh-sách-tính-năng-đề-xuất)
6. [Bảng ưu tiên](#6-bảng-ưu-tiên)
7. [Ý tưởng chưa thấy ở hãng nào](#7-ý-tưởng-chưa-thấy-ở-hãng-nào)
8. [Nguồn tham khảo](#8-nguồn-tham-khảo)

---

## 1. Tóm tắt

- **Phần kết nối của EasyPOS đã ngang hoặc hơn các hãng Việt Nam.** EasyPOS có đủ LAN, Bluetooth, USB và máy POS tích hợp, tự dò IP, tự tìm lại máy in đổi IP theo MAC, và nhiều thiết bị dùng chung một máy in.
- **Đối thủ trong nước có những thứ EasyPOS chưa có:**
  - **KiotViet:** lịch sử báo bếp kèm in lại món lỗi, cảnh báo kẹt hoặc hết giấy, tách thành phần combo về đúng bếp, phiếu chuyển bàn, in tập trung qua một máy POS.
  - **Sapo:** QR thanh toán in trên bill, in tem theo hình thức phục vụ, phân quyền in tạm tính, in tem mã vạch trên mobile.
  - **iPOS và CukCuk:** màn hình bếp (KDS).
- **Hoá đơn điện tử từ máy tính tiền không còn là điểm khác biệt.** CukCuk, iPOS (FABiBox) và Pos365 đều đã có. Với EasyPOS, tính năng này là **bắt buộc phải có**. Lợi thế của Softdreams chỉ còn nằm ở chỗ tích hợp sâu và ổn định hơn.
- **Cơ hội tạo khác biệt ở thị trường Việt Nam:** không tìm thấy hãng Việt Nam nào công bố **máy in dự phòng**, **âm báo bếp** hay **gửi hoá đơn qua Zalo/SMS**. Ở quốc tế, Lightspeed và Toast đã có máy in dự phòng.

---

## 2. EasyPOS đã có gì

| Nhóm | Đã có |
|---|---|
| Kết nối | LAN, Bluetooth (BLE/Classic), USB (Android), máy POS tích hợp (Sunmi, iMin, Urovo…) |
| Loại phiếu | Tạm tính, thanh toán, chế biến, huỷ món, cung ứng, QR thanh toán, tem nhãn, tem dán ly |
| Định tuyến | In theo khu vực chế biến; mỗi máy in gán chức năng và khu vực |
| LAN | Nhiều thiết bị dùng chung máy in, đo chất lượng mạng, tự tìm lại máy in đổi IP theo MAC, đổi IP máy in từ app, quét và nhận diện hãng, nhãn "Đã kết nối" khi quét |
| USB | Tự phát hiện khi cắm, xin quyền theo hàng đợi, banner hướng dẫn cấp quyền |
| Khác | Mẫu in web (HTML) cache offline, mở két theo máy đang in, telemetry lỗi in |

---

## 3. So sánh với các hãng

✔ = có nguồn xác nhận · (c) = chỉ có từ cộng đồng hoặc bên thứ ba · ? = không tìm thấy nguồn · ✘ = có nguồn nói là chưa có

### 3.1. Kết nối và định tuyến

| Tính năng | EasyPOS | KiotViet | Sapo | CukCuk | iPOS/FABi | Toast | Square | Lightspeed K |
|---|---|---|---|---|---|---|---|---|
| LAN / Wi-Fi | ✔ | ✔ | ✔ | ? | ✔ | ✔ | ✔ | ✔ |
| Bluetooth | ✔ | ✔ (Android) | ✔ | ? | ✔ | ? | ? | ? |
| USB | ✔ | ✔ | ? | ? | ? | ? | ? | ? |
| Tự dò IP máy in | ✔ | ✔ | ✔ | ? | ? | ? | ? | ? |
| Tự tìm lại máy in đổi IP (theo MAC) | ✔ | ? | ? | ? | ? | ? | ? | ? |
| Định tuyến theo khu vực / nhóm hàng | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Định tuyến theo hình thức phục vụ (tại bàn / mang đi / online) | ? | ? | ✔ (tem) | ? | ? | ✔ | ✔ | ? |
| Tách thành phần combo về đúng bếp | ? | ✔ | ? | ? | ? | ? | ? | ? |
| In tập trung qua một thiết bị | ✘ | ✔ | ? | ? | ? | ? | Một phần (chỉ đơn online) | ? |

### 3.2. Phiếu bếp

| Tính năng | EasyPOS | KiotViet | Sapo | CukCuk | iPOS/FABi | Toast | Square | Lightspeed K | Loyverse |
|---|---|---|---|---|---|---|---|---|---|
| Mỗi món một phiếu / gộp | ? | ✔ | ? | ? | ? | ? | ✔ | ? | ✔ |
| Gộp món giống nhau, phiếu thu gọn | ? | ? | ? | ? | ? | ? | ✔ | ? | ? |
| Cỡ chữ theo máy in | ? | ? | ? | ? | ? | ✔ | ✔ | ? | ? |
| Tên món riêng cho bếp | ? | ? | ? | ? | ? | ? | ✔ | ? | ? |
| Phiếu huỷ món | ✔ | ✔ | ? | ? | ? | ? | ✔ | ? | ✔ |
| Phiếu chuyển bàn | ? | ✔ | ? | ? | ? | ? | ? | ? | ? |
| Dấu "IN LẠI" | ? | ? | ? | ? | ? | ? | ? | ? | ✔ |
| Giữ món / lên món theo đợt | ✘ | ? | ? | ? | ? | ✔ | ✔ | ? | ? |
| Màn hình bếp (KDS) | ✘ | ? | ? | ✔ | ✔ | ✔ | ✔ | ? | ✔ |

### 3.3. Độ tin cậy

| Tính năng | EasyPOS | KiotViet | Sapo | Toast | Square | Lightspeed K |
|---|---|---|---|---|---|---|
| Cảnh báo lỗi in (kẹt / hết giấy / mất kết nối) | Một phần (báo lỗi khi in) | ✔ | ? | ✔ | (c) | ? |
| Lịch sử / hàng đợi lệnh in | ✘ | ✔ | ? | ✔ | (c) | ? |
| In lại món lỗi | ✘ | ✔ | ✔ (đơn giao hàng) | ✔ (tự in tiếp khi online lại) | ? | ✔ |
| Máy in dự phòng tự động | ✘ | ? | ? | ✔ (khi offline) | ✘ (c) | ✔ (kèm header "BACKUP") |

### 3.4. Hoá đơn, tem, quản trị

| Tính năng | EasyPOS | KiotViet | Sapo | CukCuk | iPOS/FABi | Pos365 | Toast | Square |
|---|---|---|---|---|---|---|---|---|
| QR thanh toán trên bill | ✔ | ? | ✔ | ? | ✔ | ✔ | ? | ? |
| Hoá đơn điện tử từ máy tính tiền | ? | ? | ? | ✔ | ✔ | ✔ | – | – |
| Gửi hoá đơn qua SMS / email / Zalo | ✘ | ? | ? | ? | ? | ? | ✔ (SMS/email) | ? |
| Logo, header, footer | ✔ (mẫu HTML) | ? | ✔ | ✔ | ? | ? | ✔ | ✔ |
| Tem dán ly | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Tem mã vạch bán lẻ | ? | ? | ✔ | – | ? | ✔ | ✔ | ✔ |
| Phân quyền in tạm tính / in lại | ? | ? | ✔ | ? | ✔ | ? | ? | ? |
| In thử | ✔ (nhận diện máy) | ✔ | ? | ✔ | ? | ? | ✔ | ? |

Cột EasyPOS dựa trên những gì đã thấy trong code của `print_config` và `printer_label`. Mục nào ghi "?" ở cột này
cần đội sản phẩm xác nhận lại.

---

## 4. Điểm đáng học từ từng hãng

### KiotViet: chuẩn tham khảo cho in bếp ở Việt Nam

- **Lịch sử báo bếp:** có trạng thái "Lỗi in chế biến" và nút **in lại các món in lỗi**.
- **Cảnh báo lỗi in:** kẹt giấy, hết giấy, mất kết nối.
- **Tách thành phần combo** về đúng máy in của từng món.
- **In báo chuyển bàn.** Có thể tắt in báo huỷ món.
- **"In chế biến qua máy POS":** một máy POS in tập trung cho các thiết bị khác. Trang hướng dẫn có cảnh báo về nguy cơ **in trùng** khi bật cùng lúc với app khác, nên đáng học cả cách họ tránh in trùng.
- **Mỗi máy POS một máy in hoá đơn**; máy bếp và máy tem thì được nhiều máy.

### Sapo: đẩy mạnh cập nhật 2025

- **In tem theo hình thức phục vụ:** bật/tắt riêng cho tại bàn, mang đi, giao hàng, đối tác.
- **QR thanh toán in kèm hoá đơn**, số tiền tự lấy theo tổng đơn.
- **In tạm tính chỉ cho tài khoản có quyền.**
- **In lại phiếu bếp cho đơn giao hàng** (Grab, GoFood, Ahamove).
- **In tem mã vạch trên mobile**, có mẫu tuỳ chỉnh, mã 1D và QR.

### iPOS / FABi và CukCuk: hướng tới KDS

- **Đẩy đơn tới khu chế biến qua máy in hoặc KDS.** KDS hiện trạng thái đã nhận, đang làm, hoàn thành.
- **CukCuk khuyên dùng tablet thay máy in ở bếp:** tiết kiệm giấy, cộng dồn số suất cùng món, báo phục vụ bằng một chạm.
- **iPOS giới hạn bỏ món sau khi đã in tạm tính** (chống gian lận). Có phân quyền in lại hoá đơn.
- **Xuất hoá đơn điện tử ngay khi thanh toán.**

### Toast

- **Phiếu tổng (expo)** bên cạnh phiếu của từng trạm, cho người điều phối ra món.
- **Cỡ chữ phiếu bếp theo từng máy in.** Đổi cỡ chữ cần quyền cài đặt máy in.
- **Định tuyến lại theo hình thức phục vụ:** đơn mang đi, giao hàng, online in ở trạm khác.
- **Màn "Trạng thái thiết bị"** cho xem lệnh in lỗi hoặc đang chờ. Máy in có lại thì in tiếp hàng đợi.
- **Cảnh báo cấu hình in trùng:** một máy vừa là bếp vừa là expo thì in 2 phiếu.

### Square

- **Tuỳ chọn định dạng phiếu bếp phong phú nhất:**
  - mỗi món một phiếu, phiếu thu gọn, ẩn footer, chỉnh lề;
  - cỡ chữ S/M/L, sắp xếp món theo thứ tự nhập / A-Z / danh mục;
  - **tên món riêng cho bếp**, gộp các món giống hệt nhau.
- **Đơn online chỉ tự in trên một thiết bị được chỉ định**, để tránh in trùng khi có nhiều máy POS.
- **Giữ món theo đợt (Hold & Fire):** course 1 mặc định in ngay, các course sau mặc định giữ lại.
- **Điểm yếu:** cộng đồng phàn nàn **không có máy in dự phòng** và **mất phiếu mà không có cảnh báo**.

### Lightspeed K-Series

- **Mỗi khu vực một danh sách máy in theo thứ tự ưu tiên.** In lỗi ở máy chính thì tự thử máy tiếp theo.
- **Tuỳ chọn in header "BACKUP PRINTER"** trên phiếu đi sang máy dự phòng.
- **Profile in gán theo thiết bị POS hoặc theo sơ đồ bàn.**

### Loyverse

- **Phiếu bổ sung khi sửa đơn:** thêm món thì in phiếu mới, xoá món thì in phiếu huỷ.
- **Phiếu in lại có dấu "Reprint".** Chỉ in lại được trong vòng 2 giờ sau khi đóng đơn.

---

## 5. Danh sách tính năng đề xuất

Mỗi mục ghi: **Hãng đã có** (theo mục 3), **Giá trị**, **Độ khó**, **Ghi chú kỹ thuật**.

### 5.1. Độ tin cậy

| # | Tính năng | Hãng đã có | Giá trị | Độ khó |
|---|---|---|---|---|
| R1 | **Lịch sử lệnh in + in lại phiếu lỗi**: mỗi lệnh in có trạng thái; màn xem phiếu lỗi, bấm in lại hoặc in sang máy khác | KiotViet, Toast | **Rất cao** | Trung bình–Cao |
| R2 | **Cảnh báo máy in** (mất kết nối, hết giấy, mở nắp) trên màn bán hàng | KiotViet, Toast | Cao | Trung bình |
| R3 | **Máy in dự phòng**: danh sách máy theo thứ tự ưu tiên cho mỗi khu vực, phiếu chuyển hướng có header "MÁY DỰ PHÒNG – Bếp 1" | Lightspeed, Toast | Cao, **chưa thấy hãng Việt Nam nào có** | Trung bình (cần R1) |
| R4 | **Dấu "IN LẠI"** trên phiếu bếp và hoá đơn in lại | Loyverse | Cao | Thấp |
| R5 | **In tập trung qua một thiết bị**, và đơn online chỉ tự in trên một thiết bị được chỉ định | KiotViet, Square (chỉ đơn online) | Cao | Cao |

Ghi chú:
- **R1:** lỗi xảy ra **trước khi gửi byte** (`NO_CONNECTION`, `LAN_BUSY`, `LAN_TIMEOUT`) thì tự thử lại. Lỗi **giữa chừng** (`LAN_SEND_FAILED`) thì không tự in lại, mà đánh dấu "cần kiểm tra". Đây là R9 trong IN_LAN_ON_DINH.md.
- **R2:** hỏi trạng thái bằng `DLE EOT` theo chu kỳ dài, chỉ khi máy in rảnh. Phải sửa lỗi A1 trước (hỏi trạng thái mở socket LAN mà không nhả).
- **R5:** app đã có `mqtt_client`, có thể dùng làm kênh đẩy lệnh in.

### 5.2. Phiếu bếp

| # | Tính năng | Hãng đã có | Giá trị | Độ khó |
|---|---|---|---|---|
| K1 | **Tuỳ chọn định dạng theo khu vực**: mỗi món một phiếu / gộp, gộp món giống nhau, cỡ chữ, cách sắp xếp, phiếu thu gọn | KiotViet, Square, Loyverse | Cao | Thấp–Trung bình |
| K2 | **Tên món riêng cho bếp** (tên ngắn, tên nội bộ) | Square | Trung bình | Thấp |
| K3 | **Tách thành phần combo** về đúng bếp của từng món | KiotViet | Cao (quán có combo) | Trung bình |
| K4 | **Phiếu chuyển bàn / gộp bàn** gửi xuống bếp | KiotViet | Trung bình | Thấp |
| K5 | **Ghi chú / topping nổi bật** (in đậm, đảo màu), món huỷ có gạch ngang | – | Cao | Thấp |
| K6 | **Định tuyến theo hình thức phục vụ**: đơn mang đi / giao hàng in ở khu khác, tem chỉ in cho đơn mang đi | Toast, Square, Sapo | Trung bình–Cao | Trung bình |
| K7 | **Phiếu tổng (expo)** cho người điều phối ra món | Toast | Trung bình (nhà hàng lớn) | Thấp–Trung bình |
| K8 | **Giữ món / lên món theo đợt** | Toast, Square | Trung bình–Cao | Trung bình |
| K9 | **Màn hình bếp (KDS)** chạy song song với máy in | CukCuk, iPOS, Toast, Square | **Rất cao** | Cao |

Ghi chú:
- **K1, K2:** phần lớn chỉ là sửa mẫu in HTML và thêm vài cấu hình cho máy in.
- **K7:** cần cảnh báo cấu hình in trùng như Toast (một máy vừa là bếp vừa là expo).

### 5.3. Hoá đơn và tem

| # | Tính năng | Hãng đã có | Giá trị | Độ khó |
|---|---|---|---|---|
| B1 | **Hoá đơn điện tử từ máy tính tiền + mã tra cứu / QR trên bill** | CukCuk, iPOS, Pos365 | **Bắt buộc** (đối thủ đã có) | Trung bình |
| B2 | **QR thanh toán động** theo đúng số tiền, tự đối soát | Sapo, iPOS, Pos365 | Rất cao | Trung bình |
| B3 | **Gửi hoá đơn qua Zalo / SMS / email**, tuỳ chọn không in giấy | Toast (SMS/email) | Trung bình–Cao, **chưa thấy hãng Việt Nam nào có** | Trung bình |
| B4 | **In tem mã vạch hàng loạt** cho bán lẻ (từ phiếu nhập, có mẫu tem) | Sapo, Toast, Square | Cao (bán lẻ) | Trung bình |
| B5 | **Đánh dấu "BẢN SAO" và "CHƯA THANH TOÁN"** trên hoá đơn in lại và tạm tính | – | Trung bình | Thấp |

Ghi chú:
- **B1:** đây là lợi thế sân nhà của Softdreams. Nên làm luồng xuất hoá đơn **nhanh và ổn định hơn** đối thủ, thay vì chỉ "cũng có".
- **B2:** đã có loại phiếu `paymentQR`. Cần kiểm tra đã là QR động theo đơn và đã đối soát tự động chưa.
- **B4:** đã có in tem TSPL, cần thêm màn chọn sản phẩm và mẫu tem.

### 5.4. Quản trị và chống gian lận

| # | Tính năng | Hãng đã có | Giá trị | Độ khó |
|---|---|---|---|---|
| Q1 | **Phân quyền in tạm tính / in lại** | Sapo, iPOS, Clover (c) | Cao | Thấp–Trung bình |
| Q2 | **Khoá bỏ món sau khi đã in tạm tính** (hoặc bắt quản lý duyệt) | iPOS | Cao | Trung bình |
| Q3 | **Nhật ký in + báo cáo** "tạm tính in nhiều lần nhưng đơn bị huỷ" | – | Cao | Trung bình |
| Q4 | **Quyền riêng để sửa cấu hình máy in** | Toast | Trung bình | Thấp |

### 5.5. Cài đặt và tốc độ

| # | Tính năng | Hãng đã có | Giá trị | Độ khó |
|---|---|---|---|---|
| C1 | **Trình hướng dẫn cài máy in**: quét → kêu bíp xác nhận → chọn chức năng → in thử, có kiểm tra lỗi thường gặp | Một phần ở KiotViet, Sapo | Cao | Trung bình |
| C2 | **Âm báo bếp** khi có phiếu mới (còi máy in / chuông qua cổng két) | – (chưa thấy nguồn) | Trung bình | Thấp |
| C3 | **In phiếu bếp bằng chữ** thay vì ảnh: dữ liệu nhỏ hơn hàng chục lần, chịu mạng yếu tốt | – | Cao | Trung bình–Cao |
| C4 | **Chỉnh độ đậm** theo từng máy in | – | Trung bình | Thấp |

Ghi chú:
- **C1:** phần lớn chức năng đã có, chủ yếu là ghép thành một luồng.
- **C2:** bộ lệnh còi đã có sẵn trong `PrinterLabel._identifyPayload`.
- **C3:** tiếng Việt có dấu phụ thuộc bảng mã của máy in, nên cần chế độ lai: chữ cho nội dung, ảnh cho logo / QR.
- **C4:** ngưỡng đen-trắng hiện cố định 200 trong `getEscPosRasterBytes`.

---

## 6. Bảng ưu tiên

Tiêu chí: **bắt kịp đối thủ trước** (tính năng họ đã có), rồi mới đến **tạo khác biệt**.

| Đợt | Tính năng | Lý do |
|---|---|---|
| **1. Làm ngay (ít công)** | R4 dấu "IN LẠI", B5 "BẢN SAO / CHƯA THANH TOÁN", K5 ghi chú nổi bật, K2 tên món cho bếp, C2 âm báo bếp | Vài ngày công, giảm sai món ngay |
| | Q1 phân quyền in tạm tính / in lại | Sapo và iPOS đã có |
| **2. Bắt kịp đối thủ** | **R1 lịch sử lệnh in + in lại phiếu lỗi**, R2 cảnh báo máy in | KiotViet đã có; đây là điểm đau giờ cao điểm |
| | **B1 hoá đơn điện tử từ máy tính tiền** | CukCuk, iPOS, Pos365 đã có; là sân nhà Softdreams |
| | K1 định dạng phiếu theo khu vực, K3 tách combo, K4 phiếu chuyển bàn | KiotViet đã có |
| | B2 QR thanh toán động | Sapo, iPOS, Pos365 đã có |
| **3. Tạo khác biệt** | **R3 máy in dự phòng** | Chưa thấy hãng Việt Nam nào có |
| | **B3 hoá đơn qua Zalo** | Chưa thấy hãng Việt Nam nào có, hợp thói quen người Việt |
| | Q2 + Q3 chống gian lận tạm tính | Chủ quán rất quan tâm |
| | C3 in phiếu bếp bằng chữ | Nhanh và ổn định hơn trên Wi-Fi yếu |
| **4. Dài hạn** | K9 màn hình bếp (KDS) | CukCuk, iPOS đã có; là tính năng lớn |
| | R5 in tập trung + đơn online / QR tại bàn tự in | Nền tảng cho gọi món tự phục vụ |
| | K6 định tuyến theo hình thức phục vụ, K7 phiếu expo, K8 giữ món theo đợt | Nhà hàng phục vụ bàn |
| | B4 tem mã vạch bán lẻ, C1 trình hướng dẫn cài đặt | Mở rộng sang bán lẻ, giảm tải CSKH |

**Song song với mọi đợt:** xử lý các rủi ro mức Cao trong [RUI_RO_IN_LAN_USB.md](RUI_RO_IN_LAN_USB.md) (A1–A4, U2, U3).
R1–R3 đặc biệt cần nền in ổn định thì mới báo lỗi và in lại đúng.

---

## 7. Ý tưởng chưa thấy ở hãng nào

Không tìm thấy nguồn công khai cho các ý tưởng dưới đây. Đây có thể là điểm khác biệt, nhưng cũng có thể đối thủ có
mà không công bố.

- **Báo cáo sức khoẻ máy in cho CSKH:** tỉ lệ in lỗi theo máy in, chi nhánh, giờ trong ngày, để chủ động gọi cho quán có mạng kém. Đã có `PrinterTelemetryService`, chỉ cần thêm dashboard.
- **Đo chất lượng mạng tới máy in** trước giờ cao điểm, cảnh báo "Wi-Fi quán đang yếu". EasyPOS đã có `checkLanQuality`.
- **Tự tìm lại máy in đổi IP theo MAC.** EasyPOS đã có; nên đưa vào tài liệu bán hàng như một điểm mạnh.
- **Âm báo bếp qua còi máy in hoặc chuông ngoài.**

---

## 8. Nguồn tham khảo

### Việt Nam

- KiotViet – In Bar-Bếp (KVPrinter), cập nhật 30/10/2022: https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/in-bar-bep-kvprinter/su-dung-in-bar-bep/
- KiotViet – Ứng dụng máy POS Nhà hàng: https://www.kiotviet.vn/ung-dung-kiotviet-cafe-nha-hang-touchscreen/
- KiotViet – Cài đặt máy in FnB trên mobile, 29/11/2022: https://www.kiotviet.vn/cai-dat-may-in-fnb-man-mobile/
- KiotViet – Phần mềm quản lý nhà hàng: https://www.kiotviet.vn/phan-mem-quan-ly-nha-hang/
- Sapo – Tìm IP máy in và kết nối tự động, 25/03/2025: https://www.sapo.vn/cap-nhat-tinh-nang/tinh-nang-tim-kiem-ip-may-in-ket-noi-tu-dong-tren-sapo
- Sapo – Nâng cấp tính năng in, 27/03/2025: https://www.sapo.vn/cap-nhat-tinh-nang/nang-cap-tinh-nang-in
- Sapo – In mã QR kèm hoá đơn, 28/03/2025: https://www.sapo.vn/cap-nhat-tinh-nang/in-ma-qr-kem-hoa-don-ban-hang
- Sapo – In tem mã vạch trên app mobile, 14/04/2025: https://www.sapo.vn/cap-nhat-tinh-nang/in-tem-ma-vach-mobile-app
- Sapo – Xử lý lỗi máy in từ quầy ra bếp: https://www.sapo.vn/blog/cach-xu-ly-loi-ky-thuat-may-in-tu-quay-ra-bep
- CukCuk – Trang chủ: https://www.cukcuk.vn/
- CukCuk – Nên triển khai máy in nào cho bếp/bar: https://trienkhai.cukcuk.vn/en/nen_trien_khai_loai_may_in_nao_cho_bepbar1.htm
- CukCuk – Thiết lập máy in cho thu ngân và bếp/bar: https://trienkhai.cukcuk.vn/en/lam_the_nao_de_thiet_lap_may_in_cho_thu_ngan_va_bepbar1.htm
- iPOS – FABi: https://ipos.vn/en/san-pham/phan-mem-quan-ly-ban-hang-ipos-fabi/
- iPOS – FABiBox, cập nhật 27/11/2025: https://ipos.vn/en/fabibox-mobile/
- Pos365 – Trang chủ: https://www.pos365.vn/

### Quốc tế

- Toast – Prep stations: https://support.toasttab.com/en/article/Prep-Stations-Basics
- Toast – Expediter: https://support.toasttab.com/en/article/Setting-Up-an-Expediter
- Toast – Print routing by dining option: https://support.toasttab.com/en/article/Print-Routing-by-Dining-Option
- Toast – Font sizes for kitchen tickets: https://support.toasttab.com/en/article/Font-Sizes-for-Kitchen-Tickets
- Toast – Course firing: https://support.toasttab.com/en/article/Automated-and-Expediter-Course-Firing
- Toast – Device status on POS: https://intercom.help/toast-central/en/articles/14727556-device-status-on-pos
- Toast – Printers going offline: https://support.toasttab.com/en/article/Get-Help-With-Printers-Going-Offline
- Toast – Offline mode: https://doc.toasttab.com/doc/platformguide/platformOfflineMode.html
- Toast – Item label printer: https://support.toasttab.com/en/article/Toast-Item-Label-Printer-Quick-Start-Guide
- Toast – Digital receipts: https://doc.toasttab.com/doc/platformguide/platformPwfDigitalReceipts.html
- Square – Printer profiles: https://squareup.com/help/us/en/article/8245-set-up-printer-profiles
- Square – Hold and fire courses: https://squareup.com/help/article/8172-hold-and-fire-courses-with-square-kds-and-square-for-restaurants
- Square – Receipt customization: https://squareup.com/help/us/en/article/5424
- Square – Không có máy in dự phòng (cộng đồng, 2021): https://sellercommunity.com/t5/Square-for-Restaurants/Can-Square-offer-back-up-print-routing-if-a-printer-down-down/m-p/283018
- Lightspeed K-Series – About printing: https://k-series-support.lightspeedhq.com/hc/articles/1260804606770-About-printing
- Lightspeed K-Series – Fallback printers: https://k-series-support.lightspeedhq.com/hc/articles/1260804607010
- Loyverse – Kitchen printers: https://help.loyverse.com/help/kitchen-printers
- Loyverse – KDS: https://help.loyverse.com/help/kds-configuration
