import Flutter
import PrinterSDK
import UIKit

final class ESCPosPrinter {
    weak var plugin: PrinterLabelPlugin?

    func printImageESC(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let imageData = args["image"] as? FlutterStandardTypedData
        else {
            result(FlutterError(code: "INVALID_ARGS", message: "image missing", details: nil))
            return
        }

        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String
        let paperSize = args["size"] as? Int
        // Số bản in. Nhân dữ liệu ngay tại đây thay vì để tầng Dart gọi print nhiều lần:
        // mỗi lời gọi là một job riêng trong hàng đợi của máy in, nên giữa hai bản có
        // khoảng trống không job nào giữ socket — với máy in LAN dùng chung, socket bị nhả
        // ngay ở đó và bản kế phải mở lại, đụng socket chưa giải phóng hẳn -> in chậm và có
        // bản không ra. Gộp ở đây thì cả lượt in đi trong MỘT job liên tục.
        let quantity = max(1, (args["quantity"] as? Int) ?? 1)

        buildAndSendESC(
            imageData: imageData,
            paperSize: paperSize,
            isBluetooth: Self.isBluetoothTarget(args: args)
        ) { [weak self] printData in
            guard let self = self, let oneCopy = printData else {
                result(FlutterError(code: "BUILD_FAILED", message: "Cannot build ESC command", details: nil))
                return
            }
            var data = oneCopy
            if quantity > 1 {
                data.reserveCapacity(oneCopy.count * quantity)
                for _ in 1..<quantity { data.append(oneCopy) }
            }
            // Chờ kết quả THẬT rồi mới trả về Dart (trước đây báo true ngay khi xếp hàng).
            guard let plugin = self.plugin else { result(false); return }
            // Hỏi cảm biến giấy/nắp trước khi gửi (chỉ LAN): hết giấy thì không gửi bill.
            plugin.sendAndReply(data, deviceId: deviceId, connectionType: connectionType,
                                checkPaper: true, result: result)
        }
    }

    // Build ESC/POS command bytes từ image data.
    // Dùng cho cả printImageESC và printAll để tránh duplicate code.
    //
    // Tôn trọng "quantity" trong [args]: trả về dữ liệu đã nhân đủ số bản, để cả lượt in
    // đi trong MỘT job (xem lý do ở printImageESC).
    func buildAndSendESC(
        imageData: FlutterStandardTypedData,
        args: [String: Any],
        completion: @escaping (Data?) -> Void
    ) {
        let paperSize = args["size"] as? Int
        let isBluetooth = Self.isBluetoothTarget(args: args)
        let quantity = max(1, (args["quantity"] as? Int) ?? 1)
        buildAndSendESC(
            imageData: imageData,
            paperSize: paperSize,
            isBluetooth: isBluetooth
        ) { oneCopy in
            guard let oneCopy = oneCopy else {
                completion(nil)
                return
            }
            guard quantity > 1 else {
                completion(oneCopy)
                return
            }
            var data = oneCopy
            data.reserveCapacity(oneCopy.count * quantity)
            for _ in 1..<quantity { data.append(oneCopy) }
            completion(data)
        }
    }

    /// Kết nối đích có phải Bluetooth/BLE hay không — quyết định cách chia lệnh raster.
    /// Khớp với logic định tuyến trong `PrinterLabelPlugin.sendToPrinter`.
    static func isBluetoothTarget(args: [String: Any]) -> Bool {
        if (args["connection_type"] as? String) == "Bluetooth" { return true }
        // Không có connection_type: deviceId dạng UUID là BLE, dạng "LAN:<ip>" là LAN.
        if let id = args["device_id"] as? String {
            return !id.uppercased().hasPrefix("LAN:")
        }
        return false
    }

    /// [isBluetooth] hiện KHÔNG còn ảnh hưởng cách dựng lệnh raster: mọi kết nối đều chia
    /// dải 128 dòng (xem lý do ở phần dựng `bandHeight` bên dưới). Giữ tham số để không
    /// phải đổi các lời gọi sẵn có và để dành khi cần phân biệt kết nối trở lại.
    func buildAndSendESC(
        imageData: FlutterStandardTypedData,
        paperSize: Int?,
        isBluetooth: Bool = false,
        completion: @escaping (Data?) -> Void
    ) {
        guard let image = UIImage(data: imageData.data) else {
            completion(nil)
            return
        }

        let targetWidth: CGFloat
        switch paperSize {
        case 58:  targetWidth = 384
        case 80:  targetWidth = 576
        case 384, 576: targetWidth = CGFloat(paperSize!)
        default:  targetWidth = 576
        }

        let scale = targetWidth / image.size.width
        let targetHeight = image.size.height * scale

        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: targetWidth, height: targetHeight),
            false, 1.0
        )
        image.draw(in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = resized?.cgImage else {
            completion(nil)
            return
        }

        // Dựng lệnh raster THỦ CÔNG, giống hệt Android (PrinterThermal.getEscPosRasterBytes).
        //
        // MỌI kết nối đều CHIA DẢI 128 dòng, mỗi dải là một lệnh `GS v 0` độc lập.
        //
        // Máy in ESC/POS giới hạn chiều cao MỖI lệnh raster (nhiều model chỉ nhận vài trăm
        // dòng/lệnh). Nhồi cả bill vào MỘT lệnh thì đơn ngắn vừa đủ nên chạy tốt, nhưng đơn
        // dài sinh ảnh cao hàng nghìn dòng, vượt giới hạn -> máy in HỦY chế độ raster và
        // diễn giải các byte ảnh còn lại thành VĂN BẢN. Giấy ra đầy ký tự rác lặp lại
        // (`0p0380aa0p8sç80`...), không cắt giấy. Đã quan sát trực tiếp trên máy RICHTA qua
        // BLE ở iOS với đơn dài.
        //
        // LỊCH SỬ — vì sao trước đây BLE dùng một lệnh duy nhất: để chữa lỗi firmware in ra
        // chuỗi chẩn đoán (`NVLogo PIC`, `psxMax ...`) xen giữa ảnh khi các dải tới chậm hơn
        // khả năng đồng bộ của firmware. Nhưng cách đó đổi một lỗi lấy một lỗi NẶNG HƠN:
        // đơn ngắn hết rác, còn đơn dài thì rác toàn bộ. Nguyên nhân dải tới chậm là NHỊP
        // GỬI quá nhanh so với tốc độ in, và việc đó đã được sửa đúng chỗ trong
        // BLEManager.writeData (ngân sách nghỉ ~86µs/byte theo BYTE, khớp Android). Android
        // vẫn chia dải 128 cho BLE và không gặp cả hai lỗi — đó là bằng chứng chia dải là
        // đúng, miễn nhịp gửi đủ chậm.
        let bandHeight = 128
        guard let rasterBytes = escPosRasterBytes(from: cgImage, bandHeight: bandHeight) else {
            completion(nil)
            return
        }

        var out = Data()
        out.append(contentsOf: [0x1B, 0x40])              // ESC @  — initialize
        out.append(contentsOf: [0x1B, 0x61, 0x01])        // ESC a 1 — căn giữa
        out.append(rasterBytes)                            // GS v 0 — ảnh raster (một lệnh duy nhất)
        out.append(contentsOf: [0x0A, 0x0A, 0x0A, 0x0A, 0x0A]) // feed 5 dòng
        out.append(contentsOf: [0x1D, 0x56, 0x42, 0x01])  // GS V 66 1 — cắt giấy

        completion(out)
    }

    func openDrawer(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        do {
            let args = call.arguments as? [String: Any]
            let deviceId = args?["device_id"] as? String
            let connectionType = args?["connection_type"] as? String

            var out = Data()
            out.append(contentsOf: [0x1B, 0x70, 0x00, 0x19, 0xFA, 0x1B, 0x70, 0x01, 0x19, 0xFA])
            // Dart openDrawer() nhận bool: trả false khi thật sự không gửi được lệnh mở két.
            guard let plugin = plugin else { result(false); return }
            plugin.sendToPrinter(out, deviceId: deviceId, connectionType: connectionType) { ok, _ in
                result(ok)
            }
        } catch {
            print("[ESCPosPrinter] ❌ openDrawer error: \(error)")
            result(false)
        }
    }

    /// Chuyển [cgImage] thành lệnh ESC/POS `GS v 0`, chia thành các dải cao
    /// tối đa [bandHeight] dòng (mỗi dải là một lệnh `GS v 0` độc lập).
    /// Truyền `bandHeight >= chiều cao ảnh` để có đúng một lệnh cho toàn ảnh.
    /// Ngưỡng nhị phân hóa 200 và điều kiện alpha > 50 khớp với bản Android
    /// để hai nền tảng cho ra bản in giống nhau.
    private func escPosRasterBytes(from cgImage: CGImage, bandHeight: Int) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let widthBytes = (width + 7) / 8

        // Đọc pixel về RGBA8 để tính grayscale giống công thức bên Android.
        //
        // Bộ đệm phải do TA tự cấp phát, KHÔNG được truyền `&pixels` của mảng Swift vào
        // `CGContext(data:)`. Con trỏ lấy qua `&` chỉ được bảo đảm hợp lệ TRONG lời gọi
        // đó; sau khi CGContext khởi tạo xong, Swift được phép di chuyển/huỷ bộ đệm của
        // mảng. `ctx.draw` và vòng đọc `pixels` bên dưới khi ấy ghi/đọc qua con trỏ đã
        // chết -> EXC_BAD_ACCESS (code=50). Lỗi này là hành vi KHÔNG XÁC ĐỊNH: trước đây
        // tình cờ chạy được vì vòng lặp nhỏ, nhưng khi chia dải 128 dòng thì vòng lặp dài
        // hơn làm cách cấp phát thay đổi và crash lộ ra.
        let byteCount = width * height * 4
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        pixels.initialize(repeating: 0, count: byteCount)
        defer { pixels.deallocate() }

        guard let ctx = CGContext(
            data: pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Một dải không được cao quá 65535 dòng, vì yL/yH chỉ có 2 byte. `UInt8(...)`
        // trong Swift là khởi tạo CHẶT: giá trị vượt 255 sẽ crash chứ không cắt bit âm
        // thầm như `.toByte()` bên Kotlin — nên phải kẹp trước khi dựng header.
        let rows = max(1, min(bandHeight, 65535))

        var data = Data(capacity: 8 + widthBytes * height)

        var y0 = 0
        while y0 < height {
            let bandRows = min(rows, height - y0)

            // GS v 0 m xL xH yL yH — yL/yH là chiều cao của DẢI này.
            data.append(contentsOf: [
                0x1D, 0x76, 0x30, 0x00,
                UInt8(widthBytes % 256), UInt8(widthBytes / 256),
                UInt8(bandRows % 256), UInt8(bandRows / 256)
            ])

            for y in y0..<(y0 + bandRows) {
                for xByte in 0..<widthBytes {
                    var byteVal: UInt8 = 0
                    for bit in 0..<8 {
                        let x = xByte * 8 + bit
                        guard x < width else { continue }
                        let idx = (y * width + x) * 4
                        let alpha = Int(pixels[idx + 3])
                        guard alpha > 50 else { continue }
                        let red = Double(pixels[idx])
                        let green = Double(pixels[idx + 1])
                        let blue = Double(pixels[idx + 2])
                        let gray = Int(0.299 * red + 0.587 * green + 0.114 * blue)
                        // Ngưỡng 200 — KHÔNG hạ về 128 (xem lịch sử: 128 gây in mờ).
                        //
                        // Đầu in nhiệt chỉ có 1 bit: cháy hoặc trắng, không có mức xám. Chữ do
                        // Flutter render là anti-alias nên mỗi nét gồm lõi đậm bọc bởi dải xám.
                        // Ngưỡng 200 cho cháy tới xám 199 -> nét đủ dày. Ngưỡng 128 loại sạch
                        // dải 129-199; với cỡ chữ nhỏ dải này chiếm phần lớn nét nên chỉ còn bộ
                        // xương mảnh -> bản in RẤT MỜ (đã ghi nhận trên máy BLE ở cả iOS và
                        // Android).
                        //
                        // Giữ khớp với Android (PrinterThermal.kt) và với `binarized(threshold:)`
                        // trong PrinterLabelPlugin.swift — cả hai đều dùng 200.
                        if gray < 200 {
                            byteVal |= (1 << (7 - bit))
                        }
                    }
                    data.append(byteVal)
                }
            }

            y0 += bandRows
        }

        return data
    }
}
