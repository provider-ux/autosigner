import Cocoa

class VectorSignatureTracer {
    static func extractVectorSignature(from image: NSImage) -> NSImage? {
        guard let resizedImage = resize(image, maxDimension: 1000),
              let tiffData = resizedImage.tiffRepresentation,
              let srcRep = NSBitmapImageRep(data: tiffData),
              let cgImage = srcRep.cgImage else { return image }
        
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return image }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var grayBytes = [UInt8](repeating: 255, count: width * height)
        
        guard let grayContext = CGContext(
            data: &grayBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }
        
        grayContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Calculate background paper luminance
        var paperSum = 0, paperCount = 0
        for i in 0..<(width * height) {
            let val = Int(grayBytes[i])
            if val > 120 {
                paperSum += val
                paperCount += 1
            }
        }
        let avgPaperLuminance = paperCount > 100 ? (paperSum / paperCount) : 200
        let inkThreshold = max(avgPaperLuminance - 35, 50)
        
        let rgbaSpace = CGColorSpaceCreateDeviceRGB()
        var outBytes = [UInt8](repeating: 0, count: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let val = Int(grayBytes[idx])
                if val < inkThreshold {
                    let outIndex = idx * 4
                    outBytes[outIndex] = 0       // R
                    outBytes[outIndex + 1] = 0   // G
                    outBytes[outIndex + 2] = 0   // B
                    outBytes[outIndex + 3] = 255 // Alpha (Ink)
                }
            }
        }
        
        guard let outContext = CGContext(
            data: &outBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: rgbaSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let fullProcessedCG = outContext.makeImage() else { return image }
        
        let fullImage = NSImage(cgImage: fullProcessedCG, size: NSSize(width: width, height: height))
        
        // Strictly crops image down to the exact millimeter of non-transparent ink
        return fullImage.trimmingTransparentPixels()
    }
    
    private static func resize(_ image: NSImage, maxDimension: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0 && size.height > 0 else { return nil }
        
        let maxCurrent = max(size.width, size.height)
        if maxCurrent <= maxDimension { return image }
        
        let scale = maxDimension / maxCurrent
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

extension NSImage {
    /// Scans RGBA pixels and crops the image strictly to the ink bounding box
    func trimmingTransparentPixels() -> NSImage {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return self }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var minX = width, minY = height, maxX = 0, maxY = 0
        var foundPixel = false
        
        for y in 0..<height {
            for x in 0..<width {
                let alpha = rawData[(y * width + x) * 4 + 3]
                if alpha > 15 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    foundPixel = true
                }
            }
        }
        
        guard foundPixel, maxX >= minX, maxY >= minY else { return self }
        
        let cropWidth = (maxX - minX) + 1
        let cropHeight = (maxY - minY) + 1
        
        // CGImage coordinate space uses top-left origin
        let cropRect = CGRect(x: minX, y: minY, width: cropWidth, height: cropHeight)
        
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return self }
        return NSImage(cgImage: croppedCG, size: NSSize(width: cropWidth, height: cropHeight))
    }
}
