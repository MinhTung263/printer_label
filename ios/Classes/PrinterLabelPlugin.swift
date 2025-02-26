import CoreBluetooth
import Flutter
import UIKit
public class PrinterLabelPlugin: NSObject, FlutterPlugin {
    var result: FlutterResult?
    var channel: FlutterMethodChannel?
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PrinterLabelPlugin()
        instance.channel = FlutterMethodChannel(name: "flutter_printer_label", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel:instance.channel!)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            
       // case "openBluetoothList":
           
            
            
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
}

