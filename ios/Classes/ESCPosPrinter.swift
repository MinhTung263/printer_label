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

        let esc = PTCommandESC()
        esc.initCommandQueue()
        esc.appendZeroData()
        esc.setJustification(1)
        esc.appendRasterImage(cgImage, mode: .dithering, compress: .none, package: true)
        esc.printAndLineFeed()
        esc.setFullCutWithDistance(1)

        completion(esc.getCommandData() as Data?)
    }
}
