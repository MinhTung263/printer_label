import CoreBluetooth
import Flutter

// MARK: - BLEManager
// Singleton quản lý toàn bộ vòng đời CoreBluetooth.
// Tại sao singleton là bắt buộc:
//   - CBCentralManager phải tồn tại xuyên suốt app để giữ kết nối
//   - CBPeripheral PHẢI được giữ strong reference — iOS sẽ deallocate nếu không giữ
//   - Nếu tạo mới CBCentralManager theo UI lifecycle → mất kết nối mỗi khi navigate
// Tại sao iOS BLE khác Android Bluetooth Classic:
//   - iOS dùng UUID (NSUUID) thay MAC address — MAC bị ẩn từ iOS 13+
//   - CBPeripheral object không thể recreate từ string — phải lấy từ scan cache
//   - Kết nối BLE qua CBCentralManager.connect(_:) không phải socket TCP
//   - Phải discover services → characteristics trước khi write

final class BLEManager: NSObject {

    static let shared = BLEManager()

    // CBCentralManager chạy trên main queue, giữ sống suốt app lifecycle
    private var centralManager: CBCentralManager!

    // Cache CBPeripheral theo UUID string — PHẢI giữ strong reference
    // Tại sao: CBPeripheral không có init(identifier:), nếu bị deallocate
    // sẽ không thể reconnect mà không scan lại
    private var discoveredPeripherals: [String: CBPeripheral] = [:]

    // Các peripheral đang kết nối thành công
    private var connectedPeripherals: [String: CBPeripheral] = [:]

    // Characteristic có khả năng write cho mỗi peripheral
    // tuple: (characteristic, writeType) — .withResponse hoặc .withoutResponse
    private var writableCharacteristics: [String: (CBCharacteristic, CBCharacteristicWriteType)] = [:]

    // Đếm số service còn chờ discover characteristics
    // Dùng để biết khi nào toàn bộ services đã được process
    private var pendingServiceCount: [String: Int] = [:]

    // Flutter result callbacks chờ kết quả bất đồng bộ từ BLE delegates
    private var pendingConnectResults: [String: FlutterResult] = [:]
    private var pendingDisconnectResults: [String: FlutterResult] = [:]

    // EventChannel sink để push device được discover về Flutter
    var scanEventSink: FlutterEventSink?

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
        // Xóa cache thiết bị cũ, giữ lại những thiết bị đang kết nối
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

    // identifier là UUID string từ peripheral.identifier.uuidString
    // PHẢI có trong discoveredPeripherals cache — không thể recreate từ string
    func connect(identifier: String, result: @escaping FlutterResult) {
        guard let peripheral = discoveredPeripherals[identifier] else {
            result(FlutterError(
                code: "PERIPHERAL_NOT_FOUND",
                message: "Peripheral \(identifier) not in cache. Run scan first.",
                details: nil
            ))
            return
        }

        if peripheral.state == .connected {
            result(true)
            return
        }

        if peripheral.state == .connecting {
            result(FlutterError(
                code: "ALREADY_CONNECTING",
                message: "Already connecting to \(identifier)",
                details: nil
            ))
            return
        }

        pendingConnectResults[identifier] = result
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    // MARK: - Disconnect

    func disconnect(identifier: String, result: @escaping FlutterResult) {
        guard let peripheral = connectedPeripherals[identifier] else {
            result(false)
            return
        }
        pendingDisconnectResults[identifier] = result
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func disconnectAll(result: @escaping FlutterResult) {
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
            result(FlutterError(
                code: "NOT_CONNECTED",
                message: "Peripheral \(identifier) is not connected",
                details: nil
            ))
            return
        }

        guard let charTuple = writableCharacteristics[identifier] else {
            result(FlutterError(
                code: "NO_CHARACTERISTIC",
                message: "No writable characteristic for \(identifier). Connect first.",
                details: nil
            ))
            return
        }

        let (characteristic, writeType) = charTuple
        // BLE MTU thường 182–512 bytes. Chunk 182 bytes để an toàn trên mọi thiết bị
        let chunkSize = 182
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            peripheral.writeValue(chunk, for: characteristic, type: writeType)
            offset = end
        }
        result(true)
    }

    // Write tới peripheral đầu tiên đang kết nối (dùng khi không chỉ định device_id)
    func writeDataToFirstConnected(_ data: Data, result: @escaping FlutterResult) {
        guard let first = connectedPeripherals.first else {
            result(FlutterError(
                code: "NO_CONNECTED_DEVICE",
                message: "No BLE peripheral is currently connected",
                details: nil
            ))
            return
        }
        writeData(data, toIdentifier: first.key, result: result)
    }

    // MARK: - Status

    func isConnected(identifier: String) -> Bool {
        return connectedPeripherals[identifier]?.state == .connected
    }

    func hasAnyConnection() -> Bool {
        return !connectedPeripherals.isEmpty
    }

    func getDiscoveredDevices() -> [[String: Any]] {
        return discoveredPeripherals.values.map { peripheral in
            [
                "name": peripheral.name                                                                                                               ,
                "identifier": peripheral.identifier.uuidString
            ]
        }
    }

    // Gửi lại tất cả device đã cache vào sink mới.
    // Dùng khi Flutter subscribe sau khi scan đã chạy (race condition).
    func replayCachedDevices(to sink: FlutterEventSink) {
        for peripheral in discoveredPeripherals.values {
            sink([
                "name": peripheral.name ?? "Unknown",
                "identifier": peripheral.identifier.uuidString,
                "mac": peripheral.identifier.uuidString
            ] as [String: Any])
        }
    }

    func getAllConnectionStatus() -> [String: Bool] {
        var status: [String: Bool] = [:]
        for (id, peripheral) in connectedPeripherals {
            status[id] = peripheral.state == .connected
        }
        return status
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if isScanning {
                centralManager.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        case .unauthorized:
            print("[BLEManager] Bluetooth permission denied. Add NSBluetoothAlwaysUsageDescription to Info.plist.")
        case .poweredOff:
            print("[BLEManager] Bluetooth is powered off.")
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let identifier = peripheral.identifier.uuidString

        // Giữ strong reference — bắt buộc để connect sau này
        // Nếu không cache ở đây, iOS có thể deallocate peripheral object
        discoveredPeripherals[identifier] = peripheral

        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unknown"

        let deviceInfo: [String: Any] = [
            "name": name,
            "identifier": identifier,
            "mac": identifier   // alias để tương thích Flutter model
        ]

        scanEventSink?(deviceInfo)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        let identifier = peripheral.identifier.uuidString
        connectedPeripherals[identifier] = peripheral
        peripheral.delegate = self
        // Discover tất cả services — nil = không lọc
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let identifier = peripheral.identifier.uuidString
        if let result = pendingConnectResults.removeValue(forKey: identifier) {
            result(FlutterError(
                code: "CONNECT_FAILED",
                message: error?.localizedDescription ?? "Failed to connect",
                details: nil
            ))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let identifier = peripheral.identifier.uuidString

        connectedPeripherals.removeValue(forKey: identifier)
        writableCharacteristics.removeValue(forKey: identifier)
        pendingServiceCount.removeValue(forKey: identifier)

        // Nếu có pending disconnect result → trả về thành công
        if let result = pendingDisconnectResults.removeValue(forKey: identifier) {
            result(true)
        }

        // KHÔNG xóa discoveredPeripherals — giữ cache để reconnect không cần scan lại
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let identifier = peripheral.identifier.uuidString

        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            if let result = pendingConnectResults.removeValue(forKey: identifier) {
                result(FlutterError(
                    code: "SERVICE_DISCOVERY_FAILED",
                    message: error?.localizedDescription ?? "No services found",
                    details: nil
                ))
            }
            return
        }

        // Lưu số service cần process để biết khi nào xong
        pendingServiceCount[identifier] = services.count

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let identifier = peripheral.identifier.uuidString

        if let chars = service.characteristics {
            for char in chars {
                // Ưu tiên .write (withResponse) hơn .writeWithoutResponse
                // .withResponse: printer xác nhận đã nhận → reliable hơn
                // .writeWithoutResponse: không có ACK → nhanh hơn nhưng có thể mất data
                if char.properties.contains(.write) {
                    writableCharacteristics[identifier] = (char, .withResponse)
                    break
                } else if char.properties.contains(.writeWithoutResponse),
                          writableCharacteristics[identifier] == nil {
                    writableCharacteristics[identifier] = (char, .withoutResponse)
                }
            }
        }

        // Giảm pending count
        let remaining = (pendingServiceCount[identifier] ?? 1) - 1
        pendingServiceCount[identifier] = remaining

        guard remaining == 0 else { return }

        // Tất cả services đã được process — resolve connect result
        pendingServiceCount.removeValue(forKey: identifier)

        if let result = pendingConnectResults.removeValue(forKey: identifier) {
            if writableCharacteristics[identifier] != nil {
                result(true)
            } else {
                result(FlutterError(
                    code: "NO_WRITABLE_CHARACTERISTIC",
                    message: "Printer connected but no writable characteristic found",
                    details: nil
                ))
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[BLEManager] Write error for \(peripheral.identifier.uuidString): \(error)")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverDescriptorsFor characteristic: CBCharacteristic,
        error: Error?
    ) {}
}
