import Cocoa
import CoreImage

public struct ArtworkColorTheme: Equatable {
    public let primary: NSColor
    public let glow: NSColor
    public let border: NSColor
    
    public static let `default` = ArtworkColorTheme(
        primary: NSColor(red: 0.38, green: 0.82, blue: 1.00, alpha: 1.0), // Cyan
        glow: NSColor(red: 0.38, green: 0.82, blue: 1.00, alpha: 0.45),
        border: NSColor(white: 1.0, alpha: 0.20)
    )
}

public final class ColorExtractor {
    public static let shared = ColorExtractor()
    private var colorCache: [String: ArtworkColorTheme] = [:]
    
    public func extractTheme(from imageURLString: String?, completion: @escaping (ArtworkColorTheme) -> Void) {
        guard let urlStr = imageURLString, let url = URL(string: urlStr) else {
            completion(.default)
            return
        }
        
        if let cached = colorCache[urlStr] {
            completion(cached)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async { completion(.default) }
                return
            }
            
            let color = self?.dominantColor(from: cgImage) ?? NSColor(red: 0.38, green: 0.82, blue: 1.00, alpha: 1.0)
            
            // Adjust saturation & brightness for vibrant UI aura
            var hue: CGFloat = 0
            var sat: CGFloat = 0
            var bri: CGFloat = 0
            var alpha: CGFloat = 0
            color.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            
            let vibrantSat = max(0.55, min(sat * 1.25, 0.95))
            let vibrantBri = max(0.75, min(bri * 1.15, 1.0))
            
            let primary = NSColor(hue: hue, saturation: vibrantSat, brightness: vibrantBri, alpha: 1.0)
            let glow = NSColor(hue: hue, saturation: vibrantSat, brightness: vibrantBri, alpha: 0.50)
            let border = NSColor(hue: hue, saturation: vibrantSat * 0.7, brightness: 1.0, alpha: 0.28)
            
            let theme = ArtworkColorTheme(primary: primary, glow: glow, border: border)
            self?.colorCache[urlStr] = theme
            
            DispatchQueue.main.async {
                completion(theme)
            }
        }
    }
    
    private func dominantColor(from image: CGImage) -> NSColor {
        let size = CGSize(width: 24, height: 24)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return NSColor(red: 0.38, green: 0.82, blue: 1.00, alpha: 1.0)
        }
        
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard let data = context.data else {
            return NSColor(red: 0.38, green: 0.82, blue: 1.00, alpha: 1.0)
        }
        
        let pointer = data.bindMemory(to: UInt8.self, capacity: Int(size.width * size.height * 4))
        var rTotal: CGFloat = 0
        var gTotal: CGFloat = 0
        var bTotal: CGFloat = 0
        var count: CGFloat = 0
        
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                let offset = (y * Int(size.width) + x) * 4
                let r = CGFloat(pointer[offset]) / 255.0
                let g = CGFloat(pointer[offset + 1]) / 255.0
                let b = CGFloat(pointer[offset + 2]) / 255.0
                
                // Exclude pure blacks, pure whites, and muddy greys
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let sat = maxC > 0 ? (maxC - minC) / maxC : 0
                let bri = maxC
                
                if sat > 0.18 && bri > 0.20 && bri < 0.92 {
                    rTotal += r
                    gTotal += g
                    bTotal += b
                    count += 1
                }
            }
        }
        
        if count == 0 {
            return NSColor(red: 0.38, green: 0.82, blue: 1.00, alpha: 1.0)
        }
        
        return NSColor(
            red: rTotal / count,
            green: gTotal / count,
            blue: bTotal / count,
            alpha: 1.0
        )
    }
}
