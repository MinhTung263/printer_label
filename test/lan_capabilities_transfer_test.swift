import Foundation
import Network

@main
struct LANCapabilitiesTransferTest {
    static func main() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let modes: [(Bool, Bool, Bool)] = [(true, false, false), (false, true, false),
                                         (false, false, false), (false, false, true), (true, true, false)]
        var index = 0
        var peers: [NWConnection] = []
        var printing = false
        var printed = Data()
        let payload = Data((0..<32768).map { UInt8($0 % 256) })

        func read(_ peer: NWConnection, pending: Data = Data()) {
            peer.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                DispatchQueue.main.async {
                    var pending = pending
                    if let data = data {
                        if printing { printed.append(data) }
                        else {
                            pending.append(data)
                            while pending.count >= 3 {
                                let query = Data(pending.prefix(3))
                                pending.removeFirst(3)
                                let mode = modes[index]
                                let reply: Data?
                                if mode.2 { reply = query } // Echo is not support.
                                else if query == PrinterCapabilityResult.esc && mode.0 { reply = Data([0x12]) }
                                else if query == PrinterCapabilityResult.tspl && mode.1 { reply = Data([0]) }
                                else { reply = nil }
                                if let reply = reply { peer.send(content: reply, completion: .contentProcessed { _ in }) }
                            }
                        }
                    }
                    if !complete && error == nil { read(peer, pending: pending) }
                }
            }
        }

        listener.newConnectionHandler = { peer in peers.append(peer); peer.start(queue: .main); read(peer) }
        func run(_ port: UInt16) {
            let printer = LANPrinterConnection(ip: "127.0.0.1", port: port)
            printer.connect { ok in
                precondition(ok)
                printer.probeCapabilities { result in
                    let languages = result["languages"] as! [String: String]
                    precondition((languages["escpos"] == "confirmed") == modes[index].0)
                    precondition((languages["tspl"] == "confirmed") == modes[index].1)
                    precondition(result["receiveBufferBytes"] is NSNull)
                    if index < modes.count - 1 {
                        printer.disconnect()
                        index += 1
                        run(port)
                    } else {
                        printing = true
                        printer.send(data: payload) { ok, error in
                            precondition(ok && error == nil)
                            precondition(printed == Data([0x1B, 0x40]) + payload)
                            printer.disconnect()
                            listener.cancel()
                            peers.forEach { $0.cancel() }
                            print("LAN capabilities: ESC, TSPL, dual, silence and echoes passed")
                            print("LAN: 32KiB payload preserved byte for byte")
                            exit(0)
                        }
                    }
                }
            }
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port { run(port.rawValue) }
        }
        listener.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { fatalError("Test timed out") }
        dispatchMain()
    }
}
