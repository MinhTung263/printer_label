import CoreBluetooth
import Flutter

public class PrinterLabelPlugin: NSObject, FlutterPlugin, CBCentralManagerDelegate {
    var centralManager: CBCentralManager?
    var result: FlutterResult?
    var discoveredDevices: [String] = []
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_printer_label", binaryMessenger: registrar.messenger())
        let instance = PrinterLabelPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getBluetoothDevices" {
            self.result = result
            self.discoveredDevices = []
            
            if centralManager == nil {
                centralManager = CBCentralManager(delegate: self, queue: nil)
            } else {
                startScanning()
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            result?(["error": "Bluetooth is not available"])
            result = nil
        }
    }
    
    private func startScanning() {
        discoveredDevices = []
        centralManager?.scanForPeripherals(withServices: nil, options: nil)
        
        // Tự động dừng quét sau 5 giây
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.stopScanning()
        }
    }
    
    private func stopScanning() {
        centralManager?.stopScan()
        result?(discoveredDevices) // Trả về danh sách tên thiết bị
        result = nil
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let deviceName = peripheral.name ?? "Unknown"
        if !discoveredDevices.contains(deviceName) {
            discoveredDevices.append(deviceName)
            print("Discovered Bluetooth device: \(deviceName)")
        }
    }
    
}
