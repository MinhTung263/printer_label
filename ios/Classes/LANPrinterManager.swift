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
    public func connect(ip: String, port: UInt16 = 9100, autoReconnect: Bool = true, completion: ((_ success: Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let conn = self.connections[ip] {
                // already exists
                if conn.state == .connected {
                    DispatchQueue.main.async { completion?(true) }
                    return
                }
                // exists but not connected: re-wire the connect-result callbacks and retry
                self.attachConnectResult(to: conn, ip: ip, completion: completion)
                conn.connect()
            } else {
                let conn = LANPrinterConnection(ip: ip, port: port, autoReconnect: autoReconnect)
                self.connections[ip] = conn
                self.attachConnectResult(to: conn, ip: ip, completion: completion)
                conn.connect()
            }
        }
    }

    // Wire onConnected/onDisconnected so the connect result is reported back to the
    // caller exactly once. Without this, a failed/timed-out connection never calls
    // completion and the Flutter side hangs with no error.
    private func attachConnectResult(to conn: LANPrinterConnection, ip: String, completion: ((_ success: Bool) -> Void)?) {
        // Guard against double-firing: success and failure callbacks race, and
        // onDisconnected can fire again on later background reconnect attempts.
        var didReport = false
        let report: (Bool) -> Void = { [weak self, weak conn] success in
            guard !didReport else { return }
            didReport = true
            // Detach the one-shot connect callbacks; keep the connection around so
            // subsequent send()/state inspection still works.
            conn?.onConnected = nil
            conn?.onDisconnected = nil
            if !success {
                // Drop the failed connection so a later connect() starts cleanly.
                // Mutate the connections map on the manager's serial queue.
                self?.queue.async {
                    self?.connections[ip]?.disconnect()
                    self?.connections.removeValue(forKey: ip)
                }
            }
            DispatchQueue.main.async { completion?(success) }
        }

        conn.onConnected = { report(true) }
        conn.onDisconnected = { _ in report(false) }
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
