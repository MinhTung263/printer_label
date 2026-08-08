import Foundation
import Network

// LANPrinterConnection: manages a single TCP connection to a LAN printer using NWConnection.
// Responsibilities:
// - open/close NWConnection
// - maintain per-connection serial queue for writes
// - keep a write queue and avoid concurrent writes
// - support chunked sending, retry with backoff, timeouts
// - nhả socket sau khi in xong để máy in dùng chung được nhiều thiết bị
// - expose state and callbacks for connect/disconnect/send completion

public final class LANPrinterConnection {
    public enum State: String {
        case idle, connecting, connected, failed, disconnected
    }

    /// Lý do một lần gửi thất bại — để tầng trên phân biệt "máy in đang bận" với
    /// "máy in tắt/sai IP" và báo đúng cho người dùng.
    public enum FailureKind: String {
        /// Máy in từ chối hoặc không nhận thêm kết nối — hầu như luôn là do THIẾT BỊ
        /// KHÁC đang giữ socket 9100. Máy in nhiệt phổ biến chỉ cho 1 kết nối một lúc.
        case busy
        /// Không thấy máy in: sai IP, khác mạng, hoặc đã tắt nguồn.
        case unreachable
        /// Đã gửi được một phần dữ liệu rồi mới lỗi — KHÔNG được gửi lại (xem `send`).
        case partiallySent
    }

    public struct SendError: LocalizedError {
        public let kind: FailureKind
        public let underlying: Error?
        public var errorDescription: String? {
            switch kind {
            case .busy:
                return "Máy in đang in đơn của thiết bị khác. Vui lòng thử lại sau vài giây."
            case .unreachable:
                return "Không kết nối được máy in. Kiểm tra máy in đã bật và cùng mạng Wi-Fi."
            case .partiallySent:
                return "Gửi dữ liệu tới máy in bị ngắt giữa lúc in. Kiểm tra bản in trước khi in lại."
            }
        }
    }

    public let ip: String
    public let port: UInt16

    private var connection: NWConnection?
    private(set) public var state: State = .idle

    // Serial queue to ensure thread-safety for this connection
    private let queue: DispatchQueue

    /// Một job đang chờ gửi. Giữ kèm completion để trả kết quả THẬT về Dart thay vì
    /// báo thành công lạc quan rồi im lặng khi lỗi.
    private struct Job {
        let data: Data
        let completion: ((Bool, Error?) -> Void)?
        /// Số lần đã thử gửi lại job này.
        var attempts: Int = 0
    }

    // write queue
    private var writeQueue: [Job] = []
    private var isWriting: Bool = false

    /// true khi chưa gửi job nào trên socket hiện tại — dùng để chèn `ESC @` xóa bộ đệm
    /// còn sót của lần in trước (xem `flushQueue`).
    private var isFirstJobOnSocket: Bool = true

    /// Job đã đẩy xuống TCP và đang chờ xác nhận máy in không đóng kết nối.
    /// Nếu máy in reset trong lúc chờ thì job này được coi là CHƯA in và đem retry.
    private var pendingConfirmJob: Job?

    /// Thời gian chờ sau khi đẩy xong dữ liệu để phát hiện máy in reset kết nối (do thiết
    /// bị khác đang giữ kênh in). Máy in từ chối gần như tức thì nên 400ms là đủ.
    private let acceptConfirmDelay: TimeInterval = 0.4

    // connection timeout
    private let connectionTimeout: TimeInterval = 4

    // MARK: - Retry có giới hạn + backoff
    // TRƯỚC ĐÂY: send lỗi → đẩy data về đầu queue → connect() → lỗi nữa → lặp VÔ HẠN,
    // không giới hạn số lần, không giãn nhịp. Khi 2 điện thoại tranh socket 9100 thì cả
    // hai cùng rơi vào vòng này và liên tục đập vào máy in, càng làm nhau khó kết nối.
    private let maxAttempts = 4
    /// Giãn dần: 0.4s, 0.8s, 1.6s. Cho thiết bị đang giữ socket kịp in xong và nhả ra.
    private let retryBaseDelay: TimeInterval = 0.4

    // MARK: - Nhả socket sau khi in
    // Máy in nhiệt LAN hầu hết chỉ nhận 1 kết nối TCP trên port 9100. Giữ socket thường
    // trực làm mọi thiết bị khác không kết nối được. Nhả ngay khi hàng đợi rỗng biến
    // "tranh socket" thành "xếp hàng ngắn" — mô hình các POS nhiều thiết bị vẫn dùng.
    /// Chờ một nhịp ngắn trước khi đóng: nếu có job kế tiếp (in liên tiếp nhiều đơn)
    /// thì tái dùng socket đang mở thay vì đóng/mở lại liên tục.
    private let idleCloseDelay: TimeInterval = 0.6
    private var idleCloseWork: DispatchWorkItem?
    /// true = tự đóng socket khi in xong. Tắt đi nếu muốn giữ kết nối độc quyền.
    public var releaseSocketWhenIdle: Bool = true

    // Callbacks
    public var onConnected: (() -> Void)?
    public var onDisconnected: ((_ error: Error?) -> Void)?

    // Hàng đợi completion cho connect(). Mọi caller gọi connect() trong khi đang
    // .connecting đều được thêm vào đây và fire CHÍNH XÁC 1 lần khi connected/failed/timeout.
    // Tránh lỗi: gọi connect() nhiều lần làm callback bị ghi đè và caller treo vô hạn.
    private var connectCompletions: [(Bool) -> Void] = []

    /// Lỗi của lần connect gần nhất, dùng để phân loại busy vs unreachable.
    private var lastConnectError: Error?

    // MARK: - Initialization
    public init(ip: String, port: UInt16 = 9100, queueLabel: String? = nil) {
        self.ip = ip
        self.port = port
        let label = queueLabel ?? "lan.printer." + ip
        self.queue = DispatchQueue(label: label)
    }

    deinit {
        idleCloseWork?.cancel()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
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
            // Sắp mở lại socket → hủy lệnh đóng do rảnh đang chờ.
            self.cancelIdleClose()

            if self.state == .connected {
                if let c = completion { DispatchQueue.main.async { c(true) } }
                return
            }
            if let c = completion { self.connectCompletions.append(c) }
            // Đang connect dở → chỉ xếp hàng completion, không khởi tạo lại.
            if self.state == .connecting { return }
            self.state = .connecting
            self.lastConnectError = nil
            print("[LANPrinterConnection] 🔗 Connecting to \(self.ip):\(self.port)...")

            let host = NWEndpoint.Host(self.ip)
            let nwPort = NWEndpoint.Port(rawValue: self.port) ?? .init(integerLiteral: 9100)
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            let connection = NWConnection(host: host, port: nwPort, using: params)
            self.connection = connection

            connection.stateUpdateHandler = { [weak self] newState in
                guard let self = self else { return }
                // Bỏ qua callback của socket đã bị thay thế — tránh một socket cũ
                // đang tắt ghi đè state của socket mới vừa mở.
                guard connection === self.connection else { return }
                switch newState {
                case .ready:
                    self.state = .connected
                    // Socket mới → job kế tiếp phải chèn `ESC @` để xóa bộ đệm còn sót.
                    self.isFirstJobOnSocket = true
                    print("[LANPrinterConnection] ✅ Connected to \(self.ip)")
                    self.onConnected?()
                    self.fireConnectCompletions(true)
                    self.flushQueue()
                case .failed(let error):
                    self.state = .failed
                    self.lastConnectError = error
                    // Không còn job nào chờ → đây là socket của một job ĐÃ GỬI XONG đang
                    // được máy in đóng lại (RAW/JetDirect thường reset thay vì FIN sạch sau
                    // khi nhận hết job). Đó là hành vi BÌNH THƯỜNG, không phải lỗi in; log
                    // "❌ Connection failed" ở đây làm tưởng lần in vừa rồi thất bại.
                    // Job vừa đẩy xuống TCP nhưng máy in ĐÓNG NGAY → nó chưa được in (thiết
                    // bị khác đang giữ kênh in). Đưa lại đầu hàng đợi để retry theo backoff,
                    // thay vì báo thành công giả và mất job im lặng.
                    if let unconfirmed = self.pendingConfirmJob {
                        self.pendingConfirmJob = nil
                        self.writeQueue.insert(unconfirmed, at: 0)
                        print("[LANPrinterConnection] ↩️ Máy in \(self.ip) đóng ngay sau khi nhận — job chưa in, sẽ thử lại")
                    }
                    let hasPendingWork = !self.writeQueue.isEmpty || self.isWriting
                    if hasPendingWork {
                        print("[LANPrinterConnection] ❌ Connection failed to \(self.ip): \(error)")
                        self.onDisconnected?(error)
                    } else {
                        print("[LANPrinterConnection] ⏹️ Máy in \(self.ip) đã đóng kết nối sau khi nhận xong job")
                    }
                    self.teardownConnection()
                    self.fireConnectCompletions(false)
                    // Máy in bận/tắt → thử lại theo backoff thay vì bỏ job im lặng.
                    // (scheduleRetryOrFail tự return ngay nếu hàng đợi rỗng.)
                    self.scheduleRetryOrFail(error: error)
                case .cancelled:
                    self.state = .disconnected
                    print("[LANPrinterConnection] ⏹️ Disconnected from \(self.ip)")
                    self.onDisconnected?(nil)
                    self.connection = nil
                    self.fireConnectCompletions(false)
                    // Socket đóng do rảnh là bình thường; chỉ báo lỗi khi còn job dở.
                    self.scheduleRetryOrFail(error: nil)
                default:
                    break
                }
            }

            connection.start(queue: self.queue)

            // implement a simple connect timeout
            self.queue.asyncAfter(deadline: .now() + self.connectionTimeout) { [weak self] in
                guard let self = self else { return }
                guard connection === self.connection, self.state == .connecting else { return }
                print("[LANPrinterConnection] ⏱️ Connection timeout to \(self.ip)")
                let timeoutError = NSError(
                    domain: "LANPrinterConnection", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Connection timeout"]
                )
                self.state = .failed
                self.lastConnectError = timeoutError
                self.onDisconnected?(timeoutError)
                self.teardownConnection()
                self.fireConnectCompletions(false)
                self.scheduleRetryOrFail(error: timeoutError)
            }
        }
    }

    /// Đóng socket hiện tại và bỏ tham chiếu. Phải gọi từ trong self.queue.
    private func teardownConnection() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
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
            self.cancelIdleClose()
            self.teardownConnection()
            self.state = .disconnected
            // Job chưa gửi bị hủy theo yêu cầu người dùng → trả lỗi cho caller đang chờ.
            if let unconfirmed = self.pendingConfirmJob {
                self.pendingConfirmJob = nil
                self.writeQueue.insert(unconfirmed, at: 0)
            }
            let dropped = self.writeQueue
            self.writeQueue.removeAll()
            self.isWriting = false
            if !dropped.isEmpty {
                DispatchQueue.main.async {
                    for job in dropped {
                        job.completion?(false, SendError(kind: .unreachable, underlying: nil))
                    }
                }
            }
        }
    }

    // MARK: - Sending Data
    public func send(data: Data, completion: ((_ success: Bool, _ error: Error?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            print("[LANPrinterConnection] 📤 Queueing \(data.count) bytes to \(self.ip)")
            self.cancelIdleClose()
            self.writeQueue.append(Job(data: data, completion: completion))
            if self.state == .connected {
                self.flushQueue()
            } else if self.state != .connecting {
                // Socket đã nhả sau lần in trước (hoặc chưa từng mở) → mở lại để gửi.
                self.connect()
            }
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
        guard !writeQueue.isEmpty else {
            // In xong hết → nhả socket cho thiết bị khác dùng.
            scheduleIdleCloseIfNeeded()
            return
        }

        isWriting = true
        var job = writeQueue.removeFirst()
        job.attempts += 1

        // Job ĐẦU TIÊN trên một socket vừa mở phải bắt đầu bằng `ESC @` (initialize).
        //
        // Lần in trước có thể đã bị cắt giữa dòng (máy in reset kết nối, hoặc thiết bị khác
        // ngắt), để lại BYTE DỞ trong bộ đệm máy in — thường là phần đuôi của một lệnh
        // `GS v 0` chưa đủ số byte đã khai báo. Máy in vẫn đang đợi cho đủ, nên nó ăn luôn
        // phần đầu của bill mới và in ra ký tự rác; các bill sau đó lại bình thường vì bộ
        // đệm đã sạch. Đúng triệu chứng "lần đầu kết nối lại in linh tinh, sau đó in bình
        // thường". `ESC @` hủy mọi lệnh dở và đưa máy in về trạng thái mặc định.
        let data: Data
        if isFirstJobOnSocket {
            isFirstJobOnSocket = false
            var prefixed = Data([0x1B, 0x40]) // ESC @
            prefixed.append(job.data)
            data = prefixed
            print("[LANPrinterConnection] 🧹 Thêm ESC @ đầu job để xóa bộ đệm còn sót của \(ip)")
        } else {
            data = job.data
        }
        print("[LANPrinterConnection] 📨 Sending \(data.count) bytes to \(ip) (lần \(job.attempts))...")

        self.connection?.send(content: data, completion: .contentProcessed({ [weak self] error in
            guard let self = self else { return }
            self.isWriting = false
            if let err = error {
                print("[LANPrinterConnection] ❌ Send error: \(err)")
                self.teardownConnection()
                self.state = .failed
                self.onDisconnected?(err)

                // KHÔNG gửi lại job đã bắt đầu truyền. `contentProcessed` báo lỗi sau khi
                // dữ liệu đã được đẩy xuống tầng TCP, nên máy in CÓ THỂ đã nhận và in một
                // phần. Gửi lại toàn bộ sẽ nối nửa hóa đơn cũ với hóa đơn mới → in ra rác,
                // đúng họ lỗi với bug BLE. An toàn hơn là báo lỗi để người dùng tự quyết.
                DispatchQueue.main.async {
                    job.completion?(false, SendError(kind: .partiallySent, underlying: err))
                }
                // Các job CHƯA gửi byte nào vẫn thử lại được sau khi kết nối lại.
                if !self.writeQueue.isEmpty { self.connect() }
            } else {
                // `contentProcessed` KHÔNG có lỗi chỉ nghĩa là dữ liệu đã xuống tầng TCP của
                // iOS — KHÔNG phải máy in đã nhận và in.
                //
                // Máy in này ACCEPT nhiều socket cùng lúc nhưng chỉ MỘT socket được in; các
                // socket còn lại bị nó đóng ngay khi có byte tới (đã kiểm chứng: accept 3/3
                // socket, gửi thì "Broken pipe"). Khi thiết bị khác đang giữ kênh in, iOS vẫn
                // thấy ✅ Connected + ✅ Finished sending nhưng GIẤY KHÔNG RA GÌ. Báo
                // success ở đây là BÁO THÀNH CÔNG GIẢ và job bị mất im lặng.
                //
                // Vì vậy chờ một nhịp ngắn: nếu máy in reset kết nối trong khoảng này thì
                // coi như job CHƯA vào được máy in và cho retry (backoff sẽ đợi thiết bị kia
                // in xong). Còn kết nối vẫn sống thì mới coi là gửi thành công.
                print("[LANPrinterConnection] 📦 Đã đẩy xong xuống TCP, chờ xác nhận máy in nhận...")
                self.pendingConfirmJob = job
                self.queue.asyncAfter(deadline: .now() + self.acceptConfirmDelay) { [weak self] in
                    guard let self = self else { return }
                    guard let confirming = self.pendingConfirmJob else { return } // đã bị .failed xử lý
                    self.pendingConfirmJob = nil
                    guard self.state == .connected else { return }
                    print("[LANPrinterConnection] ✅ Máy in \(self.ip) đã nhận job")
                    DispatchQueue.main.async { confirming.completion?(true, nil) }
                    self.flushQueue()
                }
            }
        }))
    }

    // MARK: - Retry
    /// Kết nối thất bại: thử lại job đầu hàng đợi theo backoff, hoặc bỏ và báo lỗi
    /// khi đã quá số lần. Phải gọi từ trong self.queue.
    private func scheduleRetryOrFail(error: Error?) {
        guard !writeQueue.isEmpty else { return }
        let kind = Self.classify(error ?? lastConnectError)
        let attempts = writeQueue[0].attempts

        guard attempts < maxAttempts else {
            let failed = writeQueue.removeFirst()
            print("[LANPrinterConnection] 🚫 Bỏ job tới \(ip) sau \(attempts) lần thử: \(kind.rawValue)")
            DispatchQueue.main.async {
                failed.completion?(false, SendError(kind: kind, underlying: error))
            }
            // Còn job khác thì tiếp tục thử.
            if !writeQueue.isEmpty { connect() }
            return
        }

        // Backoff tăng dần theo số lần đã thử — nhường socket cho thiết bị đang in.
        let delay = retryBaseDelay * pow(2.0, Double(max(0, attempts - 1)))
        writeQueue[0].attempts = attempts + 1
        print("[LANPrinterConnection] 🔄 Thử lại \(ip) sau \(String(format: "%.1f", delay))s (lần \(attempts + 1)/\(maxAttempts), \(kind.rawValue))")
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.writeQueue.isEmpty else { return }
            guard self.state != .connected, self.state != .connecting else { return }
            self.connect()
        }
    }

    /// Phân loại lỗi kết nối. `.refused`/timeout trên port 9100 gần như luôn là do thiết
    /// bị khác đang giữ socket, chứ không phải máy in offline — báo sai làm người dùng
    /// tưởng mất mạng hoặc máy in hỏng.
    private static func classify(_ error: Error?) -> FailureKind {
        guard let error = error else { return .busy }
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let code):
                switch code {
                case .ECONNREFUSED, .ECONNRESET, .ETIMEDOUT, .EBUSY, .EADDRINUSE:
                    return .busy
                case .EHOSTDOWN, .EHOSTUNREACH, .ENETDOWN, .ENETUNREACH:
                    return .unreachable
                default:
                    return .unreachable
                }
            case .dns:
                return .unreachable
            default:
                return .unreachable
            }
        }
        // Timeout tự đặt (code -1): máy in có thể đang bận in cho thiết bị khác.
        let ns = error as NSError
        if ns.domain == "LANPrinterConnection" && ns.code == -1 { return .busy }
        return .unreachable
    }

    // MARK: - Idle close
    /// Hẹn đóng socket khi không còn job. Phải gọi từ trong self.queue.
    private func scheduleIdleCloseIfNeeded() {
        guard releaseSocketWhenIdle, state == .connected else { return }
        idleCloseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.writeQueue.isEmpty, !self.isWriting, self.state == .connected else { return }
            print("[LANPrinterConnection] 💤 Nhả socket \(self.ip) để thiết bị khác dùng")
            // Đóng NHẸ NHÀNG, KHÔNG dùng cancel(). `contentProcessed` chỉ báo dữ liệu đã
            // được đẩy xuống tầng TCP, KHÔNG phải máy in đã nhận/in xong. Với đơn dài
            // (~85KB) còn hàng chục KB nằm trong buffer gửi của iOS và buffer nhận của máy
            // in. `cancel()` đóng CỨNG: huỷ luôn phần chưa flush và gửi RST -> máy in đang
            // đọc dở bị đứt giữa dòng, báo "Connection reset by peer" và BẢN IN CÓ THỂ BỊ
            // CẮT CỤT ĐOẠN CUỐI.
            //
            // `send(content: nil, isComplete: true)` gửi FIN sau khi toàn bộ dữ liệu đã
            // flush xong: máy in đọc hết những gì đã gửi, thấy EOF rồi tự đóng phía nó.
            // Đây cũng là cách máy in RAW/JetDirect nhận biết hết một job.
            self.state = .disconnected
            self.connection?.send(content: nil, contentContext: .finalMessage, isComplete: true,
                                  completion: .contentProcessed({ [weak self] _ in
                guard let self = self else { return }
                // FIN đã đi; giờ mới thực sự dọn socket.
                self.queue.async { self.finishIdleClose() }
            }))
        }
        idleCloseWork = work
        queue.asyncAfter(deadline: .now() + idleCloseDelay, execute: work)
    }

    /// Dọn socket sau khi FIN đã được gửi xong. Phải gọi từ trong self.queue.
    private func finishIdleClose() {
        // Có job mới xen vào trong lúc chờ FIN flush → giữ socket lại, đừng đóng.
        guard writeQueue.isEmpty, !isWriting else { return }
        teardownConnection()
        state = .disconnected
    }

    private func cancelIdleClose() {
        idleCloseWork?.cancel()
        idleCloseWork = nil
    }
}
