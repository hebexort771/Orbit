import AppKit
import SwiftUI

/// Mientras la Mac está bloqueada, pone los colores de la canción como fondo de pantalla.
/// Así es macOS quien dibuja encima su propio reloj, tu foto y la contraseña.
/// Al desbloquear deja tu fondo exactamente como estaba.
@MainActor
final class LockWallpaper {
    static let shared = LockWallpaper()

    private struct Backup: Codable {
        let displayID: UInt32
        let url: String
        let scaling: Int?
        let clipping: Bool?
        var ours: String
    }

    private let key = "lockWallpaperBackup"
    private let imageTypes: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]
    private(set) var active = false
    /// Qué pasó la última vez (para el informe).
    private(set) var note = "sin usar"
    private(set) var originalType = "-"

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Orbit/Fondo", isDirectory: true)
    }

    /// Dibuja el fondo de la canción y lo pone en esa pantalla. Si algo falla, no cambia nada y devuelve false.
    @discardableResult
    func apply(media: NowPlayingService, to screen: NSScreen) -> Bool {
        guard let image = render(media: media, size: screen.frame.size, scale: screen.backingScaleFactor) else {
            note = "no se pudo dibujar el fondo"
            return false
        }
        return apply(image, to: screen)
    }

    func apply(_ image: CGImage, to screen: NSScreen) -> Bool {
        let workspace = NSWorkspace.shared
        guard let displayID = screen.displayID else { note = "pantalla sin identificador"; return false }

        // Se guarda tu fondo original solo una vez: si cambia la canción, se sigue restaurando el tuyo.
        var backup = stored()
        if backup == nil {
            guard let current = workspace.desktopImageURL(for: screen) else {
                note = "no se pudo leer tu fondo de pantalla"
                return false
            }
            originalType = current.isFileURL ? "." + current.pathExtension.lowercased() : current.scheme ?? "?"
            guard current.isFileURL, imageTypes.contains(current.pathExtension.lowercased()),
                  FileManager.default.fileExists(atPath: current.path) else {
                note = "tu fondo actual es de un tipo que no se puede restaurar con seguridad (\(originalType))"
                return false
            }
            let options = workspace.desktopImageOptions(for: screen) ?? [:]
            backup = Backup(displayID: displayID, url: current.absoluteString,
                            scaling: (options[.imageScaling] as? NSNumber)?.intValue,
                            clipping: (options[.allowClipping] as? NSNumber)?.boolValue,
                            ours: "")
        }
        guard var backup else { return false }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Un nombre distinto cada vez: macOS guarda los fondos en caché por su ruta.
            let file = folder.appendingPathComponent("orbit-\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                note = "no se pudo guardar la imagen"
                return false
            }
            try data.write(to: file, options: .atomic)
            // Se guarda el respaldo antes de cambiar nada: si Orbit se cerrara, lo restaura al abrir.
            backup.ours = file.path
            save(backup)
            try workspace.setDesktopImageURL(file, for: screen, options: [
                .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
                .allowClipping: NSNumber(value: true)
            ])
            cleanup(keeping: file)
            active = true
            note = "fondo de la canción puesto"
            return true
        } catch {
            note = "macOS no dejó cambiar el fondo: \(error.localizedDescription)"
            if !active { UserDefaults.standard.removeObject(forKey: key) }
            return false
        }
    }

    /// Vuelve a poner tu fondo de siempre.
    func restore() {
        active = false
        guard let backup = stored() else { return }
        let workspace = NSWorkspace.shared
        guard let url = URL(string: backup.url),
              let screen = NSScreen.screens.first(where: { $0.displayID == backup.displayID }) ?? NSScreen.main else { return }
        // Si mientras tanto elegiste otro fondo tú mismo, no se toca.
        if let current = workspace.desktopImageURL(for: screen), !current.path.hasPrefix(folder.path) {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = backup.scaling { options[.imageScaling] = NSNumber(value: scaling) }
        if let clipping = backup.clipping { options[.allowClipping] = NSNumber(value: clipping) }
        do {
            try workspace.setDesktopImageURL(url, for: screen, options: options)
            UserDefaults.standard.removeObject(forKey: key)
            note += " · restaurado"
        } catch {
            note += " · no se pudo restaurar: \(error.localizedDescription)"
        }
    }

    /// Al abrir Orbit: si se cerró con la Mac bloqueada, devuelve tu fondo.
    func restoreLeftovers() {
        if stored() != nil { restore() }
    }

    // MARK: Imagen

    func render(media: NowPlayingService, size: CGSize, scale: CGFloat) -> CGImage? {
        let view = LockBackdrop(size: size)
            .environmentObject(media)
            .environment(\.orbitStatic, true)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    // MARK: Respaldo

    private func stored() -> Backup? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Backup.self, from: data)
    }

    private func save(_ backup: Backup) {
        if let data = try? JSONEncoder().encode(backup) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func cleanup(keeping file: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent != file.lastPathComponent {
            try? FileManager.default.removeItem(at: item)
        }
    }
}

/// Informe de lo que hay en la pantalla bloqueada, para poder ajustar Orbit a tu Mac.
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
