import Flutter
import PrinterSDK
import UIKit
import CoreBluetooth

// MARK: - EmptyStreamHandler
// Stub cho các EventChannel không có sự kiện trên iOS (vd: USB events)
private final class EmptyStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { nil }
    func onCancel(withArguments arguments: Any?) -> FlutterError? { nil }
}

// MARK: - BLEScanStreamHandler
// FlutterStreamHandler cho EventChannel bt_scan.
// onListen: gán sink vào BLEManager để push events
// onCancel: nil sink nhưng KHÔNG dừng scan — BLEManager tự quản lý lifecycle
private final class BLEScanStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        BLEManager.shared.scanEventSink = events
        BLEManager.shared.replayCachedDevices(to: events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        // Không gọi stopScan() — scan tiếp tục ngay cả khi Flutter stream bị cancel
        BLEManager.shared.scanEventSink = nil
        return nil
    }
}

// MARK: - PrinterLabelPlugin
public class PrinterLabelPlugin: NSObject, FlutterPlugin {

    private var methodChannel: FlutterMethodChannel?
    private var scanChannel: FlutterEventChannel?
    private var usbChannel: FlutterEventChannel?

    // legacy PTPrinter kept for compatibility but not used for LAN transport
    private var printer = PTPrinter()

    private let escPrinter: ESCPosPrinter
    private let bleScanHandler = BLEScanStreamHandler()

    override init() {
        self.escPrinter = ESCPosPrinter()
        super.init()
        self.escPrinter.plugin = self
        // Khởi tạo BLEManager sớm để CBCentralManager sẵn sàng
        _ = BLEManager.shared
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PrinterLabelPlugin()

        // MethodChannel chính
        let channel = FlutterMethodChannel(
            name: "flutter_printer_label",
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)

        // EventChannel để stream BLE scan results về Flutter
        let scanChannel = FlutterEventChannel(
            name: "flutter_printer_label/bt_scan",
            binaryMessenger: registrar.messenger()
        )
        scanChannel.setStreamHandler(instance.bleScanHandler)
        instance.scanChannel = scanChannel

        // Stub USB EventChannel — iOS không có USB printer events
        let usbChannel = FlutterEventChannel(
            name: "flutter_printer_label/usb_events",
            binaryMessenger: registrar.messenger()
        )
        usbChannel.setStreamHandler(EmptyStreamHandler())
        instance.usbChannel = usbChannel
    }

    // MARK: - Method Handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        // MARK: BLE Scan
        case "scan_bt":
            BLEManager.shared.startScan()
            // Trả false nếu BT không được cấp quyền để Flutter biết
            let authorized = CBCentralManager.authorization != .denied
                && CBCentralManager.authorization != .restricted
            result(authorized)

        case "stop_scan_bt":
            BLEManager.shared.stopScan()
            result(true)

        // MARK: BLE Connect
        // macAddress arg trên iOS thực chất là UUID identifier từ CBPeripheral
        case "connect_bt":
            guard let args = call.arguments as? [String: Any],
                  let identifier = (args["mac_address"] ?? args["identifier"]) as? String,
                  !identifier.isEmpty
            else {
                result(FlutterError(code: "INVALID_ARGS", message: "identifier required", details: nil))
                return
            }
            BLEManager.shared.connect(identifier: identifier, result: result)

        // MARK: Get Discovered Devices
        case "get_bluetooth_devices":
            let devices = BLEManager.shared.getDiscoveredDevices()
            result(devices)

        // MARK: Disconnect
        case "disconnect":
            let args = call.arguments as? [String: Any]
            let deviceId = args?["device_id"] as? String
            let connectionType = args?["connection_type"] as? String

            if let id = deviceId, !id.isEmpty {
                if let bleId = extractBLEIdentifier(from: id) {
                    BLEManager.shared.disconnect(identifier: bleId, result: result)
                } else if connectionType == "Bluetooth" {
                    BLEManager.shared.disconnectAll(result: result)
                } else {
                    disconnectLAN(result: result)
                }
            } else {
                // Disconnect tất cả BLE + LAN
                BLEManager.shared.disconnectAll { _ in }
                disconnectLAN(result: result)
            }

        // MARK: LAN Connect
        case "connect_lan":
            guard let args = call.arguments as? [String: Any],
                  let ip = args["ip_address"] as? String, !ip.isEmpty
            else {
                result(false)
                return
            }
            connectLAN(ip: ip, result: result)

        // MARK: Print Label (TSPL)
        case "print_label":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printLabel(args: args, result: result)

        // MARK: Print Image (TSPL)
        case "print_image":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printImage(args: args, result: result)

        // MARK: Print Barcode (TSPL)
        case "print_barcode":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printBarcode(args: args, result: result)

        // MARK: Print ESC/POS
        case "print_image_esc":
            escPrinter.printImageESC(call: call, result: result)

        // MARK: Print All
        case "print_all":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printAll(args: args, result: result)

        // MARK: Check Connection
        case "checkConnect":
            let args = call.arguments as? [String: Any]
            let deviceId = args?["device_id"] as? String
            if let id = deviceId {
                // Kiểm tra BLE connection
                if let bleId = extractBLEIdentifier(from: id) {
                    result(BLEManager.shared.isConnected(identifier: bleId))
                } else if let ip = extractLANIp(from: id) {
                    // Kiểm tra LAN connection
                    result(LANPrinterManager.shared.isConnected(ip: ip))
                } else {
                    result(false)
                }
            } else {
                // Không có deviceId → check BLE hoặc LAN bất kỳ cái nào có kết nối
                let hasBleSub = BLEManager.shared.hasAnyConnection()
                let hasLanSub = !LANPrinterManager.shared.getConnectedPrinters().isEmpty
                result(hasBleSub || hasLanSub)
            }

        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - LAN Helpers

    private func connectLAN(ip: String, result: @escaping FlutterResult) {
        // Use LANPrinterManager to create/maintain a connection per IP
        LANPrinterManager.shared.connect(ip: ip, port: 9100, autoReconnect: true) { success in
            result(success)
        }
    }

    private func disconnectLAN(result: @escaping FlutterResult) {
        // If caller provided an IP previously (printer.ip), prefer disconnecting that.
        // Otherwise, disconnect all LAN connections.
        if let ip = printer.ip, !ip.isEmpty {
            LANPrinterManager.shared.disconnect(ip: ip) { success in
                result(success)
            }
        } else {
            LANPrinterManager.shared.disconnectAll()
            result(true)
        }
    }

    // MARK: - Print Routing

    // Quyết định route print data tới BLE hay LAN dựa trên device_id/connection_type
    func sendToPrinter(_ data: Data, deviceId: String? = nil, connectionType: String? = nil) {
        print("[PrinterLabelPlugin] sendToPrinter called: deviceId=\(deviceId ?? "nil"), connectionType=\(connectionType ?? "nil"), data size=\(data.count)")
        
        if connectionType == "Bluetooth" {
            print("[PrinterLabelPlugin] → Route: Bluetooth")
            // Thử extract UUID kể cả khi có prefix "BT:"
            let bleId = deviceId.flatMap { extractBLEIdentifier(from: $0) }
            routeToBLE(data, identifier: bleId)
        } else if let id = deviceId, let bleId = extractBLEIdentifier(from: id) {
            print("[PrinterLabelPlugin] → Route: BLE (extracted UUID: \(bleId))")
            // deviceId là BLE UUID → gửi tới BLE device cụ thể
            routeToBLE(data, identifier: bleId)
        } else if let id = deviceId {
            print("[PrinterLabelPlugin] → Route: LAN (deviceId: \(id))")
            // deviceId có nhưng không phải BLE → extract IP từ "LAN:192.168.1.10" format
            if let ip = extractLANIp(from: id) {
                print("[PrinterLabelPlugin] → Extracted IP: \(ip)")
                LANPrinterManager.shared.send(data: data, to: ip, completion: { _, _ in })
            } else {
                print("[PrinterLabelPlugin] ❌ Failed to extract IP from \(id)")
            }
        } else {
            print("[PrinterLabelPlugin] → Route: Default (no deviceId)")
            // Không có device_id → thử BLE trước, fallback sang LAN tất cả
            if BLEManager.shared.hasAnyConnection() {
                print("[PrinterLabelPlugin] → Fallback to first BLE device")
                BLEManager.shared.writeDataToFirstConnected(data) { _ in }
            } else {
                print("[PrinterLabelPlugin] → Fallback to all LAN printers")
                // no deviceId and no BLE: send to all connected LAN printers
                let ips = LANPrinterManager.shared.getConnectedPrinters()
                print("[PrinterLabelPlugin] Found \(ips.count) LAN printers: \(ips)")
                for ip in ips {
                    LANPrinterManager.shared.send(data: data, to: ip, completion: { _, _ in })
                }
            }
        }
    }

    private func routeToBLE(_ data: Data, identifier: String?) {
        if let id = identifier, !id.isEmpty {
            BLEManager.shared.writeData(data, toIdentifier: id) { _ in }
        } else {
            BLEManager.shared.writeDataToFirstConnected(data) { _ in }
        }
    }

    // UUID format: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
    private func isUUID(_ string: String) -> Bool {
        return UUID(uuidString: string) != nil
    }

    // Trích UUID từ device_id có thể có prefix "BT:" (từ DeviceId.bluetooth())
    // Ví dụ: "BT:12345678-ABCD-..." → "12345678-ABCD-..."
    private func extractBLEIdentifier(from deviceId: String) -> String? {
        let raw = deviceId.hasPrefix("BT:") ? String(deviceId.dropFirst(3)) : deviceId
        return isUUID(raw) ? raw : nil
    }

    // Trích IP từ device_id có prefix "LAN:" (từ DeviceId.lan())
    // Ví dụ: "LAN:192.168.1.10" → "192.168.1.10"
    private func extractLANIp(from deviceId: String) -> String? {
        guard deviceId.hasPrefix("LAN:") else { return nil }
        return String(deviceId.dropFirst(4))
    }

    // MARK: - Print Methods

    func printLabel(args: [String: Any], result: @escaping FlutterResult) {
        guard let images = args["images"] as? [FlutterStandardTypedData], !images.isEmpty else {
            result(false)
            return
        }

        let sizeMap = args["size"] as? [String: Any]
        let labelWidthMM = sizeMap?["width"] as? Int ?? 100
        let labelHeightMM = sizeMap?["height"] as? Int ?? 20
        let startX = args["x"] as? Int ?? 0
        let startY = args["y"] as? Int ?? 0
        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String

        for imageData in images {
            let cmd = PTCommandTSPL()
            cmd.encoding = String.Encoding.utf8.rawValue
            cmd.setPrintAreaSizeWithWidth(labelWidthMM, height: labelHeightMM)
            cmd.setGapWithDistance(1, offset: 0)
            cmd.setCLS()

            guard let cgImage = imageFromFlutter(imageData)?.cgImage else { continue }

            cmd.addBitmap(
                withXPos: startX, yPos: startY,
                mode: .OVERWRITE, image: cgImage,
                bitmapMode: .binary, compress: .none
            )
            cmd.print(withSets: 1, copies: 1)
            sendToPrinter(cmd.cmdData as Data, deviceId: deviceId, connectionType: connectionType)
        }
        result(true)
    }

    func printImage(args: [String: Any], result: @escaping FlutterResult) {
        guard let imageData = args["image"] as? FlutterStandardTypedData else {
            result(false)
            return
        }

        let x = args["x"] as? Int ?? 0
        let y = args["y"] as? Int ?? 0
        let width = args["width"] as? Int ?? 100
        let height = args["height"] as? Int ?? 20
        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String

        guard let cgImage = imageFromFlutter(imageData)?.cgImage else {
            result(false)
            return
        }

        let cmd = PTCommandTSPL()
        cmd.encoding = String.Encoding.utf8.rawValue
        cmd.setPrintAreaSizeWithWidth(width, height: height)
        cmd.setGapWithDistance(1, offset: 0)
        cmd.setCLS()
        cmd.addBitmap(
            withXPos: x, yPos: y,
            mode: .OVERWRITE, image: cgImage,
            bitmapMode: .binary, compress: .none
        )
        cmd.print(withSets: 1, copies: 1)
        sendToPrinter(cmd.cmdData as Data, deviceId: deviceId, connectionType: connectionType)
        result(true)
    }

    func printBarcode(args: [String: Any], result: @escaping FlutterResult) {
        guard let imageData = args["image"] as? FlutterStandardTypedData else {
            result(false)
            return
        }

        let x = args["x"] as? Int ?? 0
        let y = args["y"] as? Int ?? 0
        let width = args["width"] as? Int ?? 100
        let height = args["height"] as? Int ?? 20
        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String

        guard let cgImage = imageFromFlutter(imageData)?.cgImage else {
            result(false)
            return
        }

        let cmd = PTCommandTSPL()
        cmd.encoding = String.Encoding.utf8.rawValue
        cmd.setPrintAreaSizeWithWidth(width, height: height)
        cmd.setGapWithDistance(1, offset: 0)
        cmd.setCLS()
        cmd.addBitmap(
            withXPos: x, yPos: y,
            mode: .OVERWRITE, image: cgImage,
            bitmapMode: .binary, compress: .none
        )
        cmd.print(withSets: 1, copies: 1)
        sendToPrinter(cmd.cmdData as Data, deviceId: deviceId, connectionType: connectionType)
        result(true)
    }

    func printAll(args: [String: Any], result: @escaping FlutterResult) {
        let connectionType = args["connection_type"] as? String

        // Lấy command data — thử build ESC hoặc TSPL tuỳ args có sẵn
        if let imageData = args["image"] as? FlutterStandardTypedData {
            // ESC path
            escPrinter.buildAndSendESC(imageData: imageData, args: args) { [weak self] data in
                guard let self = self, let data = data else { result(false); return }
                if connectionType == "Bluetooth" || connectionType == nil {
                    self.sendToPrinter(data, deviceId: nil, connectionType: connectionType)
                }
                if connectionType == "LAN" || connectionType == nil {
                    let ips = LANPrinterManager.shared.getConnectedPrinters()
                    for ip in ips {
                        LANPrinterManager.shared.send(data: data, to: ip, completion: { _, _ in })
                    }
                }
                result(true)
            }
        } else if let images = args["images"] as? [FlutterStandardTypedData], !images.isEmpty {
            // TSPL path — send tới tất cả connections
            let sizeMap = args["size"] as? [String: Any]
            let w = sizeMap?["width"] as? Int ?? 100
            let h = sizeMap?["height"] as? Int ?? 20
            let x = args["x"] as? Int ?? 0
            let y = args["y"] as? Int ?? 0

            for imageData in images {
                let cmd = PTCommandTSPL()
                cmd.encoding = String.Encoding.utf8.rawValue
                cmd.setPrintAreaSizeWithWidth(w, height: h)
                cmd.setGapWithDistance(1, offset: 0)
                cmd.setCLS()
                guard let cg = imageFromFlutter(imageData)?.cgImage else { continue }
                cmd.addBitmap(withXPos: x, yPos: y, mode: .OVERWRITE, image: cg, bitmapMode: .binary, compress: .none)
                cmd.print(withSets: 1, copies: 1)
                let data = cmd.cmdData as Data
                sendToPrinter(data, deviceId: nil, connectionType: connectionType)
            }
            result(true)
        } else {
            result(false)
        }
    }

    // MARK: - Utilities

    func imageFromFlutter(_ data: FlutterStandardTypedData) -> UIImage? {
        return UIImage(data: data.data)
    }
}
