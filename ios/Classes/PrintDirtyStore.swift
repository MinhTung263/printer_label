import Foundation

/// Sổ ghi nhớ "máy in này có thể đang dở một lệnh ảnh", LƯU BỀN (UserDefaults).
///
/// Ảnh bill đi bằng lệnh raster `GS v 0` khai báo trước số byte. Lần in trước đứt giữa chừng
/// (rút dây, rớt Wi-Fi, tắt máy in, app bị kill / crash) thì máy in vẫn chờ nốt phần ảnh còn
/// thiếu và NUỐT bill kế tiếp làm dữ liệu ảnh -> ra ký tự rác, giấy chạy dài. Lần in kế tiếp tới
/// máy đó phải xả bằng `flushZeros` byte 0x00 (lấp phần ảnh còn thiếu) rồi `ESC @`.
///
/// Trước đây cờ chỉ nằm trong bộ nhớ (`Set` tĩnh) và chỉ bật ở vài đường lỗi, nên app bị kill
/// giữa chừng (hoặc dừng / chạy lại khi debug) là mất cờ, bill sau ra rác. Giờ theo kiểu
/// "ghi trước":
///  - `mark` TRƯỚC khi gửi byte đầu của một lệnh in (ghi đĩa ngay);
///  - `clear` chỉ khi lệnh đã được máy in nhận xong;
///  - mọi gián đoạn giữa hai điểm đó (lỗi, kill, crash) đều để cờ lại.
///
/// Khoá là IP máy in (LAN) hoặc định danh thiết bị (Bluetooth).
enum PrintDirtyStore {
    private static let defaultsKey = "printer_label.print_dirty_keys"
    private static let lock = NSLock()
    private static var keys: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    )

    /// Số byte 0x00 xả. Một dải `GS v 0` tối đa 128 dòng; mỗi dòng tối đa 128 byte (1024 chấm,
    /// đủ máy 112mm) -> lấp được MỌI phần ảnh còn thiếu của một dải. 0x00 thừa là lệnh rỗng.
    static let flushZeros = 128 * 128

    /// Lệnh nhỏ hơn ngưỡng này không thể để máy in dở một lệnh ảnh -> khỏi ghi sổ (đỡ ghi đĩa).
    static let armThresholdBytes = 512

    static func isDirty(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return keys.contains(key)
    }

    /// Đánh dấu và ghi đĩa NGAY: app bị kill ngay sau đó vẫn còn cờ.
    static func mark(_ key: String) {
        guard !key.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guard keys.insert(key).inserted else { return }
        persistLocked()
    }

    /// Bỏ đánh dấu. Mất lần ghi này chỉ gây thêm một lần xả thừa, vô hại.
    static func clear(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        guard keys.remove(key) != nil else { return }
        persistLocked()
    }

    private static func persistLocked() {
        let defaults = UserDefaults.standard
        defaults.set(Array(keys), forKey: defaultsKey)
        defaults.synchronize()
    }
}
