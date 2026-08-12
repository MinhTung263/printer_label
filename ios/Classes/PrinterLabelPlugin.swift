import Flutter
import PrinterSDK
import UIKit
import CoreBluetooth
import Network

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
        // Đọc tham số filterPrinterOnly từ Flutter (truyền qua receiveBroadcastStream arguments)
        let args = arguments as? [String: Any]
        BLEManager.shared.filterPrinterOnly = args?["filter_printer_only"] as? Bool ?? true
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

    // Cache MAC -> IP từ lần scan_net_printers gần nhất. SDK máy in trên iOS
    // (PTDispatcher) không có API cấu hình IP theo MAC như SDK Android, nên khi
    // set_net_ip chỉ nhận được mac (không có current_ip), ta tra IP tương ứng ở đây
    // rồi vẫn gửi cấu hình qua route ESC/POS TCP hiện có.
    private var lastScannedMacToIp: [String: String] = [:]

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
            let authorized: Bool
            if #available(iOS 13.1, *) {
                authorized = CBCentralManager.authorization != .denied
                    && CBCentralManager.authorization != .restricted
            } else {
                authorized = true
            }
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
            
        case "print_text":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printText(args: args, result: result)
            
        case "print_text_esc":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printTextESC(args: args, result: result)

        case "print_barcode":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printBarcode(args: args, result: result)

        case "print_qrcode":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printQRCode(args: args, result: result)

        case "print_barcode_esc":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printBarcodeESC(args: args, result: result)

        case "print_qrcode_esc":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printQRCodeESC(args: args, result: result)

        // MARK: Print Image (TSPL)
        case "print_image":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            printImage(args: args, result: result)

        // MARK: Print ESC/POS
        case "print_image_esc":
            escPrinter.printImageESC(call: call, result: result)

        case "open_drawer":
            escPrinter.openDrawer(call: call, result: result)


        // MARK: Identify LAN Printer (Beep / Feed / Slip)
        case "identify_lan_printer":
            guard let args = call.arguments as? [String: Any],
                  let ip = args["ip_address"] as? String, !ip.isEmpty
            else {
                result(false)
                return
            }

            var data: Data?
            if let typedData = args["bytes"] as? FlutterStandardTypedData {
                data = typedData.data
            } else if let byteList = args["bytes"] as? [UInt8] {
                data = Data(byteList)
            } else if let intList = args["bytes"] as? [Int] {
                data = Data(intList.map { UInt8($0 & 0xFF) })
            } else if let nsNumbers = args["bytes"] as? [NSNumber] {
                data = Data(nsNumbers.map { UInt8(truncating: $0) })
            }

            guard let payload = data, !payload.isEmpty else {
                print("[PrinterLabelPlugin] ❌ identify_lan_printer: bytes is empty or invalid format")
                result(false)
                return
            }

            LANPrinterManager.shared.send(data: payload, to: ip) { ok, err in
                if !ok {
                    print("[PrinterLabelPlugin] ❌ identify_lan_printer failed for \(ip): \(err?.localizedDescription ?? "unknown")")
                } else {
                    print("[PrinterLabelPlugin] 🔔 identify_lan_printer succeeded for \(ip)")
                }
                result(ok)
            }

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

        case "check_printer_status":
            let args = call.arguments as? [String: Any]
            let deviceId = args?["device_id"] as? String
            if let id = deviceId {
                let isConnected: Bool
                if let bleId = extractBLEIdentifier(from: id) {
                    isConnected = BLEManager.shared.isConnected(identifier: bleId)
                } else if let ip = extractLANIp(from: id) {
                    isConnected = LANPrinterManager.shared.isConnected(ip: ip)
                } else {
                    isConnected = false
                }
                result(isConnected ? "normal" : "offline")
            } else {
                let anyConnected = BLEManager.shared.hasAnyConnection() || !LANPrinterManager.shared.getConnectedPrinters().isEmpty
                result(anyConnected ? "normal" : "offline")
            }

        case "bluetooth_enabled":
            result(BLEManager.shared.isBluetoothEnabled)

        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)

        case "scan_net_printers":
            let scanTimeout: Double = 1.5
            let queue = DispatchQueue(label: "com.printerlabel.scan.\(UUID().uuidString)")
            var devices: [[String: Any]] = []
            var seenKeys = Set<String>()

            // 1. Quét qua PTDispatcher (PT SDK)
            PTDispatcher.share()?.findAllPeripheralBlock = { (printerArray: NSMutableArray?) in
                guard let array = printerArray as? [PTPrinter], !array.isEmpty else { return }
                queue.async {
                    for printer in array {
                        let ip = printer.ip ?? ""
                        let mac = printer.mac ?? ""
                        guard !ip.isEmpty else { continue }
                        let key = "\(ip)|\(mac)"
                        if seenKeys.insert(key).inserted {
                            devices.append(["mac": mac, "ip": ip])
                            print("[iOS scan PT] Found: ip=\(ip) mac=\(mac)")
                        }
                    }
                }
            }

            PTDispatcher.share()?.sendBroadcastMessages()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                PTDispatcher.share()?.scanDevice(atLAN: scanTimeout - 0.3)
            }

            // 2. Quét qua POS UDP Broadcast (XP0001FIND) cho Xprinter / POS Network Printers
            POSNetConfigHelper.scanUdpPrinters(timeout: scanTimeout - 0.2) { udpDevices in
                queue.async {
                    for d in udpDevices {
                        let ip = d["ip"] as? String ?? ""
                        let mac = d["mac"] as? String ?? ""
                        guard !ip.isEmpty else { continue }
                        let key = "\(ip)|\(mac)"
                        if seenKeys.insert(key).inserted {
                            devices.append(d)
                            print("[iOS scan UDP] Found: ip=\(ip) mac=\(mac)")
                        }
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + scanTimeout) {
                queue.sync {
                    for device in devices {
                        if let mac = device["mac"] as? String, !mac.isEmpty,
                           let ip = device["ip"] as? String, !ip.isEmpty {
                            self.lastScannedMacToIp[mac.uppercased()] = ip
                        }
                    }
                    result(devices)
                }
            }

        case "set_net_ip":
            let args = call.arguments as? [String: Any]
            let newIp = args?["ip"] as? String ?? ""
            let mask = args?["mask"] as? String ?? "255.255.255.0"
            let gateway = args?["gateway"] as? String ?? ""
            let dhcp = args?["dhcp"] as? Bool ?? false
            let mac = args?["mac"] as? String ?? ""
            var currentIp = args?["current_ip"] as? String ?? ""

            // Nếu Flutter không truyền current_ip nhưng có mac, tra IP tương ứng từ lần scan gần nhất
            if currentIp.isEmpty && !mac.isEmpty {
                currentIp = lastScannedMacToIp[mac.uppercased()] ?? ""
            }

            guard !newIp.isEmpty else {
                result(FlutterError(code: "INVALID_ARGS", message: "ip is required", details: nil))
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                // --- Tuyến 1 (Ưu tiên): Đổi IP theo MAC qua UDP Broadcast (Xprinter/POS) ---
                // Gửi trực tiếp tới cổng UDP 9000, KHÔNG gửi dữ liệu tới cổng in 9100
                // để tránh việc máy in hiểu nhầm là lệnh in và in ra 1 tờ giấy trắng / rác.
                if !mac.isEmpty {
                    let udpOk = POSNetConfigHelper.sendUdpNetConfig(
                        mac: mac,
                        ip: newIp,
                        mask: mask,
                        gateway: gateway,
                        dhcp: dhcp,
                        currentIp: currentIp.isEmpty ? nil : currentIp
                    )
                    DispatchQueue.main.async {
                        result(udpOk)
                    }
                    return
                }

                // --- Tuyến 2: Chỉ khi KHÔNG CÓ MAC mới gửi lệnh cấu hình qua TCP cổng in 9100 (Epson, Brother, PT SDK) ---
                let targetIp = !currentIp.isEmpty ? currentIp : (LANPrinterManager.shared.getConnectedPrinters().first ?? "")

                if !targetIp.isEmpty {
                    let esc = PTCommandESC()
                    esc.setPrinterWiFiDhcpStatus(dhcp ? 1 : 0)
                    if !dhcp {
                        esc.setPrinterWiFiIPAddress(newIp)
                        esc.setPrinterWiFiSubnetMask(mask)
                        if !gateway.isEmpty {
                            esc.setPrinterWiFiGateway(gateway)
                        }
                    }
                    esc.saveWiFiParametersSetting()
                    if let data = esc.getCommandData() as Data? {
                        self.sendEscNetworkCommand(to: targetIp, data: data) { resultCode, sendOk in
                            DispatchQueue.main.async {
                                result(sendOk && (resultCode == nil || resultCode == 0 || resultCode == 4))
                            }
                        }
                        return
                    }
                }

                DispatchQueue.main.async {
                    result(false)
                }
            }


        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - LAN Helpers

    /// Gửi lệnh ESC cấu hình mạng (WiFi IP/mask/gateway/dhcp) tới `ip:9100` qua một
    /// socket TCP tạm thời riêng (KHÔNG dùng LANPrinterManager — connection đó được
    /// tinh chỉnh riêng cho in ấn với retry/idle-close, không phù hợp cho lệnh cấu hình
    /// cần đọc phản hồi).
    ///
    /// Theo tài liệu SDK, sau khi nhận lệnh set, máy in trả về 1 byte mã kết quả:
    /// 0 = thành công, 1 = thất bại, 2 = không có quyền, 3 = sai tham số,
    /// 4 = thành công nhưng cần khởi động lại. `resultCode` sẽ là nil nếu máy in
    /// không phản hồi trong thời gian chờ (một số firmware không trả lời lệnh này).
    private func sendEscNetworkCommand(
        to ip: String,
        port: UInt16 = 9100,
        data: Data,
        timeout: TimeInterval = 2.5,
        completion: @escaping (_ resultCode: Int?, _ sendOk: Bool) -> Void
    ) {
        let queue = DispatchQueue(label: "com.printerlabel.netconfig.\(ip)")
        let host = NWEndpoint.Host(ip)
        let nwPort = NWEndpoint.Port(rawValue: port) ?? 9100
        let connection = NWConnection(host: host, port: nwPort, using: .tcp)

        var finished = false
        func finish(_ resultCode: Int?, _ sendOk: Bool) {
            queue.async {
                guard !finished else { return }
                finished = true
                connection.cancel()
                DispatchQueue.main.async { completion(resultCode, sendOk) }
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: data, completion: .contentProcessed({ error in
                    guard error == nil else {
                        print("[set_net_ip] ❌ Gửi lệnh tới \(ip) lỗi: \(error!)")
                        finish(nil, false)
                        return
                    }
                    print("[set_net_ip] 📤 Đã gửi \(data.count) byte cấu hình mạng tới \(ip), chờ phản hồi...")
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { recvData, _, _, _ in
                        if let recvData = recvData, !recvData.isEmpty {
                            let code = Int(recvData[recvData.startIndex])
                            print("[set_net_ip] 📥 Máy in \(ip) phản hồi: \([UInt8](recvData)) → mã \(code)")
                            finish(code, true)
                        } else {
                            print("[set_net_ip] ⚠️ Máy in \(ip) không phản hồi trong \(timeout)s sau khi gửi lệnh")
                            finish(nil, true)
                        }
                    }
                }))
            case .failed(let error):
                print("[set_net_ip] ❌ Không kết nối được \(ip): \(error)")
                finish(nil, false)
            case .cancelled:
                finish(nil, false)
            default:
                break
            }
        }

        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) {
            finish(nil, true)
        }
    }

    private func connectLAN(ip: String, result: @escaping FlutterResult) {
        // Use LANPrinterManager to create/maintain a connection per IP
        LANPrinterManager.shared.connect(ip: ip, port: 9100) { success in
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

    @discardableResult
    func sendToPrinter(_ data: Data, deviceId: String? = nil, connectionType: String? = nil) -> Bool {
        print("[PrinterLabelPlugin] sendToPrinter called: deviceId=\(deviceId ?? "nil"), connectionType=\(connectionType ?? "nil"), data size=\(data.count)")
        
        if connectionType == "Bluetooth" {
            print("[PrinterLabelPlugin] → Route: Bluetooth")
            let bleId = deviceId.flatMap { extractBLEIdentifier(from: $0) }
            routeToBLE(data, identifier: bleId)
            return BLEManager.shared.hasAnyConnection()
        } else if let id = deviceId, let bleId = extractBLEIdentifier(from: id) {
            print("[PrinterLabelPlugin] → Route: BLE (extracted UUID: \(bleId))")
            routeToBLE(data, identifier: bleId)
            return BLEManager.shared.hasAnyConnection()
        } else if let id = deviceId {
            print("[PrinterLabelPlugin] → Route: LAN (deviceId: \(id))")
            if let ip = extractLANIp(from: id) {
                print("[PrinterLabelPlugin] → Extracted IP: \(ip)")
                LANPrinterManager.shared.send(data: data, to: ip, completion: { ok, err in
                    // sendToPrinter là fire-and-forget nên không trả lỗi về Dart được;
                    // log lại để chẩn đoán khi máy in bận vì thiết bị khác đang in.
                    if !ok {
                        print("[PrinterLabelPlugin] ❌ LAN write failed (\(ip)): \(err?.localizedDescription ?? "unknown")")
                    }
                })
                return true
            } else {
                print("[PrinterLabelPlugin] ❌ Failed to extract IP from \(id)")
                return false
            }
        } else {
            print("[PrinterLabelPlugin] → Route: Default (no deviceId)")
            var sent = false
            if BLEManager.shared.hasAnyConnection() {
                print("[PrinterLabelPlugin] → Broadcast to all connected BLE devices")
                BLEManager.shared.writeDataToAllConnected(data) { _ in }
                sent = true
            }
            let ips = LANPrinterManager.shared.getConnectedPrinters()
            print("[PrinterLabelPlugin] Found \(ips.count) LAN printers: \(ips)")
            if !ips.isEmpty {
                for ip in ips {
                    LANPrinterManager.shared.send(data: data, to: ip, completion: { ok, err in
                    // sendToPrinter là fire-and-forget nên không trả lỗi về Dart được;
                    // log lại để chẩn đoán khi máy in bận vì thiết bị khác đang in.
                    if !ok {
                        print("[PrinterLabelPlugin] ❌ LAN write failed (\(ip)): \(err?.localizedDescription ?? "unknown")")
                    }
                })
                }
                sent = true
            }
            return sent
        }
    }

    private func routeToBLE(_ data: Data, identifier: String?) {
        // sendToPrinter là fire-and-forget nên không có FlutterResult để trả lỗi về Dart.
        // Log lại để chẩn đoán được khi máy in nhận thiếu dữ liệu.
        let logFailure: (String) -> (Any?) -> Void = { target in
            return { res in
                if let error = res as? FlutterError {
                    print("[PrinterLabelPlugin] ❌ BLE write failed (\(target)): \(error.code) \(error.message ?? "")")
                }
            }
        }
        if let id = identifier, !id.isEmpty {
            BLEManager.shared.writeData(data, toIdentifier: id, result: logFailure(id))
        } else {
            BLEManager.shared.writeDataToFirstConnected(data, result: logFailure("first-connected"))
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

    private func resizeImage(_ image: UIImage, targetWidth: CGFloat, targetHeight: CGFloat, drawX: CGFloat = 0.0) -> CGImage? {
        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: targetWidth, height: targetHeight),
            true, // opaque: true (gives us a solid white background to avoid transparent pixel issues)
            1.0   // scale factor of 1.0 to keep exact dot dimensions
        )
        
        // Fill background with white
        if let context = UIGraphicsGetCurrentContext() {
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        }
        
        image.draw(in: CGRect(x: drawX, y: 0, width: targetWidth, height: targetHeight))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let binarizedImage = resized?.binarized(threshold: 200) else { return resized?.cgImage }
        return binarizedImage.cgImage
    }

    // MARK: - Print Methods

    func printLabel(args: [String: Any], result: @escaping FlutterResult) {
        guard let images = args["images"] as? [FlutterStandardTypedData], !images.isEmpty else {
            result(false)
            return
        }

        let sizeMap = args["size"] as? [String: Any]
        let labelWidthMM = sizeMap?["width"] as? Int ?? 40
        let labelHeightMM = sizeMap?["height"] as? Int ?? 25
        
        let gapMap = args["gap"] as? [String: Any]
        let gapWidthMM = gapMap?["width"] as? Int ?? 2
        let gapHeightMM = gapMap?["height"] as? Int ?? 0
        
        // Chỉ khổ 3 tem cần HOME (xem LabelPerRow.useHome). Bật cho khổ 1-2 tem sẽ đẩy
        // thừa một hàng -> in một hàng lại bỏ trắng một hàng.
        let useHome = args["use_home"] as? Bool ?? false

        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String

        let targetWidth = labelWidthMM * 8
        let targetHeight = labelHeightMM * 8

        for imageData in images {
            autoreleasepool {
                let cmd = PTCommandTSPL()
                cmd.encoding = String.Encoding.utf8.rawValue
                cmd.setPrintAreaSizeWithWidth(labelWidthMM, height: labelHeightMM)
                cmd.setGapWithDistance(gapWidthMM, offset: gapHeightMM)
                cmd.setReferenceXPos(0, yPos: 0)
                cmd.setPrintDirection(.normal, mirror: .normal)
                if useHome {
                    // Dò khe decal để canh lại đầu tem, xóa sai số đẩy giấy tích lũy.
                    cmd.setHome()
                }
                cmd.setCLS()

                guard let uiImage = imageFromFlutter(imageData) else { return }
                // Bù dải trắng leftPadding của widget Dart (8px logic -> ~1.16mm sau khi
                // scale). -8 dots = -1mm đưa tem đầu về sát mép trái mà không cắt mất.
                let drawX: CGFloat = -8.0
                guard let cgImage = resizeImage(uiImage, targetWidth: CGFloat(targetWidth), targetHeight: CGFloat(targetHeight), drawX: drawX) else { return }

                cmd.addBitmap(
                    withXPos: 0, yPos: 0,
                    mode: .OVERWRITE, image: cgImage,
                    bitmapMode: .binary, compress: .none
                )
                cmd.print(withSets: 1, copies: 1)
                sendToPrinter(cmd.cmdData as Data, deviceId: deviceId, connectionType: connectionType)
            }
        }
        result(true)
    }

    func printText(args: [String: Any], result: @escaping FlutterResult) {
        let text = args["text"] as? String ?? ""
        let startX = args["x"] as? Int ?? 0
        let startY = args["y"] as? Int ?? 0
        let fontVal = args["font"] as? Int ?? 0
        let rotationVal = args["rotation"] as? Int ?? 0
        let sizeX = args["sizeX"] as? Int ?? 1
        let sizeY = args["sizeY"] as? Int ?? 1
        
        let labelWidthMM = args["width"] as? Int ?? 40
        let labelHeightMM = args["height"] as? Int ?? 30
        
        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String

        let cmd = PTCommandTSPL()
        cmd.encoding = String.Encoding.utf8.rawValue
        cmd.setPrintAreaSizeWithWidth(labelWidthMM, height: labelHeightMM)
        cmd.setGapWithDistance(1, offset: 0)
        cmd.setCLS()
        
        let fontStyle = PTTSCTextFontStyle(rawValue: UInt(fontVal)) ?? PTTSCTextFontStyle(rawValue: 0)!
        let rotation = PTTSCStyleRotation(rawValue: UInt(rotationVal)) ?? PTTSCStyleRotation(rawValue: 0)!
        
        cmd.appendText(
            withXpos: startX,
            yPos: startY,
            font: fontStyle,
            rotation: rotation,
            xMultiplication: sizeX,
            yMultiplication: sizeY,
            text: text
        )
        
        cmd.print(withSets: 1, copies: 1)
        sendToPrinter(cmd.cmdData as Data, deviceId: deviceId, connectionType: connectionType)
        result(true)
    }

    func printTextESC(args: [String: Any], result: @escaping FlutterResult) {
        let text = args["text"] as? String ?? ""
        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String

        let esc = PTCommandESC()
        esc.initCommandQueue()
        esc.appendZeroData()
        esc.appendText(text)
        esc.printAndLineFeed()
        esc.setFullCutWithDistance(1)

        let data = esc.getCommandData() as Data?
        if let printData = data {
            sendToPrinter(printData, deviceId: deviceId, connectionType: connectionType)
            result(true)
        } else {
            result(FlutterError(code: "BUILD_FAILED", message: "Cannot build ESC text command", details: nil))
        }
    }

    func printBarcode(args: [String: Any], result: @escaping FlutterResult) {
        let code = args["code"] as? String ?? ""
        let startX = args["x"] as? Int ?? 0
        let startY = args["y"] as? Int ?? 0
        let height = args["height"] as? Int ?? 100
        let typeVal = args["type"] as? String ?? "128"
        let width = args["width"] as? Int ?? 40
        let heightMM = args["heightMM"] as? Int ?? 30
        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String

        let cmd = PTCommandTSPL()
        cmd.encoding = String.Encoding.utf8.rawValue
        cmd.setPrintAreaSizeWithWidth(width, height: heightMM)
        cmd.setGapWithDistance(1, offset: 0)
        cmd.setCLS()

        let typeInt: Int = {
            switch typeVal {
            case "39": return 5
            case "93": return 7
            case "128": return 0
            case "EAN13": return 8
            case "EAN8": return 11
            case "UPCA": return 16
            case "UPCE": return 17
            default: return 0
            }
        }()

        let barcodeType = PTTSCBarcodeStyle(rawValue: UInt(typeInt)) ?? PTTSCBarcodeStyle(rawValue: 0)!
        let readable = PTTSCBarcodeReadbleStyle(rawValue: 1) ?? PTTSCBarcodeReadbleStyle(rawValue: 1)!
        let rotation = PTTSCStyleRotation(rawValue: 0) ?? PTTSCStyleRotation(rawValue: 0)!
        let ratio = PTTSCBarcodeRatio(rawValue: 2) ?? PTTSCBarcodeRatio(rawValue: 2)!

        cmd.printBarcode(
            withXPos: startX,
            yPos: startY,
            type: barcodeType,
            height: height,
            readable: readable,
            rotation: rotation,
            ratio: ratio,
            context: code
        )

        cmd.print(withSets: 1, copies: 1)
        sendToPrinter(cmd.cmdData as Data, deviceId: deviceId, connectionType: connectionType)
        result(true)
    }

    func printQRCode(args: [String: Any], result: @escaping FlutterResult) {
        let code = args["code"] as? String ?? ""
        let startX = args["x"] as? Int ?? 0
        let startY = args["y"] as? Int ?? 0
        let size = args["size"] as? Int ?? 4
        let width = args["width"] as? Int ?? 40
        let heightMM = args["heightMM"] as? Int ?? 30
        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String

        let cmd = PTCommandTSPL()
        cmd.encoding = String.Encoding.utf8.rawValue
        cmd.setPrintAreaSizeWithWidth(width, height: heightMM)
        cmd.setGapWithDistance(1, offset: 0)
        cmd.setCLS()

        let ecc = PTTSCQRcodeEcclevel(rawValue: 76) ?? PTTSCQRcodeEcclevel(rawValue: 76)!
        let widthQR = PTTSCQRcodeWidth(rawValue: UInt(size)) ?? PTTSCQRcodeWidth(rawValue: 4)!
        let mode = PTTSCQRCodeMode(rawValue: 77) ?? PTTSCQRCodeMode(rawValue: 77)!
        let rotation = PTTSCStyleRotation(rawValue: 0) ?? PTTSCStyleRotation(rawValue: 0)!
        let model = PTTSCQRCodeModel(rawValue: 1) ?? PTTSCQRCodeModel(rawValue: 1)!
        let mask = PTTSCQRcodeMask(rawValue: 8) ?? PTTSCQRcodeMask(rawValue: 8)!

        cmd.printQRcode(
            withXPos: startX,
            yPos: startY,
            eccLevel: ecc,
            cellWidth: widthQR,
            mode: mode,
            rotation: rotation,
            model: model,
            mask: mask,
            context: code
        )

        cmd.print(withSets: 1, copies: 1)
        sendToPrinter(cmd.cmdData as Data, deviceId: deviceId, connectionType: connectionType)
        result(true)
    }

    func printBarcodeESC(args: [String: Any], result: @escaping FlutterResult) {
        let code = args["code"] as? String ?? ""
        let typeVal = args["type"] as? String ?? "128"
        let width = args["width"] as? Int ?? 2
        let height = args["height"] as? Int ?? 162
        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String

        let esc = PTCommandESC()
        esc.initCommandQueue()
        esc.appendZeroData()

        let typeInt: Int = {
            switch typeVal {
            case "UPCA": return 65
            case "UPCE": return 66
            case "EAN13": return 67
            case "EAN8": return 68
            case "CODE39": return 69
            case "ITF": return 70
            case "CODEBAR": return 71
            case "CODE93": return 72
            default: return 73
            }
        }()

        let barcodeType = ESCBarcode(rawValue: typeInt) ?? ESCBarcode(rawValue: 73)!
        esc.append(barcodeType, data: code, justification: 1, width: width, height: height, hri: 2)
        esc.printAndLineFeed()
        esc.setFullCutWithDistance(1)

        let data = esc.getCommandData() as Data?
        if let printData = data {
            sendToPrinter(printData, deviceId: deviceId, connectionType: connectionType)
            result(true)
        } else {
            result(FlutterError(code: "BUILD_FAILED", message: "Cannot build ESC barcode command", details: nil))
        }
    }

    func printQRCodeESC(args: [String: Any], result: @escaping FlutterResult) {
        let code = args["code"] as? String ?? ""
        let size = args["size"] as? Int ?? 8
        let deviceId = args["device_id"] as? String
        let connectionType = args["connection_type"] as? String

        let esc = PTCommandESC()
        esc.initCommandQueue()
        esc.appendZeroData()

        esc.appendQRCodeData(code, justification: 1, leftMargin: 0, eccLevel: 48, model: 49, size: size)
        esc.printAndLineFeed()
        esc.setFullCutWithDistance(1)

        let data = esc.getCommandData() as Data?
        if let printData = data {
            sendToPrinter(printData, deviceId: deviceId, connectionType: connectionType)
            result(true)
        } else {
            result(FlutterError(code: "BUILD_FAILED", message: "Cannot build ESC QR code command", details: nil))
        }
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

        guard let uiImage = imageFromFlutter(imageData) else {
            result(false)
            return
        }
        let binarizedImage = uiImage.binarized(threshold: 200) ?? uiImage
        guard let cgImage = binarizedImage.cgImage else {
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


    // MARK: - Utilities

    func imageFromFlutter(_ data: FlutterStandardTypedData) -> UIImage? {
        return UIImage(data: data.data)
    }
}
