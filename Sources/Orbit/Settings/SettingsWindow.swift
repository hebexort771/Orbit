import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let onClose: () -> Void
    private let router = SettingsRouter()

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let hosting = NSHostingController(rootView: SettingsRoot(router: router))
        window = NSWindow(contentViewController: hosting)
        super.init()
        window.title = "Orbit"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbar = NSToolbar(identifier: "OrbitSettingsToolbar")
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 820, height: 620))
        window.minSize = NSSize(width: 740, height: 520)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("OrbitSettingsWindow")
    }

    func show(section: SettingsSection? = nil) {
        if let section { router.selection = section }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

@MainActor
final class SettingsRouter: ObservableObject {
    @Published var selection: SettingsSection? = .general
}
