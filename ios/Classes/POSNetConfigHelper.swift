import Foundation

/// Helper xử lý cấu hình và quét mạng qua giao thức UDP Broadcast (XP0001SAVE / XP0001FIND)
/// cho các dòng máy in Xprinter, POS Network Printers trên iOS.
class POSNetConfigHelper {

    // MARK: - Parse Helpers

    /// Chuyển chuỗi MAC (dạng "00:11:22:33:44:55", "00-11-22-33-44-55", hoặc "001122334455") thành 6 bytes.
    static func parseMac(_ macStr: String) -> [UInt8] {
        let clean = macStr.replacingOccurrences(of: ":", with: "")
                          .replacingOccurrences(of: "-", with: "")
                          .replacingOccurrences(of: " ", with: "")
        if clean.count == 12 {
            var bytes = [UInt8]()
            var index = clean.startIndex
            for _ in 0..<6 {
                let nextIndex = clean.index(index, offsetBy: 2)
                let byteStr = clean[index..<nextIndex]
                if let byte = UInt8(byteStr, radix: 16) {
                    bytes.append(byte)
                } else {
                    bytes.append(0)
                }
                index = nextIndex
            }
            return bytes
        }
        let parts = macStr.components(separatedBy: CharacterSet(charactersIn: ":- "))
                          .filter { !$0.isEmpty }
        if parts.count == 6 {
            return parts.map { UInt8($0.trimmingCharacters(in: .whitespaces), radix: 16) ?? 0 }
        }
        return [UInt8](repeating: 0, count: 6)
    }

    /// Chuyển chuỗi IPv4 (dạng "192.168.1.100") thành 4 bytes.
    static func parseIp(_ ipStr: String) -> [UInt8] {
        let parts = ipStr.components(separatedBy: ".")
        if parts.count == 4 {
            return parts.map { UInt8($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        }
        return [UInt8](repeating: 0, count: 4)
    }

    // MARK: - Packet Builders

    /// Xây dựng gói tin UDP cấu hình mạng XP0001SAVE (34 bytes).
    /// Khớp 100% với POSWIFIManager (iOS SDK) và PosUdpNet (Android AAR).
    ///
    /// Layout:
    /// - 0..9   (10 bytes): "XP0001SAVE"
    /// - 10..15  (6 bytes): MAC address
    /// - 16..17  (2 bytes): Length / Magic 0x0022 (34 in little-endian = 0x22, 0x00)
    /// - 18..21  (4 bytes): New IP
    /// - 22..25  (4 bytes): Subnet Mask
    /// - 26..29  (4 bytes): Gateway
    /// - 30..31  (2 bytes): Port 9100 in little-endian (0x8C, 0x23)
    /// - 32      (1 byte) : DHCP (0x01 = On, 0x00 = Off)
    /// - 33      (1 byte) : Padding 0x00 (đủ 34 bytes)
    static func buildUdpSavePacket(
        mac: String,
        ip: String,
        mask: String,
        gateway: String,
        dhcp: Bool
    ) -> [UInt8]? {
        guard let header = "XP0001SAVE".data(using: .ascii) else { return nil }
        var packet = [UInt8](header) // 10 bytes

        let macBytes = parseMac(mac)
        packet.append(contentsOf: macBytes) // 6 bytes

        // Length: 0x0022 (34 in little-endian)
        packet.append(contentsOf: [0x22, 0x00])

        let ipBytes = parseIp(ip)
        packet.append(contentsOf: ipBytes) // 4 bytes

        let effectiveMask = mask.isEmpty ? "255.255.255.0" : mask
        let maskBytes = parseIp(effectiveMask)
        packet.append(contentsOf: maskBytes) // 4 bytes

        let gwBytes = gateway.isEmpty ? [UInt8](repeating: 0, count: 4) : parseIp(gateway)
        packet.append(contentsOf: gwBytes) // 4 bytes

        // Port 9100 in little-endian (0x238C = 0x8C, 0x23)
        packet.append(contentsOf: [0x8C, 0x23])

        // DHCP flag
        packet.append(dhcp ? 0x01 : 0x00)

        // Padding to 34 bytes
        if packet.count < 34 {
            packet.append(0x00)
        }

        return packet
    }

    // MARK: - Network Interfaces

    /// Lấy danh sách địa chỉ Broadcast của các network interface đang hoạt động (ví dụ: en0).
    static func getBroadcastAddresses() -> [String] {
        var addresses = [String]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return addresses }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard let addrPtr = ptr.pointee.ifa_addr else { continue }
            let addr = addrPtr.pointee

            if (flags & (IFF_UP | IFF_RUNNING | IFF_BROADCAST)) == (IFF_UP | IFF_RUNNING | IFF_BROADCAST) &&
               (flags & IFF_LOOPBACK) == 0 {
                if addr.sa_family == UInt8(AF_INET) {
                    if let dstaddr = ptr.pointee.ifa_dstaddr {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(dstaddr, socklen_t(dstaddr.pointee.sa_len),
                                       &hostname, socklen_t(hostname.count),
                                       nil, 0, NI_NUMERICHOST) == 0 {
                            let ip = String(cString: hostname)
                            if !ip.isEmpty && ip != "0.0.0.0" {
                                addresses.append(ip)
                            }
                        }
                    }
                }
            }
        }
        return addresses
    }

    // MARK: - UDP Send Net Config

    /// Gửi gói tin cấu hình IP qua UDP Broadcast tới cổng 9000.
    /// Hoạt động với tất cả máy in POS LAN / Xprinter ngay cả khi khác dải mạng Subnet.
    static func sendUdpNetConfig(
        mac: String,
        ip: String,
        mask: String,
        gateway: String,
        dhcp: Bool,
        currentIp: String? = nil,
        port: UInt16 = 9000
    ) -> Bool {
        guard let packet = buildUdpSavePacket(mac: mac, ip: ip, mask: mask, gateway: gateway, dhcp: dhcp) else {
            print("[POSNetConfig] ❌ Không thể tạo gói tin UDP cấu hình mạng")
            return false
        }

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else {
            print("[POSNetConfig] ❌ Lỗi tạo UDP socket: errno=\(errno)")
            return false
        }
        defer { close(sock) }

        var broadcastEnable: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var destinations: Set<String> = ["255.255.255.255"]
        for bcast in getBroadcastAddresses() {
            destinations.insert(bcast)
        }
        if let cip = currentIp, !cip.isEmpty {
            destinations.insert(cip)
        }

        var anySent = false
        for dest in destinations {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            if inet_pton(AF_INET, dest, &addr.sin_addr) == 1 {
                for _ in 0..<3 {
                    let sent = withUnsafePointer(to: &addr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                            packet.withUnsafeBufferPointer { bufPtr in
                                sendto(sock, bufPtr.baseAddress, packet.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                    if sent > 0 {
                        anySent = true
                    }
                    usleep(30000) // 30ms giữa các lần gửi
                }
            }
        }

        print("[POSNetConfig] 📤 Đã gửi UDP net config (mac=\(mac), ip=\(ip), mask=\(mask), gw=\(gateway), dhcp=\(dhcp)) tới \(destinations) -> result=\(anySent)")
        return anySent
    }

    // MARK: - UDP Scan Devices

    /// Quét các máy in POS / Xprinter trong mạng LAN bằng gói tin XP0001FIND qua UDP Broadcast cổng 9000.
    static func scanUdpPrinters(
        timeout: TimeInterval = 1.0,
        port: UInt16 = 9000,
        completion: @escaping ([[String: Any]]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard sock >= 0 else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            defer { close(sock) }

            var reuse: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

            var broadcast: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

            var tv = timeval(tv_sec: 0, tv_usec: 200000) // 200ms recv timeout per loop
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var bindAddr = sockaddr_in()
            bindAddr.sin_family = sa_family_t(AF_INET)
            bindAddr.sin_port = port.bigEndian
            bindAddr.sin_addr.s_addr = INADDR_ANY.bigEndian

            let bindRes = withUnsafePointer(to: &bindAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindRes < 0 {
                var bindAny = sockaddr_in()
                bindAny.sin_family = sa_family_t(AF_INET)
                bindAny.sin_port = 0
                bindAny.sin_addr.s_addr = INADDR_ANY.bigEndian
                _ = withUnsafePointer(to: &bindAny) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            guard let findData = "XP0001FIND".data(using: .ascii) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let findBytes = [UInt8](findData)

            var destinations: Set<String> = ["255.255.255.255"]
            for bcast in getBroadcastAddresses() {
                destinations.insert(bcast)
            }

            for dest in destinations {
                var targetAddr = sockaddr_in()
                targetAddr.sin_family = sa_family_t(AF_INET)
                targetAddr.sin_port = port.bigEndian
                if inet_pton(AF_INET, dest, &targetAddr.sin_addr) == 1 {
                    _ = withUnsafePointer(to: &targetAddr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            findBytes.withUnsafeBufferPointer { buf in
                                sendto(sock, buf.baseAddress, findBytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                }
            }

            var discovered: [[String: Any]] = []
            var seenMacs = Set<String>()
            let startTime = Date()
            var recvBuf = [UInt8](repeating: 0, count: 512)

            while Date().timeIntervalSince(startTime) < timeout {
                var srcAddr = sockaddr_in()
                var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                let count = withUnsafeMutablePointer(to: &srcAddr) { srcPtr in
                    srcPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(sock, &recvBuf, recvBuf.count, 0, sa, &srcLen)
                    }
                }

                if count >= 33 {
                    let headerString = String(bytes: recvBuf[0..<min(11, count)], encoding: .ascii) ?? ""
                    if headerString.contains("XP0001FOUND") {
                        let macBytes = Array(recvBuf[11..<min(17, count)])
                        let macStr = macBytes.map { String(format: "%02X", $0) }.joined(separator: ":")

                        let ipBytes = Array(recvBuf[19..<min(23, count)])
                        let ipStr = ipBytes.map { "\($0)" }.joined(separator: ".")

                        let maskBytes = count >= 27 ? Array(recvBuf[23..<27]) : []
                        let maskStr = maskBytes.isEmpty ? "" : maskBytes.map { "\($0)" }.joined(separator: ".")

                        let gwBytes = count >= 31 ? Array(recvBuf[27..<31]) : []
                        let gwStr = gwBytes.isEmpty ? "" : gwBytes.map { "\($0)" }.joined(separator: ".")

                        let dhcp = count >= 34 ? (recvBuf[33] == 1) : false

                        if !macStr.isEmpty && !ipStr.isEmpty && !seenMacs.contains(macStr.uppercased()) {
                            seenMacs.insert(macStr.uppercased())
                            discovered.append([
                                "mac": macStr,
                                "ip": ipStr,
                                "mask": maskStr,
                                "gateway": gwStr,
                                "dhcp": dhcp
                            ])
                            print("[POSNetConfig] 🔍 Tìm thấy qua UDP: ip=\(ipStr) mac=\(macStr)")
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                completion(discovered)
            }
        }
    }
}
