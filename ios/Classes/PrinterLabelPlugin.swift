import Flutter
import UIKit
import PrinterSDK
public class PrinterLabelPlugin: NSObject, FlutterPlugin {
    var result: FlutterResult?

    private var channel: FlutterMethodChannel?
    private var printer = PTPrinter()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PrinterLabelPlugin()
        instance.channel = FlutterMethodChannel(name: "flutter_printer_label", binaryMessenger: registrar.messenger())

        registrar.addMethodCallDelegate(instance, channel:instance.channel!)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {

        switch call.method {
            
        case "connect_lan":
            guard let args = call.arguments as? [String: Any],
                  let ip = args["ip_address"] as? String, !ip.isEmpty else {
                result(false)
                return
            }

            printer.ip = ip
            printer.module = .wiFi
            printer.port = "9100"

            let dispatcher = PTDispatcher.share()

            // 1. Nếu đã connect trước đó, disconnect trước
            if dispatcher?.printerConnected != nil {
                dispatcher?.disconnect()
            }

            // 2. Thiết lập callback
            dispatcher?.whenConnectSuccess {
                result(true)
            }

            dispatcher?.whenConnectFailureWithErrorBlock { _ in
                result(false)
            }

            // 3. Connect lại
            dispatcher?.connect(printer)
        case "print_label":
            if let args = call.arguments as? [String: Any] {
                printLabel(args: args,result: result)
            } else {
                print("Invalid arguments for print_multi_label")
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    func printLabel(args: [String: Any],result: @escaping FlutterResult) {
        guard let images = args["images"] as? [FlutterStandardTypedData], !images.isEmpty else {
            print("No images")
            result(false)
            return
        }
   
        let sizeMap = args["size"] as? [String: Any]
        let labelWidthMM: Int = sizeMap?["width"] as? Int ?? 200
        let labelHeightMM: Int = sizeMap?["height"] as? Int ?? 20
        let startX     = args["x"] as? Int ?? 10
        let startY     = args["y"] as? Int ?? 0

        for imageData in images {
            let printer = PTCommandTSPL()
            printer.encoding = String.Encoding.utf8.rawValue
            printer.setPrintAreaSizeWithWidth(labelWidthMM, height: labelHeightMM)
            printer.setGapWithDistance(1, offset: 0)
            printer.setCLS()

            guard let cgImage = imageFromFlutter(imageData)?.cgImage else { continue }

            printer.addBitmap(
                withXPos: startX,
                yPos: startY,
                mode: .OVERWRITE,
                image: cgImage,
                bitmapMode: .binary,
                compress: .none
            )
            printer.print(withSets: 1, copies: 1)
            sendToPrinter(printer.cmdData as Data)
        }
        result(true)
    }



    func imageFromFlutter(_ data: FlutterStandardTypedData) -> UIImage? {
        return UIImage(data: data.data)
    }
    func sendToPrinter(_ data: Any) {
        let sendData: Data
        if let mutableData = data as? NSMutableData {
            sendData = mutableData as Data
        } else if let normalData = data as? Data {
            sendData = normalData
        } else {
            print("Invalid data type")
            return
        }

        PTDispatcher.share()?.send(sendData)
    }
   
}
