import Foundation
import Network

/// Run with the production LANPrinterConnection on a loopback fake printer.
/// Regressions: enqueuing during confirmation must not lose a completion; an
/// intermediate batch must survive the ordinary 600ms idle-close interval.
@main
struct LANBatchConnectionTest {
    static func main() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        var peers: [NWConnection] = []
        var received = Data()
        var completions: [Int] = []

        func read(_ peer: NWConnection) {
            peer.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                DispatchQueue.main.async {
                    if let data = data { received.append(data) }
                    if !complete && error == nil { read(peer) }
                }
            }
        }

        listener.newConnectionHandler = { peer in
            peers.append(peer)
            peer.start(queue: .main)
            read(peer)
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state, let port = listener.port else { return }
            let printer = LANPrinterConnection(ip: "127.0.0.1", port: port.rawValue)
            printer.send(data: Data([1]), keepOpenAfter: true) { ok, error in
                precondition(ok && error == nil)
                completions.append(1)
            }
            // The first write is waiting for its 400ms confirmation by now.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                printer.send(data: Data([2]), keepOpenAfter: true) { ok, error in
                    precondition(ok && error == nil)
                    completions.append(2)
                    precondition(completions == [1, 2])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        precondition(printer.state == .connected)
                        precondition(peers.count == 1)
                        printer.send(data: Data([3]), keepOpenAfter: false) { ok, error in
                            precondition(ok && error == nil)
                            completions.append(3)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                                precondition(completions == [1, 2, 3])
                                precondition(received == Data([0x1B, 0x40, 1, 2, 3]))
                                precondition(printer.state == .disconnected)
                                listener.cancel()
                                peers.forEach { $0.cancel() }
                                print("LANBatchConnection: all checks passed")
                                exit(0)
                            }
                        }
                    }
                }
            }
        }
        listener.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            fatalError("LAN batch test timed out; completions: \(completions)")
        }
        dispatchMain()
    }
}
