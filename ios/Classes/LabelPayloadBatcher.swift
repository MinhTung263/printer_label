import Foundation

/// Coalesce whole TSPL rows without creating an unbounded transport job.
/// A row larger than maxBytes stays intact: splitting its BITMAP command would
/// make the next job's initialization bytes part of the image payload.
enum LabelPayloadBatcher {
    static func batches(_ rows: [Data], maxRows: Int = 10,
                        maxBytes: Int = 256 * 1024) -> [Data] {
        precondition(maxRows > 0 && maxBytes > 0)
        var result: [Data] = []
        var current = Data()
        var count = 0
        for row in rows where !row.isEmpty {
            if count > 0 && (count == maxRows || current.count + row.count > maxBytes) {
                result.append(current)
                current = Data()
                count = 0
            }
            current.append(row)
            count += 1
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
