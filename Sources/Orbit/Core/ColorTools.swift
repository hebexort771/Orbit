import AppKit
import SwiftUI

enum ArtworkPalette {
    /// Color más vivo de una portada, ajustado para verse bien sobre negro.
    static func accent(from image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 18
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let found: NSColor? = pixels.withUnsafeMutableBytes { raw -> NSColor? in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            let bytes = raw.bindMemory(to: UInt8.self)

            var buckets: [Int: (r: Double, g: Double, b: Double, w: Double)] = [:]
            var avg = (r: 0.0, g: 0.0, b: 0.0)
            for i in 0..<(side * side) {
                let r = Double(bytes[i * 4]) / 255
                let g = Double(bytes[i * 4 + 1]) / 255
                let b = Double(bytes[i * 4 + 2]) / 255
                avg.r += r; avg.g += g; avg.b += b
                let maxC = max(r, g, b), minC = min(r, g, b)
                let sat = maxC > 0 ? (maxC - minC) / maxC : 0
                let weight = sat * sat * maxC + 0.02
                let hue = hueOf(r: r, g: g, b: b)
                let key = Int(hue * 12) % 12
                var bucket = buckets[key] ?? (r: 0, g: 0, b: 0, w: 0)
                bucket.r += r * weight; bucket.g += g * weight; bucket.b += b * weight; bucket.w += weight
                buckets[key] = bucket
            }
            let count = Double(side * side)
            guard let best = buckets.values.max(by: { $0.w < $1.w }), best.w > 0.6 else {
                return NSColor(srgbRed: avg.r / count, green: avg.g / count, blue: avg.b / count, alpha: 1)
            }
            return NSColor(srgbRed: best.r / best.w, green: best.g / best.w, blue: best.b / best.w, alpha: 1)
        }
        return found.map(readable)
    }

    private static func hueOf(r: Double, g: Double, b: Double) -> Double {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let d = maxC - minC
        guard d > 0.0001 else { return 0 }
        var h: Double
        if maxC == r { h = (g - b) / d }
        else if maxC == g { h = 2 + (b - r) / d }
        else { h = 4 + (r - g) / d }
        h /= 6
        if h < 0 { h += 1 }
        return h
    }

    /// Sube el brillo y la saturación lo justo para que destaque sobre negro.
    static func readable(_ color: NSColor) -> NSColor {
        guard let c = color.usingColorSpace(.sRGB) else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.12 { return NSColor(white: 0.92, alpha: 1) }
        let sat = min(max(s, 0.45), 0.85)
        let bri = max(b, 0.82)
        return NSColor(hue: h, saturation: sat, brightness: bri, alpha: 1)
    }
}

extension Color {
    static let orbitGreen = Color(red: 0.25, green: 0.86, blue: 0.42)
    static let orbitRed = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let orbitBlue = Color(red: 0.32, green: 0.62, blue: 1.0)
    static let orbitYellow = Color(red: 1.0, green: 0.8, blue: 0.2)
    static let orbitViolet = Color(red: 0.62, green: 0.45, blue: 1.0)
}
