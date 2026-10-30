import AppKit
import SwiftUI

/// `Orbit --snapshot carpeta` dibuja cada estado de la isla en PNG y captura las ventanas reales.
/// Sirve para revisar el diseño en la compilación automática.
@MainActor
enum Snapshot {
    static func run(into folder: String, delegate: AppDelegate) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--lang"), index + 1 < arguments.count,
           let language = AppLanguage(rawValue: arguments[index + 1]) {
            Settings.shared.language = language
        } else {
            Settings.shared.language = .es
        }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            renderStates(to: directory)
            await captureLive(to: directory, delegate: delegate)
            NSApp.terminate(nil)
        }
    }

    private struct Case {
        let name: String
        var floating = false
        var preview = true
        let setup: @MainActor (IslandModel) -> Void
    }

    private static func renderStates(to directory: URL) {
        let services = Services.demo
        let cases: [Case] = [
            Case(name: "01-idle") { _ in },
            Case(name: "02-hover", preview: false) { $0.hovering = true },
            Case(name: "03-music") { $0.liveMusic = true },
            Case(name: "04-music-expanded") { $0.liveMusic = true; $0.page = .music; $0.expanded = true },
            Case(name: "05-lyrics") { $0.page = .music; $0.lyricsMode = true; $0.expanded = true },
            Case(name: "06-calendar") { $0.page = .calendar; $0.expanded = true },
            Case(name: "07-tray") { $0.page = .tray; $0.expanded = true },
            Case(name: "08-tray-drop") { $0.dragActive = true },
            Case(name: "09-volume") { $0.show(.volume(level: 0.56, muted: false, output: .speaker), for: nil) },
            Case(name: "10-brightness") { $0.show(.brightness(level: 0.7), for: nil) },
            Case(name: "11-charging") { $0.show(.battery(.charging(80)), for: nil) },
            Case(name: "12-low-battery") { $0.show(.battery(.low(15)), for: nil) },
            Case(name: "13-airpods") { $0.show(.bluetooth(name: "AirPods Pro", symbol: "airpodspro", battery: 85, connected: true), for: nil) },
            Case(name: "14-lock") { $0.show(.lock(locked: true), for: nil) },
            Case(name: "15-unlock") { $0.show(.lock(locked: false), for: nil) },
            Case(name: "16-calendar-alert") { $0.show(.calendar(title: "Diseño de la app", minutes: 5, color: .orbitBlue), for: nil) },
            Case(name: "17-welcome") { $0.show(.welcome, for: nil) },
            Case(name: "18-floating-music", floating: true) { $0.liveMusic = true },
            Case(name: "19-floating-expanded", floating: true) { $0.page = .music; $0.expanded = true },
            Case(name: "20-floating-volume", floating: true) { $0.show(.volume(level: 0.3, muted: false, output: .airpodsPro), for: nil) },
            Case(name: "20b-track") { $0.show(.track(title: "Luz de Neón", artist: "Aurora Vale"), for: nil) }
        ]

        for item in cases {
            let model = IslandModel(metrics: item.floating ? .previewFloating() : .preview, isPreview: item.preview)
            item.setup(model)
            let view = SnapshotFrame(model: model)
                .services(services)
                .environment(\.orbitStatic, true)
            write(view, to: directory.appendingPathComponent(item.name + ".png"))
        }

        // Notch líquido: el cursor se acerca por debajo y el notch se estira hacia él como agua.
        let approach: [(String, CGPoint, Bool)] = [
            ("50-agua-lejos", CGPoint(x: 30, y: 150), false),
            ("51-agua-cerca", CGPoint(x: 30, y: 92), false),
            ("52-agua-gota", CGPoint(x: 36, y: 64), false),
            ("53-agua-gota-lado", CGPoint(x: -64, y: 60), false),
            ("54-agua-musica", CGPoint(x: 10, y: 66), true)
        ]
        for (name, pointer, music) in approach {
            let model = IslandModel(metrics: .preview, isPreview: true)
            model.liveMusic = music
            let layout = model.currentLayout
            let geometry = LiquidField.Geometry(height: layout.height, halfFlat: layout.width / 2 - layout.bottom, collapsed: true)
            model.liquid.simulate(pointer: pointer, geometry: geometry, seconds: 1.6)
            let view = ZStack(alignment: .topLeading) {
                SnapshotFrame(model: model)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                    .offset(x: 360 + pointer.x - 3, y: model.metrics.topInset + pointer.y - 2)
            }
            .frame(width: 720, height: 270)
            .services(services)
            .environment(\.orbitStatic, true)
            write(view, to: directory.appendingPathComponent(name + ".png"))
        }
        // Onda al soltar: la gota vuelve a entrar y el borde ondula.
        do {
            let model = IslandModel(metrics: .preview, isPreview: true)
            let layout = model.currentLayout
            let geometry = LiquidField.Geometry(height: layout.height, halfFlat: layout.width / 2 - layout.bottom, collapsed: true)
            model.liquid.simulate(pointer: CGPoint(x: 20, y: 64), geometry: geometry, seconds: 1.4)
            model.liquid.splash(at: 20, strength: 4)
            model.liquid.simulate(pointer: nil, geometry: geometry, seconds: 0.2)
            write(SnapshotFrame(model: model).services(services).environment(\.orbitStatic, true),
                  to: directory.appendingPathComponent("55-agua-onda.png"))
        }

        for (index, style) in LockStyle.allCases.enumerated() {
            let state = LockScreenState()
            state.style = style
            state.phase = .shown
            let size = CGSize(width: 1470, height: 956)
            let lock = ZStack(alignment: .topLeading) {
                PreviewWallpaper()
                LockScreenView(state: state, size: size, safeTop: 32)
            }
            .frame(width: size.width, height: size.height)
            .services(services)
            .environment(\.orbitStatic, true)
            write(lock, to: directory.appendingPathComponent("21-lock-\(index + 1)-\(style.rawValue).png"), scale: 1)
        }

        // Cada MacBook con notch, con su notch y el inicio de sesión de macOS simulados,
        // para comprobar que nada se tapa ni se sale.
        let macs: [(String, CGSize, CGFloat, CGFloat)] = [
            ("air13", CGSize(width: 1470, height: 956), 32, 185),
            ("air15", CGSize(width: 1710, height: 1112), 32, 185),
            ("pro14", CGSize(width: 1512, height: 982), 32, 185),
            ("pro16", CGSize(width: 1728, height: 1117), 32, 185),
            ("pro14-mas-espacio", CGSize(width: 1800, height: 1169), 38, 220)
        ]
        for (name, size, top, notchWidth) in macs {
            for style in [LockStyle.widget, .lyrics, .cover, .karaoke, .card] {
                let state = LockScreenState()
                state.style = style
                state.phase = .shown
                let lock = ZStack(alignment: .topLeading) {
                    PreviewWallpaper()
                    LockScreenView(state: state, size: size, safeTop: top)
                    LoginMock(size: size, safeTop: top, notchWidth: notchWidth)
                }
                .frame(width: size.width, height: size.height)
                .services(services)
                .environment(\.orbitStatic, true)
                write(lock, to: directory.appendingPathComponent("24-fit-\(name)-\(style.rawValue).png"), scale: 1)
            }
        }

        // Inicio de la canción (antes de la primera línea): los puntos van en su propia fila.
        services.media.demoSeek(to: 12)
        for style in [LockStyle.lyrics, .karaoke] {
            let state = LockScreenState()
            state.style = style
            state.phase = .shown
            let size = CGSize(width: 1710, height: 1112)
            let lock = ZStack(alignment: .topLeading) {
                PreviewWallpaper()
                LockScreenView(state: state, size: size, safeTop: 32)
                LoginMock(size: size, safeTop: 32, notchWidth: 185)
            }
            .frame(width: size.width, height: size.height)
            .services(services)
            .environment(\.orbitStatic, true)
            write(lock, to: directory.appendingPathComponent("25-intro-\(style.rawValue).png"), scale: 1)
        }
        services.media.demoSeek(to: 69)

        // Modo "encima de todo": fondo completo con un hueco suave donde está tu foto y la contraseña.
        do {
            let state = LockScreenState()
            state.style = .lyrics
            state.phase = .shown
            state.loginHole = true
            let size = CGSize(width: 1710, height: 1112)
            let lock = ZStack(alignment: .topLeading) {
                PreviewWallpaper()
                LockScreenView(state: state, size: size, safeTop: 32)
                LoginMock(size: size, safeTop: 32, notchWidth: 185)
            }
            .frame(width: size.width, height: size.height)
            .services(services)
            .environment(\.orbitStatic, true)
            write(lock, to: directory.appendingPathComponent("26-encima-de-todo.png"), scale: 1)
        }

        // Letra palabra por palabra: a mitad de una línea.
        services.media.demoSeek(to: 74.6)
        do {
            let state = LockScreenState()
            state.style = .lyrics
            state.phase = .shown
            let size = CGSize(width: 1710, height: 1112)
            let lock = ZStack(alignment: .topLeading) {
                PreviewWallpaper()
                LockScreenView(state: state, size: size, safeTop: 32)
            }
            .frame(width: size.width, height: size.height)
            .services(services)
            .environment(\.orbitStatic, true)
            write(lock, to: directory.appendingPathComponent("28-karaoke.png"), scale: 1)

            let model = IslandModel(metrics: .preview)
            model.page = .music
            model.lyricsMode = true
            model.expanded = true
            write(SnapshotFrame(model: model).services(services).environment(\.orbitStatic, true),
                  to: directory.appendingPathComponent("29-karaoke-isla.png"))
        }
        services.media.demoSeek(to: 69)

        // La imagen que se pone como fondo de pantalla mientras la Mac está bloqueada.
        if let wallpaper = LockWallpaper.shared.render(media: services.media, size: CGSize(width: 1710, height: 1112)) {
            let rep = NSBitmapImageRep(cgImage: wallpaper)
            if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                try? data.write(to: directory.appendingPathComponent("27-fondo-de-pantalla.jpg"))
            }
        }

        let thumbs = HStack(spacing: 14) {
            ForEach(LockStyle.allCases) { style in
                LockStyleThumb(style: style, accent: services.media.accent)
                    .frame(width: 120, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
        .background(Color.white)
        write(thumbs, to: directory.appendingPathComponent("22-lock-thumbs.png"))

        let icons = HStack(spacing: 18) {
            ForEach(SettingsSection.allCases) { SettingsIcon(section: $0, size: 40) }
        }
        .padding(20)
        .background(Color.white)
        write(icons, to: directory.appendingPathComponent("23-settings-icons.png"))
    }

    private static func write<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else {
            NSLog("Orbit snapshot: no se pudo dibujar \(url.lastPathComponent)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }

    // MARK: Ventanas reales

    private static func captureLive(to directory: URL, delegate: AppDelegate) async {
        delegate.start(demo: true)
        await pause(2.6)
        screen(to: directory, "30-live-welcome")
        guard let island = delegate.island else { return }
        island.model.liveMusic = true
        await pause(1.2)
        screen(to: directory, "31-live-music")
        island.demo(.battery(.charging(80)))
        await pause(0.9)
        screen(to: directory, "32-live-charging")
        island.expand(page: .music)
        await pause(1.2)
        screen(to: directory, "33-live-expanded")
        island.collapse()

        delegate.previewLockScreen()
        // Fotogramas de la entrada y la salida, para revisar la coreografía.
        await pause(0.35)
        screen(to: directory, "34a-live-lock-entrada")
        await pause(0.3)
        screen(to: directory, "34b-live-lock-entrada")
        await pause(1.6)
        screen(to: directory, "34-live-lock-preview")
        delegate.lockScreenController?.closePreview(animated: true)
        await pause(0.15)
        screen(to: directory, "35a-live-lock-salida")
        await pause(0.25)
        screen(to: directory, "35b-live-lock-salida")
        await pause(1.0)

        for section in SettingsSection.allCases {
            delegate.showSettings(section)
            await pause(section == .general ? 1.4 : 0.9)
            if let number = delegate.settingsWindowNumber {
                window(number, to: directory, "40-settings-" + section.rawValue)
            }
        }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func screen(to directory: URL, _ name: String) {
        capture(["-x", "-C", directory.appendingPathComponent(name + ".png").path])
    }

    private static func window(_ number: Int, to directory: URL, _ name: String) {
        capture(["-x", "-o", "-l", String(number), directory.appendingPathComponent(name + ".png").path])
    }

    private static func capture(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("Orbit snapshot: screencapture falló: \(error)")
        }
    }
}

/// Un trozo de escritorio con la barra de menús y el notch.
struct SnapshotFrame: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        ZStack(alignment: .top) {
            PreviewWallpaper()
            PreviewMenuBar()
                .frame(height: model.metrics.notchHeight)
            IslandCanvas(model: model)
        }
        .frame(width: 720, height: 270, alignment: .top)
        .clipped()
    }
}

/// Notch e inicio de sesión de macOS dibujados encima, solo para las capturas de prueba.
private struct LoginMock: View {
    let size: CGSize
    let safeTop: CGFloat
    let notchWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                .fill(Color.black)
                .frame(width: notchWidth, height: safeTop)
                .position(x: size.width / 2, y: safeTop / 2)
            VStack(spacing: 10) {
                Circle().fill(Color.white.opacity(0.35)).frame(width: 64, height: 64)
                Text("Usuario").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                Capsule().fill(Color.white.opacity(0.22)).frame(width: 180, height: 30)
            }
            .position(x: size.width / 2, y: size.height - 132)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
