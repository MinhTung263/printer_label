import Foundation

// LANPrinterManager: singleton manager maintaining multiple LANPrinterConnection instances keyed by IP.
// Exposes connect/disconnect/send APIs used by Flutter plugin.

public final class LANPrinterManager {
    public static let shared = LANPrinterManager()

    // map IP -> connection
    private var connections: [String: LANPrinterConnection] = [:]

    // MARK: - Máy in đã ghép nối (registered) vs socket đang mở (connected)
    // Socket được NHẢ sau khi in xong để nhiều thiết bị dùng chung được máy in LAN
    // (máy in nhiệt thường chỉ nhận 1 kết nối trên port 9100). Vì vậy "không có socket"
    // KHÔNG còn nghĩa là "máy in offline" — nếu lấy trạng thái socket làm câu trả lời cho
    // checkConnect thì máy in vừa in xong sẽ hiện offline và Dart sẽ chặn không cho in.
    // Ta ghi nhớ những IP đã connect thành công và coi chúng là còn ghép nối cho tới khi
    // người dùng chủ động disconnect.
    private var registeredPrinters: Set<String> = []

    // serial access queue for manager state
    private let queue = DispatchQueue(label: "lan.printer.manager")

    private init() {}

    // Connect to a printer by ip. If exists, will reuse existing connection.
    // connect() của LANPrinterConnection tự quản lý hàng đợi completion → an toàn khi
    // gọi nhiều lần cho cùng IP; completion luôn fire đúng 1 lần với kết quả thật.
    public func connect(ip: String, port: UInt16 = 9100, completion: ((_ success: Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let conn = self.connectionFor(ip: ip, port: port)
            conn.connect { [weak self] success in
                guard let self = self else { return }
                self.queue.async {
                    if success {
                        // Ghép nối thành công → ghi nhớ, kể cả khi socket bị nhả sau đó.
                        self.registeredPrinters.insert(ip)
                    } else {
                        // Connect thất bại → bỏ connection để lần sau khởi tạo sạch.
                        self.connections[ip]?.disconnect()
                        self.connections.removeValue(forKey: ip)
                        self.registeredPrinters.remove(ip)
                    }
                    completion?(success)
                }
            }
        }
    }

    /// Lấy connection sẵn có hoặc tạo mới. Phải gọi từ trong queue.
    private func connectionFor(ip: String, port: UInt16 = 9100) -> LANPrinterConnection {
        if let existing = connections[ip] { return existing }
        let conn = LANPrinterConnection(ip: ip, port: port)
        // Không tới được máy in -> thôi coi IP này là "đã ghép nối", để checkConnect báo
        // đúng và app có cơ hội tìm lại máy (VD máy in đổi IP) thay vì cứ in vào IP cũ.
        conn.onUnreachable = { [weak self] _ in
            self?.queue.async { _ = self?.registeredPrinters.remove(ip) }
        }
        connections[ip] = conn
        return conn
    }

    public func disconnect(ip: String, completion: ((_ success: Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let wasRegistered = self.registeredPrinters.remove(ip) != nil
            if let conn = self.connections[ip] {
                conn.disconnect()
                self.connections.removeValue(forKey: ip)
                DispatchQueue.main.async { completion?(true) }
            } else {
                DispatchQueue.main.async { completion?(wasRegistered) }
            }
        }
    }

    public func disconnectAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            for (_, conn) in self.connections {
                conn.disconnect()
            }
            self.connections.removeAll()
            self.registeredPrinters.removeAll()
        }
    }

    public func send(data: Data, to ip: String, checkPaper: Bool = false,
                     completion: ((_ success: Bool, _ error: Error?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            print("[LANPrinterManager] 📤 send() called for IP: \(ip), data size: \(data.count)")
            // Socket có thể đã được nhả sau lần in trước — send() của connection tự mở lại
            // khi cần, đồng thời tự retry theo backoff nếu máy in đang bận vì thiết bị khác.
            // Nhờ vậy ở đây chỉ cần xếp job và chờ kết quả THẬT.
            let conn = self.connectionFor(ip: ip)
            self.registeredPrinters.insert(ip)
            conn.send(data: data, checkPaper: checkPaper) { success, error in
                if !success {
                    print("[LANPrinterManager] ❌ send tới \(ip) thất bại: \(error?.localizedDescription ?? "unknown")")
                }
                DispatchQueue.main.async { completion?(success, error) }
            }
        }
    }

    /// true khi máy in [ip] đang được ghép nối (dù socket có thể đã nhả để nhường thiết
    /// bị khác). Dùng cho checkConnect: phản ánh "có in được không", không phải "socket
    /// có đang mở không".
    public func isConnected(ip: String) -> Bool {
        var connected = false
        queue.sync {
            connected = registeredPrinters.contains(ip) || connections[ip]?.state == .connected
        }
        return connected
    }

    /// true khi socket tới [ip] đang thực sự mở. Dùng để chẩn đoán, không dùng cho
    /// checkConnect (xem `isConnected`).
    public func hasLiveSocket(ip: String) -> Bool {
        var live = false
        queue.sync { live = connections[ip]?.state == .connected }
        return live
    }

    public func getConnectedPrinters() -> [String] {
        var list: [String] = []
        queue.sync {
            // Gồm cả máy in đã ghép nối nhưng đang nhả socket, để việc in không deviceId
            // vẫn tìm được máy in sau khi socket tự đóng.
            var set = registeredPrinters
            for (ip, conn) in connections where conn.state == .connected {
                set.insert(ip)
            }
            list = Array(set)
        }
        return list
    }
}
