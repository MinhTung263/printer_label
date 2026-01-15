import UIKit
import Flutter
import PrinterSDK
final class ESCPosPrinter {
    weak var plugin: PrinterLabelPlugin?
    func printImageESC(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {

        // 1️⃣ Parse model từ Flutter
        guard let args = call.arguments as? [String: Any],
              let imageData = args["image"] as? FlutterStandardTypedData else {

            result(FlutterError(
                code: "INVALID_ARGS",
                message: "PrintThermalModel.image missing",
                details: nil
            ))
            return
        }

        let paperSize = args["size"] as? Int

        // 2️⃣ Uint8List → UIImage
        guard let image = UIImage(data: imageData.data) else {
            result(FlutterError(
                code: "IMAGE_DECODE_FAILED",
                message: "Cannot decode image data",
                details: nil
            ))
            return
        }

        // 3️⃣ Xác định khổ giấy
        let targetWidth: CGFloat
        switch paperSize {
        case 58:
            targetWidth = 384
        case 80:
            targetWidth = 576
        case 384, 576:
            targetWidth = CGFloat(paperSize!)
        default:
            targetWidth = 576   // fallback 80mm
        }

        // 4️⃣ Resize ảnh
        let scale = targetWidth / image.size.width
        let targetHeight = image.size.height * scale

        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: targetWidth, height: targetHeight),
            false,
            1.0
        )
        image.draw(in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let finalImage = resizedImage,
              let cgImage = finalImage.cgImage else {
            result(FlutterError(
                code: "RESIZE_FAILED",
                message: "Resize image failed",
                details: nil
            ))
            return
        }

        // 5️⃣ Build ESC/POS command
        let esc = PTCommandESC()
        esc.initCommandQueue()
        esc.appendZeroData()
        esc.setJustification(1)

        esc.appendRasterImage(
            cgImage,
            mode: .dithering,
            compress: .none,
            package: true
        )

        esc.printAndLineFeed()
        esc.setFullCut()

        guard let printData = esc.getCommandData() else {
            result(FlutterError(
                code: "COMMAND_FAILED",
                message: "Cannot build print command",
                details: nil
            ))
            return
        }

        // 6️⃣ Send raw data
        plugin?.sendToPrinter(printData)

        // 7️⃣ Return success
        result(true)
    }
}
