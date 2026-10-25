import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private(set) var services: Services?
    private(set) var island: IslandController?
    private var lockScreen: LockScreenController?
    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot") {
            let folder = index + 1 < arguments.count ? arguments[index + 1] : "snapshots"
            Snapshot.run(into: folder, delegate: self)
            return
        }
        start(demo: arguments.contains("--demo"))
        if arguments.contains("--settings") { openSettings() }
    }

    func start(demo: Bool) {
        let services = demo ? Services.demo : Services()
        self.services = services
        services.start()
        let island = IslandController(services: services)
        self.island = island
        lockScreen = LockScreenController(services: services)

        AppActions.openSettings = { [weak self] in self?.openSettings() }
        AppActions.showOutputMenu = { [weak self] in self?.showOutputMenu() }
        AppActions.collapse = { [weak self] in self?.island?.collapse() }

        refreshStatusItem()
        Settings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &bag)

        if !Settings.shared.welcomeShown || demo {
            Settings.shared.welcomeShown = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                island.welcome()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        services?.media.stop()
        services?.keys.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    // MARK: Ajustes

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(onClose: { [weak self] in
                self?.settingsClosed()
            })
        }
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings(_ section: SettingsSection) {
        openSettings()
        settingsWindow?.show(section: section)
    }

    var settingsWindowNumber: Int? { settingsWindow?.window.windowNumber }

    /// Muestra la pantalla bloqueada de Orbit a pantalla completa, sin bloquear el Mac.
    func previewLockScreen() {
        lockScreen?.preview()
    }

    var lockScreenController: LockScreenController? { lockScreen }

    private func settingsClosed() {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Barra de menús

    private func refreshStatusItem() {
        let wanted = Settings.shared.menuBarIcon
        if wanted && statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = MenuBarIcon.image()
            item.button?.toolTip = "Orbit"
            item.menu = buildMenu()
            statusItem = item
        } else if !wanted, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        } else if let item = statusItem {
            item.menu = buildMenu()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: tr("Ajustes de Orbit…", "Orbit Settings…"), action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Probar animación", "Preview animation"), action: #selector(menuPreview), keyEquivalent: "").target = self
        let pause = menu.addItem(withTitle: (island?.isSuspended ?? false) ? tr("Reanudar Orbit", "Resume Orbit")
                                                                            : tr("Pausar Orbit", "Pause Orbit"),
                                 action: #selector(menuPause), keyEquivalent: "")
        pause.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Salir de Orbit", "Quit Orbit"), action: #selector(menuQuit), keyEquivalent: "q").target = self
        return menu
    }

    @objc private func menuSettings() { openSettings() }
    @objc private func menuPreview() { island?.welcome() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuPause() {
        guard let island else { return }
        island.setSuspended(!island.isSuspended)
        refreshStatusItem()
    }

    // MARK: Salida de audio

    private func showOutputMenu() {
        guard let audio = services?.audio else { return }
        let menu = NSMenu()
        let header = NSMenuItem(title: tr("Salida de audio", "Sound output"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for device in audio.outputDevices() {
            let item = NSMenuItem(title: device.name, action: #selector(pickOutput(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(device.id)
            item.state = device.id == audio.currentDeviceID ? .on : .off
            item.image = NSImage(systemSymbolName: device.kind.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func pickOutput(_ sender: NSMenuItem) {
        services?.audio.selectOutput(UInt32(sender.tag))
    }

    // MARK: Inicio de sesión

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Orbit: no se pudo cambiar el inicio automático: \(error)")
            }
        }
    }
}

/// Icono de la barra de menús: un notch con un punto en órbita.
enum MenuBarIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let pill = NSBezierPath(roundedRect: NSRect(x: 3, y: 10.5, width: 12, height: 5), xRadius: 2.5, yRadius: 2.5)
            pill.fill()
            let orbit = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 2.5, width: 15, height: 7))
            orbit.lineWidth = 1.3
            orbit.stroke()
            NSBezierPath(ovalIn: NSRect(x: 12.2, y: 3.4, width: 3.6, height: 3.6)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
