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

        buildAndSendESC(
            imageData: imageData,
            paperSize: paperSize,
            isBluetooth: Self.isBluetoothTarget(args: args)
        ) { [weak self] printData in
            guard let self = self, let data = printData else {
                result(FlutterError(code: "BUILD_FAILED", message: "Cannot build ESC command", details: nil))
                return
            }
            self.plugin?.sendToPrinter(data, deviceId: deviceId, connectionType: connectionType)
            result(true)
        }
    }

    // Build ESC/POS command bytes từ image data.
    // Dùng cho cả printImageESC và printAll để tránh duplicate code.
    func buildAndSendESC(
        imageData: FlutterStandardTypedData,
        args: [String: Any],
        completion: @escaping (Data?) -> Void
    ) {
        let paperSize = args["size"] as? Int
        let isBluetooth = Self.isBluetoothTarget(args: args)
        buildAndSendESC(
            imageData: imageData,
            paperSize: paperSize,
            isBluetooth: isBluetooth,
            completion: completion
        )
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
        // Số dòng ảnh trên MỖI lệnh `GS v 0` phải chọn theo loại kết nối — hai kết nối
        // hỏng theo hai kiểu ngược nhau:
        //
        // • BLE: gửi MỘT lệnh duy nhất cho cả ảnh. KHÔNG dùng nhiều dải (và cũng không
        //   dùng PTCommandESC.appendRasterImage(..., package: true), vì nhánh package của
        //   SDK chia ảnh thành nhiều lệnh liên tiếp). Máy in phải xử lý xong dải này mới
        //   nhận dải kế; khi in 2 máy BLE cùng lúc, băng thông mỗi máy giảm và các dải tới
        //   chậm hơn khả năng đồng bộ của firmware, làm nó rớt khỏi trạng thái nhận raster
        //   rồi diễn giải byte ảnh còn lại thành LỆNH/TEXT — giấy in ra chuỗi chẩn đoán
        //   của firmware (`NVLogo PIC`, `psxMax ...`) xen giữa ảnh.
        //
        // • LAN: phải CHIA DẢI. Máy in ESC/POS giới hạn chiều cao mỗi lệnh raster (Epson
        //   chỉ nhận vài trăm dòng/lệnh). Đơn ngắn thì vừa, nhưng đơn dài sinh ảnh cao
        //   hàng nghìn dòng, vượt giới hạn -> máy in hủy chế độ raster và in ra ký tự rác,
        //   không cắt giấy, treo luôn các job sau. LAN không gặp lỗi kiểu BLE ở trên vì
        //   TCP băng thông cao và NWConnection gửi tuần tự đúng thứ tự.
        //
        // Đây cũng là cách Android đang làm (bên đó LAN/USB để SDK `printBitmap` tự chia).
        let bandHeight = isBluetooth ? cgImage.height : 128
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
            let sent = plugin?.sendToPrinter(out, deviceId: deviceId, connectionType: connectionType) ?? false
            result(sent)
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
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels,
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
                        // Ngưỡng 200 giúp chữ in ra đen đậm, sắc nét (giống Android)
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
