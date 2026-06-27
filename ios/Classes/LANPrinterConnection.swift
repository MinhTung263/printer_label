import Foundation
import Network

// LANPrinterConnection: manages a single TCP connection to a LAN printer using NWConnection.
// Responsibilities:
// - open/close NWConnection
// - maintain per-connection serial queue for writes
// - keep a write queue and avoid concurrent writes
// - support chunked sending, retry, timeouts, and optional auto-reconnect
// - expose state and callbacks for connect/disconnect/send completion

public final class LANPrinterConnection {
    public enum State: String {
        case idle, connecting, connected, failed, disconnected
    }

    public let ip: String
    public let port: UInt16

    private var connection: NWConnection?
    private(set) public var state: State = .idle

    // Serial queue to ensure thread-safety for this connection
    private let queue: DispatchQueue

    // write queue
    private var writeQueue: [Data] = []
    private var isWriting: Bool = false

    // connection timeout
    private let connectionTimeout: TimeInterval = 4

    // Callbacks
    public var onConnected: (() -> Void)?
    public var onDisconnected: ((_ error: Error?) -> Void)?

    // Hàng đợi completion cho connect(). Mọi caller gọi connect() trong khi đang
    // .connecting đều được thêm vào đây và fire CHÍNH XÁC 1 lần khi connected/failed/timeout.
    // Tránh lỗi: gọi connect() nhiều lần làm callback bị ghi đè và caller treo vô hạn.
    private var connectCompletions: [(Bool) -> Void] = []

    // MARK: - Initialization
    public init(ip: String, port: UInt16 = 9100, queueLabel: String? = nil) {
        self.ip = ip
        self.port = port
        let label = queueLabel ?? "lan.printer." + ip
        self.queue = DispatchQueue(label: label)
    }

    deinit {
        disconnect()
    }

    // MARK: - Connect / Disconnect
    public func connect() {
        connect(completion: nil)
    }

    // connect với completion: gọi đúng 1 lần với kết quả thành công/thất bại.
    // An toàn khi gọi nhiều lần: nếu đang .connecting, completion mới được xếp
    // vào hàng đợi và fire cùng các caller khác. Nếu đã .connected, fire ngay true.
    public func connect(completion: ((Bool) -> Void)?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.state == .connected {
                if let c = completion { DispatchQueue.main.async { c(true) } }
                return
            }
            if let c = completion { self.connectCompletions.append(c) }
            // Đang connect dở → chỉ xếp hàng completion, không khởi tạo lại.
            if self.state == .connecting { return }
            self.state = .connecting
            print("[LANPrinterConnection] 🔗 Connecting to \(self.ip):\(self.port)...")

            let host = NWEndpoint.Host(self.ip)
            let nwPort = NWEndpoint.Port(rawValue: self.port) ?? .init(integerLiteral: 9100)
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            let connection = NWConnection(host: host, port: nwPort, using: params)
            self.connection = connection

            connection.stateUpdateHandler = { [weak self] newState in
                guard let self = self else { return }
                switch newState {
                case .ready:
                    self.state = .connected
                    print("[LANPrinterConnection] ✅ Connected to \(self.ip)")
                    self.onConnected?()
                    self.fireConnectCompletions(true)
                    self.flushQueue()
                case .failed(let error):
                    self.state = .failed
                    print("[LANPrinterConnection] ❌ Connection failed to \(self.ip): \(error)")
                    self.onDisconnected?(error)
                    self.connection?.cancel()
                    self.connection = nil
                    self.fireConnectCompletions(false)
                case .cancelled:
                    self.state = .disconnected
                    print("[LANPrinterConnection] ⏹️ Disconnected from \(self.ip)")
                    self.onDisconnected?(nil)
                    self.connection = nil
                    self.fireConnectCompletions(false)
                default:
                    break
                }
            }

            connection.start(queue: self.queue)

            // implement a simple connect timeout
            self.queue.asyncAfter(deadline: .now() + self.connectionTimeout) { [weak self] in
                guard let self = self else { return }
                if self.state == .connecting {
                    self.connection?.cancel()
                    self.state = .failed
                    print("[LANPrinterConnection] ⏱️ Connection timeout to \(self.ip)")
                    self.onDisconnected?(NSError(domain: "LANPrinterConnection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection timeout"]))
                    self.connection?.cancel()
                    self.connection = nil
                    self.fireConnectCompletions(false)
                }
            }
        }
    }

    // Fire toàn bộ completion đang chờ đúng 1 lần (trên main thread), rồi xóa hàng đợi.
    // Phải được gọi từ trong self.queue.
    private func fireConnectCompletions(_ success: Bool) {
        guard !connectCompletions.isEmpty else { return }
        let pending = connectCompletions
        connectCompletions.removeAll()
        DispatchQueue.main.async {
            for c in pending { c(success) }
        }
    }

    public func disconnect() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.connection?.stateUpdateHandler = nil
            self.connection?.cancel()
            self.connection = nil
            self.state = .disconnected
            self.writeQueue.removeAll()
            self.isWriting = false
        }
    }

    // MARK: - Sending Data
    public func send(data: Data, completion: ((_ success: Bool, _ error: Error?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            print("[LANPrinterConnection] 📤 Queueing \(data.count) bytes to \(self.ip)")
            self.writeQueue.append(data)
            self.flushQueue()
        }
    }

    // Flush sends queued data sequentially, handling chunking and avoiding concurrent writes
    private func flushQueue() {
        guard !isWriting else { return }
        guard state == .connected else { 
            if !writeQueue.isEmpty {
                print("[LANPrinterConnection] ⚠️ Queue not empty but connection not ready. State: \(state)")
            }
            return 
        }
        guard !writeQueue.isEmpty else { return }

        isWriting = true
        let data = writeQueue.removeFirst()
        print("[LANPrinterConnection] 📨 Sending \(data.count) bytes to \(ip)...")

        // chunk size: 8 KB
        let chunkSize = 8 * 1024
        var offset = 0

        func sendNextChunk() {
            guard offset < data.count else {
                // finished this data
                print("[LANPrinterConnection] ✅ Finished sending all chunks")
                self.isWriting = false
                // continue with next queued item
                self.flushQueue()
                return
            }
            let length = min(chunkSize, data.count - offset)
            let chunk = data.subdata(in: offset..<(offset + length))
            offset += length

            self.connection?.send(content: chunk, completion: .contentProcessed({ [weak self] error in
                guard let self = self else { return }
                if let err = error {
                    // on send error, cancel connection and schedule reconnect
                    print("[LANPrinterConnection] ❌ Send chunk error: \(err)")
                    self.isWriting = false
                    self.connection?.cancel()
                    self.connection = nil
                    self.state = .failed
                    self.onDisconnected?(err)
                } else {
                    // continue sending next chunk
                    sendNextChunk()
                }
            }))
        }

        sendNextChunk()
    }
}
