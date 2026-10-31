# Audit tốc độ & chất lượng in — việc cần làm

> Ghi lại để làm sau. Xem thêm code tại `ios/Classes/BLEManager.swift`,
> `android/src/main/kotlin/com/printer/printer_label/`, `lib/src/service/`.

## Tình trạng hiện tại

Chưa tối ưu tối đa. Hai điểm nghẽn lớn nhất là **không nén dữ liệu bitmap**
và **chunk/delay BLE trên iOS cố định, không thích ứng**. Về chất lượng,
đang dùng threshold nhị phân đơn giản, chưa có dithering.

## Điểm nghẽn

### 1. Không nén dữ liệu bitmap trước khi gửi (ưu tiên cao nhất)

- TSPL trên cả Android và iOS đang gửi bitmap raw, không nén.
- Một tem 100×150mm ở 203dpi ≈ 120KB chưa nén. Qua Bluetooth (~16KB/s
  thực tế), riêng bước truyền mất ~7-8 giây/tem — đây là phần chiếm tỷ
  trọng lớn nhất trong tổng thời gian in.
- SDK máy in đã có sẵn API nén (RLE/TIFF-pack-bits) nhưng code không gọi
  tới:
  - Android: `TSPLPrinter.bitmap(...)` đang dùng thay vì
    `TSPLPrinter.bitmapCompression(...)` — `PrinterLabelPlugin.kt:750-757`.
  - iOS: `compress: .none` trong `PrinterLabelPlugin.swift:415-418` và
    `ESCPosPrinter.swift:83`.
- Chỉ cần đổi tham số gọi hàm, SDK đã hỗ trợ sẵn thuật toán.

### 2. BLE iOS: chunk cố định 180 byte + delay tĩnh 25ms/gói

- `ios/Classes/BLEManager.swift:162-163` — `safeMaxChunkSize = 180`,
  không dựa trên MTU thật negotiate được với từng máy in.
- `ios/Classes/BLEManager.swift:176-184` — dùng `Thread.sleep` cố định
  25ms cho mỗi gói `.withResponse`, không dựa trên callback ACK thật
  (`peripheral(_:didWriteValueFor:)`).
- Hệ quả: máy in nhanh bị làm chậm giả tạo; máy chậm vẫn có nguy cơ tràn
  buffer nếu ước tính 16KB/s sai cho thiết bị đó.
- Cách đúng hơn: chunk theo MTU thật + chờ callback ACK thay vì sleep.
- **Cần benchmark trên máy in thật trước khi nới lỏng** — giới hạn 180
  byte có thể do lo ngại tràn buffer của một số dòng máy cụ thể.

### 3. Chưa có dithering — chỉ threshold nhị phân

- Đang ép mọi pixel về đen/trắng tuyệt đối ở ngưỡng cố định 200
  (`binarized(threshold:200)`), dù cả 2 SDK hãng đều hỗ trợ sẵn:
  - Android: `AlgorithmType.Dithering` (hiện dùng `AlgorithmType.Threshold`,
    `PrinterLabelPlugin.kt:756`).
  - iOS: mode dithering trong `appendRasterImage`
    (`ESCPosPrinter.swift:73,83`, hiện dùng `.binary`).
- Với text/barcode/QR: threshold hiện tại **là tối ưu, không cần đổi** —
  dithering sẽ làm mờ cạnh chữ nhỏ ở 203dpi.
- Với ảnh chụp thật / logo có gradient, bóng đổ: threshold làm mất hết
  chi tiết vùng xám, chỉ còn mảng đen/trắng cứng. Dithering sẽ cho kết
  quả nét và có chiều sâu hơn nhiều.
- **Lưu ý khi sửa**: phải bỏ đồng thời bước `binarized(threshold:200)`
  thủ công hiện tại. Nếu không, ảnh đã bị ép nhị phân từ trước khi đưa
  vào SDK, dithering của SDK sẽ nhận input không còn gray-scale để dither
  → vô nghĩa. Cần sửa đồng bộ cả hai chỗ.
- Nên có logic chọn thuật toán theo loại nội dung: có ảnh raster →
  dithering; chỉ text/vector → threshold (heuristic, không nên áp dụng
  dithering toàn cục).

### 4. Oversampling khi render bị lãng phí

- Đang render ảnh ở độ phân giải cao hơn cần thiết (~500dpi tương đương)
  rồi downscale về 203dpi để anti-alias
  (`label_from_widget.dart:41-42,91,127`).
- Nhưng bước threshold cứng ngay sau đó xóa sạch lợi ích của oversampling
  này — tốn CPU/bộ nhớ vô ích nếu vẫn giữ threshold.
- Nếu chuyển sang dithering (mục 3): giữ oversampling để nuôi dữ liệu
  gray-scale cho thuật toán dithering.
- Nếu vẫn dùng threshold cho text: có thể giảm oversampling để tiết kiệm
  tài nguyên, không ảnh hưởng chất lượng.

### 5. DPI hard-code 8 dots/mm (203dpi)

- `PrinterLabelPlugin.kt:723-724` và tương tự phía iOS — không đọc DPI
  thật của máy in.
- Chỉ ảnh hưởng khi dùng máy in 300dpi (sai tỷ lệ vật lý, không phải vấn
  đề độ nét).
- Ưu tiên thấp hơn các mục trên.

### 6. Nợ kỹ thuật: 2 công thức mm→px khác nhau

- `label_from_widget.dart:41` / `barcode_view.dart:29-30` dùng hằng số
  cứng 6.57.
- `image_resize.dart:70-72` dùng công thức đúng chuẩn `dpi / 25.4`.
- Không phải bug tốc độ/chất lượng trực tiếp, nhưng nên hợp nhất về một
  công thức `mmToPx(mm, dpi)` để dễ áp dụng đồng bộ các cải tiến DPI/
  dithering về sau.

## Kế hoạch làm theo thứ tự ưu tiên

1. **Bật nén bitmap TSPL** — đổi tham số gọi hàm nén sẵn có trong SDK.
   Tác động tốc độ lớn nhất, rủi ro thấp nhất.
2. **Nới chunk BLE iOS theo MTU thật + pacing theo callback ACK** thay vì
   sleep cố định. Cần benchmark trên máy in thật trước khi áp dụng.
3. **Thêm dithering như tùy chọn** cho nội dung có ảnh/gradient, giữ
   threshold mặc định cho text/barcode. Nhớ bỏ bước binarize thủ công khi
   bật dithering.
4. Đọc DPI thật của máy in thay vì hard-code.
5. (Thấp) Hợp nhất công thức mm→px giữa các file.

## Giới hạn cần lưu ý

SDK bên thứ 3 ở cả hai nền tảng là binary đóng gói (Android:
`net.posprinter` classes.jar obfuscated; iOS: `PrinterSDK.xcframework`),
không thể audit implementation nội bộ (chunk/delay thật bên trong
`sendSync`/`PTDispatcher`). Mọi thay đổi ở mục 1-3 **bắt buộc phải test
thực nghiệm trên máy in thật** trước khi đưa vào production — không thể
xác nhận hành vi chính xác chỉ qua đọc header/mã nguồn.
