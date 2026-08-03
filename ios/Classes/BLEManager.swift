import CoreBluetooth
import Flutter

// MARK: - BLEManager
// Singleton quản lý toàn bộ vòng đời CoreBluetooth.
final class BLEManager: NSObject {

    static let shared = BLEManager()

    private var centralManager: CBCentralManager!

    // MARK: - State được bảo vệ bởi stateLock
    // Các dictionary dưới đây bị GHI từ delegate CoreBluetooth (main queue) và ĐỌC
    // từ thread gọi của Flutter khi in. Dictionary của Swift KHÔNG thread-safe: đọc
    // và ghi đồng thời có thể trả về giá trị của phần tử khác hoặc crash. Khi in 2
    // máy cùng lúc điều này làm lấy sai characteristic → gửi dữ liệu sai máy.
    // Mọi truy cập BẮT BUỘC đi qua stateLock.
    private let stateLock = NSLock()
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var connectedPeripherals: [String: CBPeripheral] = [:]
    private var writableCharacteristics: [String: (CBCharacteristic, CBCharacteristicWriteType)] = [:]
    private var pendingServiceCount: [String: Int] = [:]
    private var pendingConnectResults: [String: FlutterResult] = [:]
    private var pendingDisconnectResults: [String: FlutterResult] = [:]

    // ⭐ Timeout cho connect — tránh treo khi máy in tắt
    private var connectTimeouts: [String: DispatchWorkItem] = [:]
    private let connectTimeoutInterval: TimeInterval = 5.0 // 5 giây

    /// Thực thi [body] khi đang giữ stateLock.
    private func withState<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    /// Gọi [body] trên main thread. Callback CoreBluetooth chạy trên `bleQueue`, nhưng
    /// mọi thứ chạm tới Flutter (FlutterResult, EventSink) BẮT BUỘC ở main thread.
    private func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }

    private let minScanRSSI: Int = -70

    // Hàng đợi ghi TUẦN TỰ RIÊNG cho TỪNG máy in (theo identifier). Mỗi máy BLE là
    // một peripheral độc lập, nên 2 máy KHÁC nhau ghi song song được — chỉ cần
    // các gói trên CÙNG một máy đi tuần tự để không chèn vào nhau gây in ra rác.
    // Nhờ vậy in cùng lúc nhiều máy không phải đợi nhau.
    private var writeQueues: [String: DispatchQueue] = [:]
    private let writeQueuesLock = NSLock()

    private func writeQueue(for identifier: String) -> DispatchQueue {
        writeQueuesLock.lock()
        defer { writeQueuesLock.unlock() }
        if let q = writeQueues[identifier] { return q }
        let q = DispatchQueue(label: "com.printer.printer_label.ble.write.\(identifier)")
        writeQueues[identifier] = q
        return q
    }

    // MARK: - Flow control cho việc ghi
    // iOS chỉ nhận `writeWithoutResponse` khi bộ đệm nội bộ còn chỗ. Nếu ghi tiếp khi
    // đã đầy, iOS ÂM THẦM LOẠI BỎ gói — không callback, không lỗi. Máy in mất byte
    // giữa stream ESC/POS → lệch escape sequence → in ra ký tự rác.
    // Khi in 1 máy thì băng thông BLE dư nên hiếm khi lộ; in 2 máy cùng lúc chúng
    // CHIA SẺ chung một radio, throughput mỗi máy tụt khoảng một nửa, nên đầy buffer
    // và mất byte liên tục. Vì vậy phải chờ tín hiệu thật từ iOS thay vì sleep theo
    // một tốc độ đoán trước.
    private let signalLock = NSLock()
    /// Semaphore báo "buffer đã sẵn chỗ" theo từng máy (peripheralIsReady...).
    private var readySignals: [String: DispatchSemaphore] = [:]
    /// Semaphore báo "đã nhận ack ghi" theo từng máy (didWriteValueFor).
    private var ackSignals: [String: DispatchSemaphore] = [:]
    /// Lỗi ghi gần nhất của từng máy, dùng để báo về Flutter.
    private var lastWriteErrors: [String: Error] = [:]

    private func signal(_ dict: inout [String: DispatchSemaphore], for identifier: String) -> DispatchSemaphore {
        if let s = dict[identifier] { return s }
        let s = DispatchSemaphore(value: 0)
        dict[identifier] = s
        return s
    }

    private func readySignal(for identifier: String) -> DispatchSemaphore {
        signalLock.lock()
        defer { signalLock.unlock() }
        return signal(&readySignals, for: identifier)
    }

    private func ackSignal(for identifier: String) -> DispatchSemaphore {
        signalLock.lock()
        defer { signalLock.unlock() }
        return signal(&ackSignals, for: identifier)
    }

    /// Xóa mọi tín hiệu/lỗi còn tồn của [identifier] để lần in sau bắt đầu sạch.
    private func resetSignals(for identifier: String) {
        signalLock.lock()
        defer { signalLock.unlock() }
        readySignals.removeValue(forKey: identifier)
        ackSignals.removeValue(forKey: identifier)
        lastWriteErrors.removeValue(forKey: identifier)
    }

    private func recordWriteError(_ error: Error?, for identifier: String) {
        signalLock.lock()
        defer { signalLock.unlock() }
        if let error = error { lastWriteErrors[identifier] = error }
    }

    private func takeWriteError(for identifier: String) -> Error? {
        signalLock.lock()
        defer { signalLock.unlock() }
        return lastWriteErrors.removeValue(forKey: identifier)
    }

    // MARK: - Máy in cần ghi chậm
    // Một số máy in mini dùng pin không chịu được luồng dữ liệu tốc độ cao: đầu in kéo
    // dòng vượt ngưỡng bảo vệ và máy TỰ NGẮT NGUỒN giữa lúc in. Với các model này phải
    // dùng write CÓ XÁC NHẬN (.withResponse) để tốc độ tự khớp khả năng tiêu thụ thật.
    // Các máy còn lại giữ .withoutResponse cho tốc độ tối đa.
    private static let slowWriteNameKeywords = [
        "ri-5809", "ri5809"
    ]

    /// Máy in tên [name] có cần ghi có xác nhận (chậm hơn nhưng an toàn nguồn) không.
    static func needsSlowWrite(_ name: String?) -> Bool {
        guard let name = name?.lowercased(), !name.isEmpty else { return false }
        return slowWriteNameKeywords.contains { name.contains($0) }
    }

    var scanEventSink: FlutterEventSink?
    /// true = chỉ hiển thị thiết bị BLE được nhận dạng là máy in, false = tất cả thiết bị
    var filterPrinterOnly: Bool = true
    private var isScanning = false

    /// Queue riêng cho toàn bộ callback CoreBluetooth.
    ///
    /// TRƯỚC ĐÂY dùng DispatchQueue.main: mọi delegate — gồm cả
    /// `peripheralIsReady(toSendWriteWithoutResponse:)` mà vòng ghi đang chờ — phải xếp
    /// hàng sau công việc render UI của Flutter. Main thread bận một frame là tín hiệu
    /// "buffer đã sẵn chỗ" bị hoãn, luồng in khựng lại; UI rảnh thì chạy mượt. Đó là lý
    /// do bản in LÚC MƯỢT LÚC GIẬT CỤC không theo quy luật nào, và vì sao chỉnh nhịp
    /// nghỉ mãi không dứt — thủ phạm là tranh chấp main thread, không phải tham số nhịp.
    private let bleQueue = DispatchQueue(label: "com.printer.printer_label.ble.central")

    private override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    // MARK: - Scan
    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        withState {
            discoveredPeripherals = discoveredPeripherals.filter { connectedPeripherals[$0.key] != nil }
        }
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
        if let peripheral = withState({ discoveredPeripherals[identifier] }) {
            _connect(peripheral, identifier: identifier, result: result)
            return
        }
        // 2. Retrieve từ UUID đã lưu — KHÔNG CẦN SCAN LẠI
        if let uuid = UUID(uuidString: identifier) {
            let retrieved = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = retrieved.first {
                withState { discoveredPeripherals[identifier] = peripheral }
                _connect(peripheral, identifier: identifier, result: result)
                return
            }
            // 3. Retrieve từ thiết bị đang kết nối hệ thống
            let connected = centralManager.retrieveConnectedPeripherals(withServices: [])
            if let peripheral = connected.first(where: { $0.identifier.uuidString == identifier }) {
                withState { discoveredPeripherals[identifier] = peripheral }
                _connect(peripheral, identifier: identifier, result: result)
                return
            }
        }
        // 4. Thất bại → false (giống Android)
        result(false)
    }

    private func _connect(_ peripheral: CBPeripheral, identifier: String, result: @escaping FlutterResult) {
        // ⭐ Hủy timeout cũ nếu có
        withState { connectTimeouts[identifier]?.cancel() }

        if peripheral.state == .connected {
            if withState({ writableCharacteristics[identifier] != nil }) {
                result(true)
                return
            }
            peripheral.delegate = self
            peripheral.discoverServices(nil)
            withState { pendingConnectResults[identifier] = result }
            scheduleConnectTimeout(peripheral, identifier: identifier, result: result)
            return
        }
        if peripheral.state == .connecting {
            result(false) // giống Android
            return
        }

        // Máy in mất nguồn ĐỘT NGỘT (tự ngắt do sụt áp) không kịp báo disconnect sạch,
        // để lại characteristic cũ đã chết trong cache. Lần connect sau sẽ discover lại
        // service, nhưng nếu characteristic cũ còn đó thì mọi write đều ghi vào handle
        // không còn hiệu lực → "connect lại lỗi". Dọn state cũ trước khi kết nối mới.
        withState {
            writableCharacteristics.removeValue(forKey: identifier)
            pendingServiceCount.removeValue(forKey: identifier)
            pendingConnectResults[identifier] = result
        }
        resetSignals(for: identifier)
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        scheduleConnectTimeout(peripheral, identifier: identifier, result: result)
    }

    /// Đặt hẹn giờ trả về false nếu kết nối/discover không hoàn tất kịp — tránh treo
    /// khi máy in đã tắt nguồn nhưng iOS chưa kịp báo.
    private func scheduleConnectTimeout(_ peripheral: CBPeripheral, identifier: String, result: @escaping FlutterResult) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let pending = self.withState { () -> FlutterResult? in
                let r = self.pendingConnectResults.removeValue(forKey: identifier)
                self.connectTimeouts.removeValue(forKey: identifier)
                return r
            }
            if pending != nil {
                self.centralManager.cancelPeripheralConnection(peripheral)
                result(false)
            }
        }
        withState { connectTimeouts[identifier] = workItem }
        DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeoutInterval, execute: workItem)
    }

    // MARK: - Disconnect
    func disconnect(identifier: String, result: @escaping FlutterResult) {
        let peripheral: CBPeripheral? = withState {
            // ⭐ Hủy timeout nếu đang connect
            connectTimeouts[identifier]?.cancel()
            connectTimeouts.removeValue(forKey: identifier)

            guard let p = connectedPeripherals[identifier] else { return nil }
            pendingDisconnectResults[identifier] = result
            return p
        }
        guard let peripheral = peripheral else {
            result(false)
            return
        }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func disconnectAll(result: @escaping FlutterResult) {
        let peripherals: [CBPeripheral] = withState {
            // ⭐ Hủy tất cả timeout
            for (_, work) in connectTimeouts { work.cancel() }
            connectTimeouts.removeAll()
            return Array(connectedPeripherals.values)
        }
        guard !peripherals.isEmpty else {
            result(false)
            return
        }
        for peripheral in peripherals {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        result(true)
    }

    // MARK: - Write
    func writeData(_ data: Data, toIdentifier identifier: String, result: @escaping FlutterResult) {
        // Chụp peripheral + characteristic MỘT LẦN dưới lock. Nếu đọc lẻ nhiều lần
        // trong lúc delegate đang mutate (ví dụ máy kia vừa kết nối/ngắt), có thể
        // lấy được cặp không nhất quán → ghi sang máy khác.
        let snapshot: (CBPeripheral, CBCharacteristic, CBCharacteristicWriteType)? = withState {
            guard let peripheral = connectedPeripherals[identifier],
                  let (characteristic, writeType) = writableCharacteristics[identifier] else { return nil }
            return (peripheral, characteristic, writeType)
        }

        guard let (peripheral, characteristic, writeType) = snapshot else {
            let connected = withState { connectedPeripherals[identifier] != nil }
            if connected {
                result(FlutterError(code: "NO_CHARACTERISTIC", message: "No writable characteristic for \(identifier). Connect first.", details: nil))
            } else {
                result(FlutterError(code: "NOT_CONNECTED", message: "Peripheral \(identifier) is not connected", details: nil))
            }
            return
        }
        guard peripheral.state == .connected else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Peripheral \(identifier) is not connected", details: nil))
            return
        }

        // Nhịp gửi phụ thuộc kiểu ghi — hai kiểu có cơ chế backpressure KHÁC nhau:
        //
        // .withResponse: mỗi gói phải được máy in ack mới gửi gói kế. Bản thân ack ĐÃ LÀ
        //   backpressure thật, nên KHÔNG cần nghỉ thêm — nghỉ nữa là chồng hai lớp làm
        //   chậm lên nhau, gây in giật cục. Dùng hết MTU để mỗi round-trip chở được
        //   nhiều byte nhất (giới hạn 120 byte là của SPP bên Android, không áp cho BLE).
        //
        // .withoutResponse: không có phản hồi từ máy in. `canSendWriteWithoutResponse`
        //   chỉ báo bộ đệm CỦA IOS còn chỗ, không biết bộ đệm MÁY IN đã đầy chưa — nên
        //   vẫn cần nhịp nghỉ giống Android để firmware kịp in và giải phóng buffer.
        let maxWriteLen = peripheral.maximumWriteValueLength(for: writeType)
        let chunkSize: Int
        let perChunkPause: TimeInterval
        let blockPause: TimeInterval
        let blockSize: Int
        if writeType == .withResponse {
            chunkSize = max(1, maxWriteLen)
            perChunkPause = 0
            blockPause = 0
            blockSize = .max
        } else {
            // Dùng hết MTU: ít gói hơn cho cùng lượng dữ liệu → in nhanh hơn.
            //
            // Nhịp nghỉ RẢI ĐỀU thay vì dồn cục: nghỉ 80ms sau mỗi 1500 byte (kiểu
            // Android) làm máy in trôi một đoạn rồi KHỰNG hẳn 80ms, lặp lại — chính là
            // cảm giác "giật giật". Chia cùng lượng thời gian đó đều cho từng gói thì
            // firmware vẫn được nghỉ tương đương nhưng dòng giấy chạy liên tục, êm hơn.
            // (~1500 byte ≈ 8 gói MTU → 80ms/8 ≈ 10ms mỗi gói.)
            chunkSize = max(1, maxWriteLen)
            let chunksPerBlock = max(1, 1500 / chunkSize)
            perChunkPause = 0.080 / Double(chunksPerBlock)
            blockPause = 0
            blockSize = .max
        }

        resetSignals(for: identifier)

        // Ghi trên hàng đợi TUẦN TỰ RIÊNG của máy này: vừa tránh block Main Thread
        // (gây khựng UI), vừa đảm bảo các gói trên cùng máy không chèn vào nhau.
        // Máy khác có hàng đợi riêng nên vẫn in song song.
        writeQueue(for: identifier).async { [weak self] in
            guard let self = self else { return }

            var offset = 0
            var bytesSentInBlock = 0
            var failure: FlutterError?

            while offset < data.count {
                // Máy in có thể bị rút/tắt giữa lúc in — dừng ngay thay vì ghi vào hư không.
                guard peripheral.state == .connected else {
                    failure = FlutterError(code: "DISCONNECTED", message: "Peripheral \(identifier) disconnected while writing", details: nil)
                    break
                }

                let end = min(offset + chunkSize, data.count)
                let chunk = data.subdata(in: offset..<end)

                if writeType == .withoutResponse {
                    // Chờ iOS báo còn chỗ trong bộ đệm. Đây là flow control THẬT: nó tự
                    // thích ứng khi băng thông bị chia cho 2 máy, nên không mất byte.
                    if !self.waitUntilReadyToWrite(peripheral, identifier: identifier) {
                        failure = FlutterError(code: "WRITE_TIMEOUT", message: "Timed out waiting for \(identifier) to accept data", details: nil)
                        break
                    }
                    peripheral.writeValue(chunk, for: characteristic, type: writeType)
                } else {
                    // Chế độ có phản hồi: chờ ack thật của iOS thay vì ngủ cố định 25ms.
                    let ack = self.ackSignal(for: identifier)
                    peripheral.writeValue(chunk, for: characteristic, type: writeType)
                    if ack.wait(timeout: .now() + 5.0) == .timedOut {
                        failure = FlutterError(code: "WRITE_TIMEOUT", message: "Timed out waiting for write ack from \(identifier)", details: nil)
                        break
                    }
                    if let error = self.takeWriteError(for: identifier) {
                        failure = FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil)
                        break
                    }
                }

                offset = end

                // Nhịp nghỉ cho firmware máy in kịp xử lý — CHỈ áp dụng cho
                // .withoutResponse; với .withResponse các giá trị này bằng 0.
                if perChunkPause > 0 || blockPause > 0 {
                    bytesSentInBlock += chunk.count
                    if perChunkPause > 0 { Thread.sleep(forTimeInterval: perChunkPause) }
                    if bytesSentInBlock >= blockSize {
                        Thread.sleep(forTimeInterval: blockPause)
                        bytesSentInBlock = 0
                    }
                }
            }

            // Trả kết quả về Main Thread cho Flutter
            DispatchQueue.main.async {
                if let failure = failure {
                    result(failure)
                } else {
                    result(true)
                }
            }
        }
    }

    /// Chờ tới khi [peripheral] sẵn sàng nhận thêm `writeWithoutResponse`.
    /// Trả về false nếu quá thời gian chờ (máy in treo hoặc mất kết nối).
    private func waitUntilReadyToWrite(_ peripheral: CBPeripheral, identifier: String) -> Bool {
        if peripheral.canSendWriteWithoutResponse { return true }

        let ready = readySignal(for: identifier)
        let deadline = Date().addingTimeInterval(5.0)

        while !peripheral.canSendWriteWithoutResponse {
            if Date() >= deadline { return false }
            guard peripheral.state == .connected else { return false }
            // Chờ tín hiệu peripheralIsReady(toSendWriteWithoutResponse:). Dùng timeout
            // ngắn để vẫn tự thoát nếu tín hiệu đến trước khi kịp wait (tránh treo vĩnh viễn).
            _ = ready.wait(timeout: .now() + 0.05)
        }
        return true
    }

    func writeDataToFirstConnected(_ data: Data, result: @escaping FlutterResult) {
        guard let firstKey = withState({ connectedPeripherals.keys.sorted().first }) else {
            result(FlutterError(code: "NO_CONNECTED_DEVICE", message: "No BLE peripheral is currently connected", details: nil))
            return
        }
        writeData(data, toIdentifier: firstKey, result: result)
    }

    func writeDataToAllConnected(_ data: Data, completion: @escaping (Bool) -> Void) {
        let keys = withState { Array(connectedPeripherals.keys) }
        guard !keys.isEmpty else {
            completion(false)
            return
        }
        for key in keys {
            writeData(data, toIdentifier: key, result: { _ in })
        }
        completion(true)
    }

    // MARK: - Status
    var isBluetoothEnabled: Bool { centralManager.state == .poweredOn }
    func isConnected(identifier: String) -> Bool {
        withState { connectedPeripherals[identifier] }?.state == .connected
    }
    func hasAnyConnection() -> Bool { withState { !connectedPeripherals.isEmpty } }

    func getDiscoveredDevices() -> [[String: Any]] {
        let peripherals = withState { Array(discoveredPeripherals.values) }
        return peripherals.map { peripheral in
            ["name": peripheral.name ?? "Unknown", "identifier": peripheral.identifier.uuidString]
        }
    }

    func replayCachedDevices(to sink: FlutterEventSink) {
        let peripherals = withState { Array(discoveredPeripherals.values) }
        for peripheral in peripherals {
            sink(["name": peripheral.name ?? "Unknown", "identifier": peripheral.identifier.uuidString, "mac": peripheral.identifier.uuidString] as [String: Any])
        }
    }

    func getAllConnectionStatus() -> [String: Bool] {
        let entries = withState { connectedPeripherals.map { ($0.key, $0.value) } }
        var status: [String: Bool] = [:]
        for (id, peripheral) in entries { status[id] = peripheral.state == .connected }
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
        withState { discoveredPeripherals[identifier] = peripheral }
        onMain { [weak self] in
            self?.scanEventSink?(["name": name, "identifier": identifier, "mac": identifier] as [String: Any])
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let identifier = peripheral.identifier.uuidString
        withState {
            // ⭐ Hủy timeout connect
            connectTimeouts[identifier]?.cancel()
            connectTimeouts.removeValue(forKey: identifier)
            connectedPeripherals[identifier] = peripheral
        }
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier.uuidString
        let pending: FlutterResult? = withState {
            connectTimeouts[identifier]?.cancel()
            connectTimeouts.removeValue(forKey: identifier)
            return pendingConnectResults.removeValue(forKey: identifier)
        }
        onMain { pending?(false) } // giống Android
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier.uuidString
        let outcome: (disconnect: FlutterResult?, connect: FlutterResult?) = withState {
            connectedPeripherals.removeValue(forKey: identifier)
            writableCharacteristics.removeValue(forKey: identifier)
            pendingServiceCount.removeValue(forKey: identifier)
            connectTimeouts[identifier]?.cancel()
            connectTimeouts.removeValue(forKey: identifier)
            return (
                pendingDisconnectResults.removeValue(forKey: identifier),
                // Máy in có thể tắt nguồn GIỮA lúc đang discover service. Khi đó lời gọi
                // connect vẫn đang chờ — phải trả về false ngay thay vì treo tới timeout.
                pendingConnectResults.removeValue(forKey: identifier)
            )
        }
        // Đánh thức vòng ghi đang chờ, tránh treo tới hết timeout khi máy in mất kết nối.
        readySignal(for: identifier).signal()
        ackSignal(for: identifier).signal()
        onMain {
            outcome.disconnect?(true)
            outcome.connect?(false)
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let identifier = peripheral.identifier.uuidString
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            let pending: FlutterResult? = withState { pendingConnectResults.removeValue(forKey: identifier) }
            onMain { pending?(false) }
            return
        }
        withState { pendingServiceCount[identifier] = services.count }
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let identifier = peripheral.identifier.uuidString
        let outcome: (result: FlutterResult, success: Bool)? = withState {
            // Máy in "yếu nguồn" cần ghi CÓ XÁC NHẬN; các máy khác giữ tốc độ tối đa.
            let needsThrottle = BLEManager.needsSlowWrite(peripheral.name)
            if let chars = service.characteristics {
                for char in chars {
                    if needsThrottle {
                        // .withResponse: mỗi gói chờ máy in ack mới gửi gói kế, nên tốc độ
                        // tự khớp khả năng tiêu thụ thật và máy không bị sụt áp tắt nguồn.
                        if char.properties.contains(.write) {
                            writableCharacteristics[identifier] = (char, .withResponse)
                            break
                        } else if char.properties.contains(.writeWithoutResponse),
                                  writableCharacteristics[identifier] == nil {
                            writableCharacteristics[identifier] = (char, .withoutResponse)
                        }
                    } else {
                        // Mặc định: ưu tiên .withoutResponse cho tốc độ in tối đa.
                        if char.properties.contains(.writeWithoutResponse) {
                            writableCharacteristics[identifier] = (char, .withoutResponse)
                            break
                        } else if char.properties.contains(.write),
                                  writableCharacteristics[identifier] == nil {
                            writableCharacteristics[identifier] = (char, .withResponse)
                        }
                    }
                }
            }
            let remaining = (pendingServiceCount[identifier] ?? 1) - 1
            pendingServiceCount[identifier] = remaining
            guard remaining == 0 else { return nil }
            pendingServiceCount.removeValue(forKey: identifier)
            guard let result = pendingConnectResults.removeValue(forKey: identifier) else { return nil }
            return (result, writableCharacteristics[identifier] != nil)
        }
        // Gọi result NGOÀI lock — closure của Flutter có thể quay lại gọi BLEManager.
        if let outcome = outcome {
            onMain { outcome.result(outcome.success) } // false giống Android khi không tìm được characteristic
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let identifier = peripheral.identifier.uuidString
        if let error = error {
            print("[BLEManager] Write error for \(identifier): \(error)")
            recordWriteError(error, for: identifier)
        }
        // Đánh thức vòng ghi đang chờ ack (chế độ .withResponse).
        ackSignal(for: identifier).signal()
    }

    /// iOS báo bộ đệm `writeWithoutResponse` đã có chỗ trống. Đây là tín hiệu duy nhất
    /// cho biết được phép ghi tiếp — thiếu nó, gói bị loại bỏ âm thầm và máy in ra rác.
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        readySignal(for: peripheral.identifier.uuidString).signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {}
}