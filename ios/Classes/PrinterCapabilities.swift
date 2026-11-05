import Foundation

enum PrinterCapabilityResult {
    static func value(deviceId: String, esc: Bool = false, tspl: Bool = false,
                      reason: String = "no_response") -> [String: Any] {
        ["deviceId": deviceId, "reason": reason,
         "languages": ["escpos": esc ? "confirmed" : "unknown", "tspl": tspl ? "confirmed" : "unknown"],
         "features": ["nativeText": "not_tested", "raster": "not_tested", "barcode": "not_tested", "qrCode": "not_tested"],
         "receiveBufferBytes": NSNull()]
    }
    static func validEsc(_ data: Data) -> Bool { data.count == 1 && (data.first! & 0x93) == 0x12 }
    static func validTspl(_ data: Data) -> Bool { data.count == 1 && (data.first! & 0x80) == 0 }
    static let esc = Data([0x10, 0x04, 0x04])
    static let tspl = Data([0x1B, 0x21, 0x3F])
}
