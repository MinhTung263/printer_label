import UIKit

extension UIImage {
    /// Binarizes the image with a specified threshold (0-255).
    /// Pixels with luminance less than threshold become black, others become white.
    /// Transparent pixels (alpha <= 50) become white.
    func binarized(threshold: UInt8 = 200) -> UIImage? {
        var cgImageToProcess = self.cgImage
        if cgImageToProcess == nil, let ciImage = self.ciImage {
            let context = CIContext(options: nil)
            cgImageToProcess = context.createCGImage(ciImage, from: ciImage.extent)
        }
        guard let cgImage = cgImageToProcess else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        for i in 0..<width * height {
            let offset = i * 4
            let r = rawData[offset]
            let g = rawData[offset + 1]
            let b = rawData[offset + 2]
            let a = rawData[offset + 3]
            
            if a > 50 {
                // Integer-based luminance formula (0.299 * R + 0.587 * G + 0.114 * B)
                let gray = (Int(r) * 299 + Int(g) * 587 + Int(b) * 114) / 1000
                if gray < Int(threshold) {
                    rawData[offset] = 0     // R
                    rawData[offset + 1] = 0 // G
                    rawData[offset + 2] = 0 // B
                } else {
                    rawData[offset] = 255   // R
                    rawData[offset + 1] = 255 // G
                    rawData[offset + 2] = 255 // B
                }
            } else {
                // Transparent to white
                rawData[offset] = 255
                rawData[offset + 1] = 255
                rawData[offset + 2] = 255
                rawData[offset + 3] = 255
            }
        }
        
        guard let newCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: newCGImage, scale: self.scale, orientation: self.imageOrientation)
    }
}
