import AppKit
import ImageIO
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

/// Mientras la Mac está bloqueada, pone los colores de la canción como fondo de pantalla.
/// Así es macOS quien dibuja encima su propio reloj, tu foto y la contraseña.
/// Al desbloquear, tu fondo de siempre vuelve con un fundido suave.
///
/// Para que bloquear y desbloquear vayan fluidos, la imagen se prepara antes, en segundo plano,
/// cada vez que cambia la canción: en el momento de bloquear solo se cambia el fondo.
@MainActor
final class LockWallpaper {
    static let shared = LockWallpaper()

    private struct Backup: Codable {
        let displayID: UInt32
        let url: String
        let scaling: Int?
        let clipping: Bool?
    }

    struct Prepared {
        let key: String
        let url: URL
        let image: CGImage
    }

    private let defaultsKey = "lockWallpaperBackup"
    private let imageTypes: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]
    private let queue = DispatchQueue(label: "orbit.lock-wallpaper", qos: .userInitiated)
    private(set) var active = false
    private(set) var prepared: Prepared?
    private var shown: Prepared?
    private var pendingKey: String?
    private var applyWhenReady: NSScreen?
    private let dissolve = WallpaperDissolve()
    /// Qué pasó la última vez (para el informe).
    private(set) var note = "sin usar"
    private(set) var originalType = "-"

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Orbit/Fondo", isDirectory: true)
    }

    // MARK: Preparar antes de bloquear

    private func key(media: NowPlayingService, size: CGSize) -> String {
        let soft = media.softArtwork.map { String(UInt(bitPattern: ObjectIdentifier($0).hashValue)) } ?? "-"
        return "\(media.artworkSerial)-\(soft)-\(media.palette.count)-\(Int(size.width))x\(Int(size.height))-\(Settings.shared.lockBackground.rawValue)"
    }

    /// Dibuja la imagen en segundo plano (sin tocar la animación de nada) y la deja lista.
    func prepare(media: NowPlayingService, screen: NSScreen) {
        let size = screen.frame.size
        let key = key(media: media, size: size)
        guard prepared?.key != key, pendingKey != key else { return }
        pendingKey = key
        let input = WallpaperArt.Input(media: media, size: size, style: Settings.shared.lockBackground)
        let folder = folder
        queue.async {
            guard let image = WallpaperArt.render(input) else { return }
            let url = folder.appendingPathComponent("orbit-\(Int(Date().timeIntervalSince1970 * 1000)).png")
            guard WallpaperArt.writePNG(image, to: url, folder: folder) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let ready = Prepared(key: key, url: url, image: image)
                    self.prepared = ready
                    if self.pendingKey == key { self.pendingKey = nil }
                    self.cleanup()
                    if let screen = self.applyWhenReady {
                        self.applyWhenReady = nil
                        self.set(ready, on: screen)
                    }
                }
            }
        }
    }

    // MARK: Al bloquear

    /// Comprueba que tu fondo se pueda restaurar, lo guarda y pone el de la canción.
    /// Devuelve false si no conviene tocar tu fondo (entonces Orbit se dibuja encima de todo).
    @discardableResult
    func apply(media: NowPlayingService, to screen: NSScreen) -> Bool {
        guard begin(screen: screen) else { return false }
        let wanted = key(media: media, size: screen.frame.size)
        if let ready = prepared, ready.key == wanted {
            set(ready, on: screen)
        } else {
            // Aún no estaba lista: se dibuja ahora en segundo plano y se pone apenas termine.
            applyWhenReady = screen
            prepare(media: media, screen: screen)
        }
        active = true
        return true
    }

    private func begin(screen: NSScreen) -> Bool {
        guard stored() == nil else { return true }
        let workspace = NSWorkspace.shared
        guard let displayID = screen.displayID, let current = workspace.desktopImageURL(for: screen) else {
            note = "no se pudo leer tu fondo de pantalla"
            return false
        }
        originalType = current.isFileURL ? "." + current.pathExtension.lowercased() : current.scheme ?? "?"
        guard current.isFileURL, imageTypes.contains(current.pathExtension.lowercased()),
              FileManager.default.fileExists(atPath: current.path), !current.path.hasPrefix(folder.path) else {
            note = "tu fondo actual es de un tipo que no se puede restaurar con seguridad (\(originalType))"
            return false
        }
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        save(Backup(displayID: displayID, url: current.absoluteString,
                    scaling: (options[.imageScaling] as? NSNumber)?.intValue,
                    clipping: (options[.allowClipping] as? NSNumber)?.boolValue))
        return true
    }

    private func set(_ ready: Prepared, on screen: NSScreen) {
        do {
            try NSWorkspace.shared.setDesktopImageURL(ready.url, for: screen, options: [
                .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
                .allowClipping: NSNumber(value: true)
            ])
            shown = ready
            note = "fondo de la canción puesto"
        } catch {
            note = "macOS no dejó cambiar el fondo: \(error.localizedDescription)"
        }
    }

    /// Si cambia la canción con la Mac bloqueada, el fondo cambia también.
    func refresh(media: NowPlayingService, screen: NSScreen) {
        guard active else { return }
        applyWhenReady = screen
        prepare(media: media, screen: screen)
    }

    // MARK: Al desbloquear

    /// Vuelve a poner tu fondo de siempre. Con `animated`, el cambio se tapa con la imagen de la canción
    /// (justo encima del fondo, debajo de tus ventanas) y luego se desvanece despacio.
    func restore(animated: Bool = false) {
        active = false
        applyWhenReady = nil
        guard let backup = stored() else { return }
        let workspace = NSWorkspace.shared
        guard let url = URL(string: backup.url),
              let screen = NSScreen.screens.first(where: { $0.displayID == backup.displayID }) ?? NSScreen.main else { return }
        // Si mientras tanto elegiste otro fondo tú mismo, no se toca.
        if let current = workspace.desktopImageURL(for: screen), !current.path.hasPrefix(folder.path) {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        if animated, let image = shown?.image {
            dissolve.cover(screen, with: image)
        }
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = backup.scaling { options[.imageScaling] = NSNumber(value: scaling) }
        if let clipping = backup.clipping { options[.allowClipping] = NSNumber(value: clipping) }
        do {
            try workspace.setDesktopImageURL(url, for: screen, options: options)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            note += " · restaurado"
        } catch {
            note += " · no se pudo restaurar: \(error.localizedDescription)"
        }
        shown = nil
        if animated { dissolve.fadeOut(after: 0.55, duration: 1.1) }
    }

    /// Al abrir Orbit: si se cerró con la Mac bloqueada, devuelve tu fondo.
    func restoreLeftovers() {
        if stored() != nil { restore() }
    }

    /// La misma imagen que se usa de fondo, para las capturas de prueba.
    func render(media: NowPlayingService, size: CGSize) -> CGImage? {
        WallpaperArt.render(WallpaperArt.Input(media: media, size: size, style: Settings.shared.lockBackground))
    }

    // MARK: Respaldo

    private func stored() -> Backup? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Backup.self, from: data)
    }

    private func save(_ backup: Backup) {
        if let data = try? JSONEncoder().encode(backup) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    private func cleanup() {
        let keep = Set([prepared?.url.lastPathComponent, shown?.url.lastPathComponent].compactMap { $0 })
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for item in items where !keep.contains(item.lastPathComponent) {
            try? FileManager.default.removeItem(at: item)
        }
    }
}

/// Una ventana justo encima del fondo de pantalla (debajo de tus ventanas e iconos) que muestra
/// la imagen de la canción y se desvanece con Core Animation: el cambio de fondo se ve como un fundido.
@MainActor
final class WallpaperDissolve {
    private var window: NSWindow?
    private var layer: CALayer?

    func cover(_ screen: NSScreen, with image: CGImage) {
        window?.orderOut(nil)
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        let layer = CALayer()
        layer.frame = view.bounds
        layer.contents = image
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
        view.layer?.addSublayer(layer)
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
        self.window = window
        self.layer = layer
    }

    func fadeOut(after delay: Double, duration: Double) {
        guard let window, let layer else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            let curve = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let zoom = CABasicAnimation(keyPath: "transform.scale")
            zoom.fromValue = 1
            zoom.toValue = 1.08
            let group = CAAnimationGroup()
            group.animations = [fade, zoom]
            group.duration = duration
            group.timingFunction = curve
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                MainActor.assumeIsolated {
                    window.orderOut(nil)
                    if self?.window === window {
                        self?.window = nil
                        self?.layer = nil
                    }
                }
            }
            layer.opacity = 0
            layer.add(group, forKey: "dissolve")
            CATransaction.commit()
        }
    }
}

/// Dibuja el fondo de colores de la canción con Core Graphics, fuera del hilo principal.
/// Es el mismo dibujo que el fondo animado de Orbit, congelado en un instante.
enum WallpaperArt {
    struct Input {
        let soft: CGImage?
        let colors: [CGColor]
        let size: CGSize
        let style: LockBackground

        @MainActor
        init(media: NowPlayingService, size: CGSize, style: LockBackground) {
            soft = media.softArtwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let fallback = [NSColor(red: 0.24, green: 0.12, blue: 0.42, alpha: 1), NSColor(red: 0.5, green: 0.12, blue: 0.36, alpha: 1),
                            NSColor(red: 0.1, green: 0.16, blue: 0.4, alpha: 1)]
            var list = media.palette.isEmpty ? fallback : media.palette.map { NSColor($0) }
            while list.count < 3 { list.append(list[list.count - 1]) }
            colors = list.map { ($0.usingColorSpace(.sRGB) ?? $0).cgColor }
            self.size = size
            self.style = style
        }
    }

    static func render(_ input: Input) -> CGImage? {
        let W = max(1, input.size.width), H = max(1, input.size.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let rect = CGRect(x: 0, y: 0, width: W, height: H)
        let c = input.colors
        switch input.style {
        case .aurora:
            ctx.setFillColor(c[0]); ctx.fill(rect)
            if let soft = input.soft {
                let diagonal = (W * W + H * H).squareRoot() * 1.3
                layer(ctx, soft, side: diagonal, center: CGPoint(x: W / 2, y: H / 2), degrees: 14 * 3.5, mirror: false,
                      alpha: 0.72, blend: .normal, space: space)
                layer(ctx, soft, side: diagonal, center: CGPoint(x: W / 2, y: H / 2), degrees: 90 - 14 * 5, mirror: true,
                      alpha: 0.34, blend: .screen, space: space)
            }
            let speeds: [(Double, Double, Double)] = [(0.11, 0.07, 0), (0.08, 0.13, 2.1), (0.14, 0.09, 4.2)]
            let t = 14.0
            for index in 0..<3 {
                let s = speeds[index]
                let r = max(W, H) * (0.42 + 0.06 * CGFloat(index))
                let x = W * (0.5 + 0.34 * cos(t * s.0 + s.2))
                let y = H - H * (0.5 + 0.3 * sin(t * s.1 + s.2 * 1.3))
                radial(ctx, color: c[index], alpha: 0.9 * 0.4, center: CGPoint(x: x, y: y), radius: r, blend: .plusLighter, space: space)
            }
            ctx.setBlendMode(.normal)
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.4)); ctx.fill(rect)
        case .blurred:
            ctx.setFillColor(c[0]); ctx.fill(rect)
            if let soft = input.soft {
                let scale = max(W / CGFloat(soft.width), H / CGFloat(soft.height))
                let w = CGFloat(soft.width) * scale, h = CGFloat(soft.height) * scale
                ctx.draw(soft, in: CGRect(x: (W - w) / 2, y: (H - h) / 2, width: w, height: h))
            }
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.38)); ctx.fill(rect)
        case .dark:
            ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1)); ctx.fill(rect)
            radial(ctx, color: c[0], alpha: 0.55, center: CGPoint(x: W * 0.3, y: H * 0.5), radius: W * 0.45, blend: .normal, space: space)
        }
        // Viñeta para que el reloj y la letra siempre se lean.
        if let vignette = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.45)] as CFArray,
                                     locations: [0, 1]) {
            ctx.setBlendMode(.normal)
            ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: min(W, H) * 0.3,
                                   endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: max(W, H) * 0.8,
                                   options: [.drawsAfterEndLocation])
        }
        return ctx.makeImage()
    }

    /// Una capa de la portada difuminada, girada y con el borde desvanecido (nunca se ve una esquina).
    private static func layer(_ ctx: CGContext, _ image: CGImage, side: CGFloat, center: CGPoint, degrees: Double,
                              mirror: Bool, alpha: CGFloat, blend: CGBlendMode, space: CGColorSpace) {
        ctx.saveGState()
        ctx.setBlendMode(blend)
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: -CGFloat(degrees) * .pi / 180)
        if mirror { ctx.scaleBy(x: -1, y: 1) }
        let box = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
        ctx.draw(image, in: box)
        if let edge = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)] as CFArray,
                                 locations: [0, 0.62, 1]) {
            ctx.setBlendMode(.destinationIn)
            ctx.drawRadialGradient(edge, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: side / 2, options: [])
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private static func radial(_ ctx: CGContext, color: CGColor, alpha: CGFloat, center: CGPoint, radius: CGFloat,
                               blend: CGBlendMode, space: CGColorSpace) {
        guard let solid = color.copy(alpha: alpha), let clear = color.copy(alpha: 0),
              let gradient = CGGradient(colorsSpace: space, colors: [solid, clear] as CFArray, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.setBlendMode(blend)
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        ctx.restoreGState()
    }

    static func writePNG(_ image: CGImage, to url: URL, folder: URL) -> Bool {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}

/// Dónde terminan el reloj del sistema (arriba) y empieza el inicio de sesión (abajo), si se encuentran.
struct LockSystemBands: Equatable {
    var clockBottom: CGFloat?
    var loginTop: CGFloat?
}

@MainActor
enum LockReport {
    typealias SystemBands = LockSystemBands

    private static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Orbit/informe-pantalla-bloqueada.txt")
    }

    static var text: String? { try? String(contentsOf: file, encoding: .utf8) }

    /// Busca las ventanas del sistema en la pantalla bloqueada (reloj arriba, inicio de sesión abajo).
    static func bands(on screen: NSScreen) -> SystemBands {
        var bands = SystemBands()
        let frame = cgFrame(of: screen)
        let H = frame.height
        for window in windows() where window.owner != "Orbit" && window.alpha > 0.05 {
            let r = window.bounds.offsetBy(dx: -frame.minX, dy: -frame.minY)
            guard r.width > 20, r.height > 10, r.width < frame.width * 0.9, r.height < H * 0.6 else { continue }
            guard abs(r.midX - frame.width / 2) < frame.width * 0.12 else { continue }
            if r.maxY < H * 0.45 && r.minY > H * 0.02 {
                bands.clockBottom = max(bands.clockBottom ?? 0, r.maxY)
            } else if r.minY > H * 0.55 {
                bands.loginTop = min(bands.loginTop ?? .greatestFiniteMagnitude, r.minY)
            }
        }
        if let value = bands.clockBottom, !(H * 0.1...H * 0.42).contains(value) { bands.clockBottom = nil }
        if let value = bands.loginTop, !(H * 0.6...H * 0.95).contains(value) { bands.loginTop = nil }
        return bands
    }

    static func write(screen: NSScreen, safeTop: CGFloat, mode: String, bands: SystemBands) {
        let frame = cgFrame(of: screen)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var lines = [
            "Orbit \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")",
            "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "Mac: \(DeviceInfo.name) (\(DeviceInfo.identifier))",
            "Pantalla: \(Int(frame.width)) x \(Int(frame.height)) pt, notch \(Int(safeTop)) pt",
            "Modo: \(mode)",
            "Fondo: \(LockWallpaper.shared.note) · tipo original \(LockWallpaper.shared.originalType)",
            "Reloj del sistema termina en: \(bands.clockBottom.map { String(Int($0)) } ?? "no encontrado")",
            "Inicio de sesión empieza en: \(bands.loginTop.map { String(Int($0)) } ?? "no encontrado")",
            "",
            "Ventanas visibles (dueño | capa | x,y ancho×alto | opacidad):"
        ]
        for window in windows() {
            let r = window.bounds.offsetBy(dx: -frame.minX, dy: -frame.minY)
            lines.append("\(window.owner) | \(window.layer) | \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height)) | \(String(format: "%.2f", window.alpha))")
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private struct WindowInfo {
        let owner: String
        let layer: Int
        let bounds: CGRect
        let alpha: Double
    }

    private static func windows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            return WindowInfo(owner: info[kCGWindowOwnerName as String] as? String ?? "?",
                              layer: info[kCGWindowLayer as String] as? Int ?? 0,
                              bounds: bounds,
                              alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }

    /// El marco de la pantalla en coordenadas de CoreGraphics (origen arriba a la izquierda).
    private static func cgFrame(of screen: NSScreen) -> CGRect {
        let primary = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(x: screen.frame.minX, y: primary - screen.frame.maxY,
                      width: screen.frame.width, height: screen.frame.height)
    }
}
