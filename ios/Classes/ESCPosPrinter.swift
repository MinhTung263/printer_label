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

        buildAndSendESC(imageData: imageData, paperSize: paperSize) { [weak self] printData in
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
        buildAndSendESC(imageData: imageData, paperSize: paperSize, completion: completion)
    }

    func buildAndSendESC(
        imageData: FlutterStandardTypedData,
        paperSize: Int?,
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
        // KHÔNG dùng PTCommandESC.appendRasterImage(..., package: true): nhánh package
        // của SDK chia ảnh thành NHIỀU lệnh `GS v 0` liên tiếp. Máy in phải xử lý xong
        // dải này mới nhận dải kế; khi in 2 máy BLE cùng lúc, băng thông mỗi máy giảm
        // và các dải tới chậm hơn khả năng đồng bộ của firmware, làm nó rớt khỏi trạng
        // thái nhận raster rồi diễn giải byte ảnh còn lại thành LỆNH/TEXT — đó là lý do
        // giấy in ra chuỗi chẩn đoán của firmware (`NVLogo PIC`, `psxMax ...`) xen giữa
        // ảnh. Android không gặp lỗi vì luôn gửi MỘT lệnh `GS v 0` duy nhất cho cả ảnh.
        guard let rasterBytes = escPosRasterBytes(from: cgImage) else {
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

    /// Chuyển [cgImage] thành lệnh ESC/POS `GS v 0` (một lệnh cho toàn ảnh).
    /// Ngưỡng nhị phân hóa 200 và điều kiện alpha > 50 khớp với bản Android
    /// để hai nền tảng cho ra bản in giống nhau.
    private func escPosRasterBytes(from cgImage: CGImage) -> Data? {
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

        var data = Data(capacity: 8 + widthBytes * height)
        // GS v 0 m xL xH yL yH
        data.append(contentsOf: [
            0x1D, 0x76, 0x30, 0x00,
            UInt8(widthBytes % 256), UInt8(widthBytes / 256),
            UInt8(height % 256), UInt8(height / 256)
        ])

        for y in 0..<height {
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

        return data
    }
}
