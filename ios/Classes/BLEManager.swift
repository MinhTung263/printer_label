import CoreBluetooth
import Flutter

// MARK: - BLEManager
// Singleton quản lý toàn bộ vòng đời CoreBluetooth.
final class BLEManager: NSObject {

    static let shared = BLEManager()

    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var connectedPeripherals: [String: CBPeripheral] = [:]
    private var writableCharacteristics: [String: (CBCharacteristic, CBCharacteristicWriteType)] = [:]
    private var pendingServiceCount: [String: Int] = [:]
    private var pendingConnectResults: [String: FlutterResult] = [:]
    private var pendingDisconnectResults: [String: FlutterResult] = [:]

    // ⭐ Timeout cho connect — tránh treo khi máy in tắt
    private var connectTimeouts: [String: DispatchWorkItem] = [:]
    private let connectTimeoutInterval: TimeInterval = 5.0 // 5 giây

    private let minScanRSSI: Int = -70
    var scanEventSink: FlutterEventSink?
    /// true = chỉ hiển thị thiết bị BLE được nhận dạng là máy in, false = tất cả thiết bị
    var filterPrinterOnly: Bool = true
    private var isScanning = false

    private override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: DispatchQueue.main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    // MARK: - Scan
    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        discoveredPeripherals = discoveredPeripherals.filter { connectedPeripherals[$0.key] != nil }
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        guard isScanning else { return }
        isScanning = false
        centralManager.stopScan()
    }

    // MARK: - Connect
    func connect(identifier: String, result: @escaping FlutterResult) {
        // 1. Cache scan
        if let peripheral = discoveredPeripherals[identifier] {
            _connect(peripheral, identifier: identifier, result: result)
            return
        }
        // 2. Retrieve từ UUID đã lưu — KHÔNG CẦN SCAN LẠI
        if let uuid = UUID(uuidString: identifier) {
            let retrieved = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = retrieved.first {
                discoveredPeripherals[identifier] = peripheral
                _connect(peripheral, identifier: identifier, result: result)
                return
            }
            // 3. Retrieve từ thiết bị đang kết nối hệ thống
            let connected = centralManager.retrieveConnectedPeripherals(withServices: [])
            if let peripheral = connected.first(where: { $0.identifier.uuidString == identifier }) {
                discoveredPeripherals[identifier] = peripheral
                _connect(peripheral, identifier: identifier, result: result)
                return
            }
        }
        // 4. Thất bại → false (giống Android)
        result(false)
    }

    private func _connect(_ peripheral: CBPeripheral, identifier: String, result: @escaping FlutterResult) {
        // ⭐ Hủy timeout cũ nếu có
        connectTimeouts[identifier]?.cancel()

        if peripheral.state == .connected {
            if writableCharacteristics[identifier] != nil {
                result(true)
                return
            }
            peripheral.delegate = self
            peripheral.discoverServices(nil)
            pendingConnectResults[identifier] = result
            return
        }
        if peripheral.state == .connecting {
            result(false) // giống Android
            return
        }
        pendingConnectResults[identifier] = result
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)

        // ⭐ Schedule timeout — nếu máy in tắt, sau 8s tự động trả về false
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.pendingConnectResults[identifier] != nil {
                self.pendingConnectResults.removeValue(forKey: identifier)
                self.centralManager.cancelPeripheralConnection(peripheral)
                result(false)
            }
            self.connectTimeouts.removeValue(forKey: identifier)
        }
        connectTimeouts[identifier] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeoutInterval, execute: workItem)
    }

    // MARK: - Disconnect
    func disconnect(identifier: String, result: @escaping FlutterResult) {
        // ⭐ Hủy timeout nếu đang connect
        connectTimeouts[identifier]?.cancel()
        connectTimeouts.removeValue(forKey: identifier)

        guard let peripheral = connectedPeripherals[identifier] else {
            result(false)
            return
        }
        pendingDisconnectResults[identifier] = result
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func disconnectAll(result: @escaping FlutterResult) {
        // ⭐ Hủy tất cả timeout
        for (id, work) in connectTimeouts { work.cancel() }
        connectTimeouts.removeAll()

        guard !connectedPeripherals.isEmpty else {
            result(false)
            return
        }
        for (_, peripheral) in connectedPeripherals {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        result(true)
    }

    // MARK: - Write
    func writeData(_ data: Data, toIdentifier identifier: String, result: @escaping FlutterResult) {
        guard let peripheral = connectedPeripherals[identifier],
              peripheral.state == .connected else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Peripheral \(identifier) is not connected", details: nil))
            return
        }
        guard let charTuple = writableCharacteristics[identifier] else {
            result(FlutterError(code: "NO_CHARACTERISTIC", message: "No writable characteristic for \(identifier). Connect first.", details: nil))
            return
        }
        let (characteristic, writeType) = charTuple
        
        // Giới hạn kích thước gói gửi xuống máy in ở mức tối ưu cho vi xử lý máy in (120 bytes)
        // Gói nhỏ giúp máy in vừa nhận vừa in nhịp nhàng, tránh nghẽn CPU dẫn đến tràn bộ đệm.
        let safeMaxChunkSize = 120
        let chunkSize = min(peripheral.maximumWriteValueLength(for: writeType), safeMaxChunkSize)
        
        // Đưa việc ghi dữ liệu vào Background Thread để tránh block Main Thread (gây khựng UI)
        DispatchQueue.global(qos: .userInitiated).async {
            var offset = 0
            var bytesSentInBlock = 0
            
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                let chunk = data.subdata(in: offset..<end)
                
                peripheral.writeValue(chunk, for: characteristic, type: writeType)
                offset = end
                bytesSentInBlock += chunk.count
                
                // Khoảng nghỉ siêu ngắn giữa các gói tin để duy trì hàng đợi gửi của iOS ổn định
                if writeType == .withoutResponse {
                    Thread.sleep(forTimeInterval: 0.003) // 3ms nghỉ giữa các gói
                } else {
                    Thread.sleep(forTimeInterval: 0.001) // 1ms nghỉ
                }
                
                // Chiến lược chống tràn bộ đệm phần cứng (Block-based Flow Control):
                // Cứ sau mỗi 1500 bytes dữ liệu gửi đi, ta nghỉ thêm 60ms để máy in giải phóng bộ đệm và thực hiện in vật lý.
                if bytesSentInBlock >= 1500 {
                    Thread.sleep(forTimeInterval: 0.060)
                    bytesSentInBlock = 0
                }
            }
            
            // Trả kết quả về Main Thread cho Flutter
            DispatchQueue.main.async {
                result(true)
            }
        }
    }

    func writeDataToFirstConnected(_ data: Data, result: @escaping FlutterResult) {
        guard let first = connectedPeripherals.first else {
            result(FlutterError(code: "NO_CONNECTED_DEVICE", message: "No BLE peripheral is currently connected", details: nil))
            return
        }
        writeData(data, toIdentifier: first.key, result: result)
    }

    // MARK: - Status
    var isBluetoothEnabled: Bool { centralManager.state == .poweredOn }
    func isConnected(identifier: String) -> Bool { connectedPeripherals[identifier]?.state == .connected }
    func hasAnyConnection() -> Bool { !connectedPeripherals.isEmpty }

    func getDiscoveredDevices() -> [[String: Any]] {
        return discoveredPeripherals.values.map { peripheral in
            ["name": peripheral.name ?? "Unknown", "identifier": peripheral.identifier.uuidString]
        }
    }

    func replayCachedDevices(to sink: FlutterEventSink) {
        for peripheral in discoveredPeripherals.values {
            sink(["name": peripheral.name ?? "Unknown", "identifier": peripheral.identifier.uuidString, "mac": peripheral.identifier.uuidString] as [String: Any])
        }
    }

    func getAllConnectionStatus() -> [String: Bool] {
        var status: [String: Bool] = [:]
        for (id, peripheral) in connectedPeripherals { status[id] = peripheral.state == .connected }
        return status
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if isScanning { centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
        case .unauthorized:
            print("[BLEManager] Bluetooth permission denied. Add NSBluetoothAlwaysUsageDescription to Info.plist.")
        case .poweredOff:
            print("[BLEManager] Bluetooth is powered off.")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard RSSI.intValue >= minScanRSSI else { return }
        let identifier = peripheral.identifier.uuidString
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        
        guard !name.isEmpty else { return }
        
        let nameLower = name.lowercased()
        
        // Danh sách từ khóa dài tự động khớp nếu xuất hiện ở bất kỳ đâu trong tên
        let longKeywords = [
            "print", "pos", "thermal", "spp", "label", "barcode", "receipt", "ticket",
            "epson", "star", "citizen", "bixolon", "sewoo", "brother", "tsc", "sprt",
            "hprt", "goojprt", "kiotviet", "sapo", "sunmi", "paperang", "peripage", "niimbot", "zijiang"
        ]
        let matchesLong = longKeywords.contains { nameLower.contains($0) }
        
        // Danh sách tiền tố ngắn (chỉ khớp nếu ở đầu tên hoặc đi kèm khoảng trắng/gạch ngang/gạch dưới)
        let shortPrefixes = [
            "mpt", "rpp", "rt", "pt", "xp", "gp", "zj", "qs", "nt", "mtp", "cc", "dl", "jc"
        ]
        let matchesShort = shortPrefixes.contains { prefix in
            nameLower.hasPrefix(prefix) ||
            nameLower.contains("\(prefix)-") ||
            nameLower.contains("\(prefix) ") ||
            nameLower.contains("_\(prefix)")
        }
        
        guard matchesLong || matchesShort || !filterPrinterOnly else { return }
        
        // ⭐ Chỉ lưu thiết bị vào danh sách phát hiện nếu thỏa mãn bộ lọc máy in
        discoveredPeripherals[identifier] = peripheral
        scanEventSink?(["name": name, "identifier": identifier, "mac": identifier] as [String: Any])
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let identifier = peripheral.identifier.uuidString
        // ⭐ Hủy timeout connect
        connectTimeouts[identifier]?.cancel()
        connectTimeouts.removeValue(forKey: identifier)

        connectedPeripherals[identifier] = peripheral
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier.uuidString
        connectTimeouts[identifier]?.cancel()
        connectTimeouts.removeValue(forKey: identifier)

        if let result = pendingConnectResults.removeValue(forKey: identifier) {
            result(false) // giống Android
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier.uuidString
        connectedPeripherals.removeValue(forKey: identifier)
        writableCharacteristics.removeValue(forKey: identifier)
        pendingServiceCount.removeValue(forKey: identifier)
        if let result = pendingDisconnectResults.removeValue(forKey: identifier) { result(true) }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let identifier = peripheral.identifier.uuidString
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            if let result = pendingConnectResults.removeValue(forKey: identifier) {
                result(false)
            }
            return
        }
        pendingServiceCount[identifier] = services.count
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let identifier = peripheral.identifier.uuidString
        if let chars = service.characteristics {
            for char in chars {
                // Ưu tiên chọn writeWithoutResponse trước để tăng tốc độ in tối đa
                if char.properties.contains(.writeWithoutResponse) {
                    writableCharacteristics[identifier] = (char, .withoutResponse)
                    break
                } else if char.properties.contains(.write), writableCharacteristics[identifier] == nil {
                    writableCharacteristics[identifier] = (char, .withResponse)
                }
            }
        }
        let remaining = (pendingServiceCount[identifier] ?? 1) - 1
        pendingServiceCount[identifier] = remaining
        guard remaining == 0 else { return }
        pendingServiceCount.removeValue(forKey: identifier)
        if let result = pendingConnectResults.removeValue(forKey: identifier) {
            if writableCharacteristics[identifier] != nil {
                result(true)
            } else {
                result(false) // giống Android
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error { print("[BLEManager] Write error for \(peripheral.identifier.uuidString): \(error)") }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {}
}