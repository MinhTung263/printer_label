import Foundation

// LANPrinterManager: singleton manager maintaining multiple LANPrinterConnection instances keyed by IP.
// Exposes connect/disconnect/send APIs used by Flutter plugin.

public final class LANPrinterManager {
    public static let shared = LANPrinterManager()

    // map IP -> connection
    private var connections: [String: LANPrinterConnection] = [:]

    // serial access queue for manager state
    private let queue = DispatchQueue(label: "lan.printer.manager")

    private init() {}

    // Connect to a printer by ip. If exists, will reuse existing connection.
    // connect() của LANPrinterConnection tự quản lý hàng đợi completion → an toàn khi
    // gọi nhiều lần cho cùng IP; completion luôn fire đúng 1 lần với kết quả thật.
    public func connect(ip: String, port: UInt16 = 9100, completion: ((_ success: Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let conn: LANPrinterConnection
            if let existing = self.connections[ip] {
                conn = existing
            } else {
                conn = LANPrinterConnection(ip: ip, port: port)
                self.connections[ip] = conn
            }
            conn.connect { [weak self] success in
                // Connect thất bại → bỏ connection để lần sau khởi tạo sạch.
                if !success {
                    self?.queue.async {
                        self?.connections[ip]?.disconnect()
                        self?.connections.removeValue(forKey: ip)
                    }
                }
                completion?(success)
            }
        }
    }

    public func disconnect(ip: String, completion: ((_ success: Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let conn = self.connections[ip] {
                conn.disconnect()
                self.connections.removeValue(forKey: ip)
                DispatchQueue.main.async { completion?(true) }
            } else {
                DispatchQueue.main.async { completion?(false) }
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
        }
    }

    public func send(data: Data, to ip: String, completion: ((_ success: Bool, _ error: Error?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            print("[LANPrinterManager] 📤 send() called for IP: \(ip), data size: \(data.count)")
            if let conn = self.connections[ip] {
                print("[LANPrinterManager] Found connection to \(ip), state: \(conn.state)")
                if conn.state != .connected {
                    // try to connect first, then enqueue
                    print("[LANPrinterManager] Connection not ready, attempting connect...")
                    conn.connect()
                    conn.send(data: data)
                    DispatchQueue.main.async { completion?(false, NSError(domain: "LANPrinterManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Connection not ready; enqueued"])) }
                } else {
                    print("[LANPrinterManager] Connection ready, sending now...")
                    conn.send(data: data) { success, error in
                        DispatchQueue.main.async { completion?(success, error) }
                    }
                }
            } else {
                print("[LANPrinterManager] No existing connection to \(ip), creating new...")
                // create connection and connect+enqueue
                let conn = LANPrinterConnection(ip: ip)
                conn.onConnected = { [weak conn] in
                    print("[LANPrinterManager] New connection to \(ip) connected, sending data...")
                    conn?.send(data: data)
                }
                conn.onDisconnected = { error in
                    print("[LANPrinterManager] Connection to \(ip) disconnected: \(error?.localizedDescription ?? "no error")")
                    DispatchQueue.main.async { completion?(false, error) }
                }
                self.connections[ip] = conn
                conn.connect()
                conn.send(data: data)
                DispatchQueue.main.async { completion?(false, NSError(domain: "LANPrinterManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Connection created and data enqueued"])) }
            }
        }
    }

    public func isConnected(ip: String) -> Bool {
        var connected = false
        queue.sync {
            if let conn = connections[ip] {
                connected = conn.state == .connected
            }
        }
        return connected
    }

    public func getConnectedPrinters() -> [String] {
        var list: [String] = []
        queue.sync {
            for (ip, conn) in connections where conn.state == .connected {
                list.append(ip)
            }
        }
        return list
    }
}
