import Flutter
import PrinterSDK

class BluetoothScanner: NSObject, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?
    // uuid → PTPrinter (để connect sau)
    private var ptPrinters: [String: PTPrinter] = [:]

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        ptPrinters.removeAll()
        startScan()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopScan()
        self.eventSink = nil
        return nil
    }

    // MARK: - Public API

    func startScan() {
        let dispatcher = PTDispatcher.share()

        dispatcher?.whenFindAllBluetooth { [weak self] printerArray in
            guard let self, let array = printerArray else { return }

            for case let pt as PTPrinter in array {
                let uuid = pt.uuid ?? ""
                guard !uuid.isEmpty, self.ptPrinters[uuid] == nil else { continue }

                self.ptPrinters[uuid] = pt
                let device: [String: String] = [
                    "name": pt.name ?? "Unknown",
                    "mac": uuid,
                ]
                DispatchQueue.main.async {
                    self.eventSink?(device)
                }
            }
        }

        dispatcher?.scanBluetooth()
    }

    func stopScan() {
        PTDispatcher.share()?.stopScanBluetooth()
    }

    /// Trả danh sách thiết bị đã tìm thấy
    func discoveredDevices() -> [[String: String]] {
        return ptPrinters.values.map { pt in
            ["name": pt.name ?? "Unknown", "mac": pt.uuid ?? ""]
        }
    }

    /// Lấy PTPrinter object theo UUID để connect
    func printer(forUUID uuid: String) -> PTPrinter? {
        return ptPrinters[uuid]
    }
}
