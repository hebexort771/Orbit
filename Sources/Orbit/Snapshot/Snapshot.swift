import AppKit
import SwiftUI

/// `Orbit --snapshot carpeta` dibuja cada estado de la isla en PNG y captura las ventanas reales.
/// Sirve para revisar el diseño en la compilación automática.
@MainActor
enum Snapshot {
    static func run(into folder: String, delegate: AppDelegate) {
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
            Case(name: "20-floating-volume", floating: true) { $0.show(.volume(level: 0.3, muted: false, output: .airpodsPro), for: nil) }
        ]

        for item in cases {
            let model = IslandModel(metrics: item.floating ? .previewFloating() : .preview, isPreview: item.preview)
            item.setup(model)
            let view = SnapshotFrame(model: model)
                .services(services)
                .environment(\.orbitStatic, true)
            write(view, to: directory.appendingPathComponent(item.name + ".png"))
        }

        let card = LockCardState()
        card.visible = true
        let lock = ZStack {
            PreviewWallpaper()
            LockMusicCard(state: card)
        }
        .frame(width: 520, height: 420)
        .services(services)
        .environment(\.orbitStatic, true)
        write(lock, to: directory.appendingPathComponent("21-lock-screen-card.png"))

        let icons = HStack(spacing: 18) {
            ForEach(SettingsSection.allCases) { SettingsIcon(section: $0, size: 40) }
        }
        .padding(20)
        .background(Color.white)
        write(icons, to: directory.appendingPathComponent("22-settings-icons.png"))
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
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
