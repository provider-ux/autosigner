import Cocoa
import CoreImage

func removeWhiteBackground(from image: NSImage) -> NSImage? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
    
    let ciImage = CIImage(bitmapImageRep: bitmap)
    
    // CoreImage filter to mask out the white background
    let filter = CIFilter(name: "CIMaskingColor")
    filter?.setValue(ciImage, forKey: kCIInputImageKey)
    filter?.setValue(CIColor(red: 1.0, green: 1.0, blue: 1.0), forKey: kCIInputColorKey) // Target white
    
    guard let outputImage = filter?.outputImage else { return nil }
    
    let rep = NSCIImageRep(ciImage: outputImage)
    let finalImage = NSImage(size: rep.size)
    finalImage.addRepresentation(rep)
    
    return finalImage
}
