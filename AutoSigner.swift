import Foundation
import PDFKit

struct UserProfile: Identifiable {
    var id = UUID()
    var printedName: String
    var signatureImage: NSImage?
}

class AutoSigner {
    func applySignatures(to document: PDFDocument, profile: UserProfile) {
        clearExistingSignatures(from: document)
        
        guard profile.signatureImage != nil else {
            print("⚠️ No signature image found in profile.")
            return
        }
        
        let targetKeywords = ["Physician Signature:", "Physician Signature", "Attending Physician"]
        let excludeKeywords = ["nurse", "np", "rn", "lpn"]
        
        var signedPages: [Int: [CGRect]] = [:]
        
        for keyword in targetKeywords {
            let selections = document.findString(keyword, withOptions: .caseInsensitive)
            
            for selection in selections {
                guard let page = selection.pages.first else { continue }
                let pageIndex = document.index(for: page)
                let keywordBounds = selection.bounds(for: page)
                
                let extendedBounds = keywordBounds.insetBy(dx: -150, dy: 0)
                let extendedSelection = page.selection(for: extendedBounds)
                let lineText = extendedSelection?.string?.lowercased() ?? ""
                
                if excludeKeywords.contains(where: { lineText.contains($0) }) { continue }
                
                let existingRects = signedPages[pageIndex] ?? []
                if existingRects.contains(where: { $0.intersects(keywordBounds.insetBy(dx: -20, dy: -20)) }) {
                    continue
                }
                
                let signatureWidth: CGFloat = 380
                let signatureHeight: CGFloat = 90
                
                let signatureRect = CGRect(
                    x: keywordBounds.maxX + 10,
                    y: keywordBounds.maxY - signatureHeight,
                    width: signatureWidth,
                    height: signatureHeight
                )
                
                let annotation = CleanSignatureAnnotation(bounds: signatureRect, profile: profile)
                page.addAnnotation(annotation)
                
                if signedPages[pageIndex] == nil { signedPages[pageIndex] = [] }
                signedPages[pageIndex]?.append(keywordBounds)
            }
        }
    }
    
    func batchSign(urls: [URL], profile: UserProfile) -> Int {
        var successCount = 0
        
        for url in urls {
            guard let doc = PDFDocument(url: url) else { continue }
            applySignatures(to: doc, profile: profile)
            
            let outputFolder = url.deletingLastPathComponent()
            let baseName = url.deletingPathExtension().lastPathComponent
            let outputURL = outputFolder.appendingPathComponent("\(baseName)_signed.pdf")
            
            if doc.write(to: outputURL) {
                successCount += 1
            }
        }
        
        return successCount
    }
    
    func clearExistingSignatures(from document: PDFDocument) {
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            while let annotation = page.annotations.first(where: { $0 is CleanSignatureAnnotation }) {
                page.removeAnnotation(annotation)
            }
        }
    }
}

class CleanSignatureAnnotation: PDFAnnotation {
    var profile: UserProfile
    let timestampString: String
    var isSelected: Bool = false
    
    init(bounds: NSRect, profile: UserProfile, timestamp: String? = nil) {
        self.profile = profile
        
        if let existingTime = timestamp {
            self.timestampString = existingTime
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            self.timestampString = formatter.string(from: Date())
        }
        
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        self.color = .clear
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        
        let rect = self.bounds
        
        if let rawSigImage = profile.signatureImage {
            let sigImage = rawSigImage.trimmingTransparentPixels()
            let imgSize = sigImage.size
            
            if imgSize.width > 0 && imgSize.height > 0 {
                let aspect = imgSize.width / imgSize.height
                
                let maxSigHeight = max(15, rect.height * 0.75)
                var drawHeight = maxSigHeight
                var drawWidth = drawHeight * aspect
                
                if drawWidth > (rect.width - 5) {
                    drawWidth = rect.width - 5
                    drawHeight = drawWidth / aspect
                }
                
                let fitRect = NSRect(
                    x: rect.minX,
                    y: rect.maxY - drawHeight,
                    width: drawWidth,
                    height: drawHeight
                )
                
                sigImage.draw(in: fitRect)
                
                let textLineHeight = max(9.0, rect.height * 0.11)
                let fontSize = max(7.5, textLineHeight * 0.80)
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraphStyle
                ]
                
                let line1Y = fitRect.minY - textLineHeight + 2.0
                let line2Y = line1Y - textLineHeight + 1.0
                
                let line1Text = profile.printedName
                let line1Rect = NSRect(x: rect.minX, y: line1Y, width: rect.width, height: textLineHeight)
                line1Text.draw(in: line1Rect, withAttributes: attributes)
                
                let line2Text = "Electronically Signed \(timestampString)"
                let line2Rect = NSRect(x: rect.minX, y: line2Y, width: rect.width, height: textLineHeight)
                line2Text.draw(in: line2Rect, withAttributes: attributes)
            }
        }
        
        if isSelected {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2.0)
            context.stroke(rect)
            
            let handleSize: CGFloat = max(12.0, rect.height * 0.12)
            let handleRect = CGRect(x: rect.maxX - handleSize, y: rect.maxY - handleSize, width: handleSize, height: handleSize)
            context.setFillColor(NSColor.controlAccentColor.cgColor)
            context.fill(handleRect)
        }
        
        NSGraphicsContext.restoreGraphicsState()
    }
}
