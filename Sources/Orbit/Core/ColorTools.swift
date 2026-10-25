import AppKit
import SwiftUI
import CoreImage

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

extension ArtworkPalette {
    /// Hasta 4 colores de la portada, oscurecidos para usarlos como fondo.
    static func palette(from image: NSImage) -> [NSColor] {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let colors: [NSColor] = pixels.withUnsafeMutableBytes { raw -> [NSColor] in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return [] }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            let bytes = raw.bindMemory(to: UInt8.self)
            var buckets: [Int: (r: Double, g: Double, b: Double, w: Double)] = [:]
            for i in 0..<(side * side) {
                let r = Double(bytes[i * 4]) / 255, g = Double(bytes[i * 4 + 1]) / 255, b = Double(bytes[i * 4 + 2]) / 255
                let maxC = max(r, g, b), minC = min(r, g, b)
                let sat = maxC > 0 ? (maxC - minC) / maxC : 0
                let key: Int
                if sat < 0.15 { key = 100 + Int(maxC * 3) } else { key = Int(hueOf(r: r, g: g, b: b) * 10) % 10 }
                let weight = 0.25 + sat * maxC
                var bucket = buckets[key] ?? (r: 0, g: 0, b: 0, w: 0)
                bucket.r += r * weight; bucket.g += g * weight; bucket.b += b * weight; bucket.w += weight
                buckets[key] = bucket
            }
            return buckets.values.sorted { $0.w > $1.w }.prefix(4).map {
                NSColor(srgbRed: $0.r / $0.w, green: $0.g / $0.w, blue: $0.b / $0.w, alpha: 1)
            }
        }
        return colors.map(backdrop)
    }

    /// Versión oscura y saturada de un color, para fondos con texto blanco encima.
    static func backdrop(_ color: NSColor) -> NSColor {
        guard let c = color.usingColorSpace(.sRGB) else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s < 0.12 ? s : min(0.95, s * 1.15 + 0.1), brightness: min(max(b * 0.75, 0.22), 0.62), alpha: 1)
    }

    /// La portada reducida y muy difuminada: una textura suave para el fondo animado.
    static func soft(from image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 64
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let small = ctx.makeImage() else { return nil }
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let output = CIImage(cgImage: small)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 5)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35, kCIInputBrightnessKey: -0.04])
            .cropped(to: rect)
        guard let result = CIContext().createCGImage(output, from: rect) else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: side, height: side))
    }
}

/// El color de acento actual (portada, sistema o elegido por el usuario).
enum AccentStore {
    nonisolated(unsafe) static var current: Color = .white
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }

    /// Colores sugeridos para el acento personalizado.
    static let accentPresets: [(String, String)] = [
        ("#FF5C93", "Neón"), ("#FF453A", "Rojo"), ("#FF9F0A", "Ámbar"), ("#FFD60A", "Sol"),
        ("#30D158", "Lima"), ("#40C8E0", "Océano"), ("#0A84FF", "Azul"), ("#BF5AF2", "Violeta"), ("#F2F2F7", "Blanco")
    ]
}

extension Color {
    static let orbitGreen = Color(red: 0.25, green: 0.86, blue: 0.42)
    static let orbitRed = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let orbitBlue = Color(red: 0.32, green: 0.62, blue: 1.0)
    static let orbitYellow = Color(red: 1.0, green: 0.8, blue: 0.2)
    static let orbitViolet = Color(red: 0.62, green: 0.45, blue: 1.0)
}
