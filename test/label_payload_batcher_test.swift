import Foundation

@main
struct LabelPayloadBatcherTest {
    static func main() {
        let rows = (0..<23).map { Data([UInt8($0)]) }
        let batches = LabelPayloadBatcher.batches(rows)
        precondition(batches.map { $0.count } == [10, 10, 3])
        precondition(batches.reduce(Data(), +) == rows.reduce(Data(), +))
        precondition(LabelPayloadBatcher.batches([]).isEmpty)

        // Byte limits preserve complete rows, including an oversized BITMAP.
        let bounded = LabelPayloadBatcher.batches([
            Data([1, 2]), Data([3, 4]), Data([5, 6, 7, 8, 9]), Data([10])
        ], maxBytes: 3)
        precondition(bounded == [Data([1, 2]), Data([3, 4]), Data([5, 6, 7, 8, 9]), Data([10])])
        print("LabelPayloadBatcher: all checks passed")
    }
}
