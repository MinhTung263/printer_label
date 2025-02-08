import CoreBluetooth
import Flutter
import PrinterSDK
import UIKit
public class PrinterLabelPlugin: NSObject, FlutterPlugin {
    var centralManager: CBCentralManager?
    var result: FlutterResult?
    var discoveredDevices: [String] = []
    var dataSources = [PTPrinter]()
    var channel: FlutterMethodChannel?
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PrinterLabelPlugin()
        instance.channel = FlutterMethodChannel(name: "flutter_printer_label", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel:instance.channel!)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            
        case "getBluetoothDevice":
            openPrinterSelection(result: result)
        case "printWithSelectedPrinter":
            if let args = call.arguments as? [String: Any],
               let printerMac = args["mac"] as? String {
                if let printer = dataSources.first(where: { $0.mac == printerMac }) {
                    connectAndPrint(printer: printer)
                }
            }
            result(nil)
        case "printWifi":
            printWifi()
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func openPrinterSelection(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                let printerVC = SelectDevice()
                printerVC.modalPresentationStyle = .fullScreen
                printerVC.onPrintersUpdated = { printers in
                    self.dataSources = printers
                }
                
                printerVC.onPrinterSelected = { selectedPrinter in
                    let printerInfo = [
                        "name": selectedPrinter.name ?? "Unknown",
                        "mac": selectedPrinter.mac
                    ]
                    
                    result(printerInfo)
                }
                rootVC.present(printerVC, animated: true, completion: nil)
            }
        }
    }
    private func connectAndPrint(printer: PTPrinter) {
        PTDispatcher.share()?.connect(printer)
        if PTDispatcher.share().printerConnected == nil {
            showAlert(message: "Printer unconnected, pls. connect")
            return
        }
        
        let esc = PTCommandESC.init()
        esc.initializePrinter()
        esc.appendText("UPCA:", mode: ESCText.normal)
        esc.append(ESCBarcode.B_UPCA, data: "075678164125", justification: 0, width: 2, height: 60, hri: 2)
        esc.appendText("\n", mode: ESCText.normal)
        PTDispatcher.share()?.send(esc.getCommandData())
        
        
    }
    
    private func printWifi() {
        let pt = PTPrinter.init()
        pt.ip = "192.168.50.91"
        pt.module = .wiFi
        pt.port = "9100"
        connectAndPrint(printer: pt)
        
    }
    func showAlert(message: String) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            
            if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                rootVC.present(alertController, animated: true, completion: nil)
            }
        }
    }
    
}
