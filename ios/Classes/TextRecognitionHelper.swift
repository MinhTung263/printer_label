import UIKit
import Vision

/// Nhận chữ trong ảnh bằng Vision của Apple (có sẵn trong iOS 13+, chạy trên máy,
/// chạy được cả Simulator) — VD đọc IP / gateway trên tờ self-test của máy in.
enum TextRecognitionHelper {
    /// Toàn bộ chữ đọc được, mỗi dòng một hàng theo thứ tự trên → dưới, trái →
    /// phải. `nil` khi không đọc được ảnh / iOS cũ.
    static func recognize(path: String, completion: @escaping (String?) -> Void) {
        guard #available(iOS 13.0, *),
              let image = UIImage(contentsOfFile: path),
              let cgImage = image.cgImage
        else {
            completion(nil)
            return
        }
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation]
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Toạ độ Vision gốc ở dưới-trái: y lớn = ở trên.
            let sorted = observations.sorted { a, b in
                let dy = a.boundingBox.midY - b.boundingBox.midY
                if abs(dy) > 0.01 { return dy > 0 }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            let text = sorted
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            DispatchQueue.main.async { completion(text) }
        }
        request.recognitionLevel = .accurate
        // Không tự "sửa chính tả" — IP / MAC / số hiệu dễ bị sửa sai.
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: orientation(of: image),
            options: [:]
        )
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
