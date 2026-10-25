import AppKit
import SwiftUI

/// Ventana transparente sobre la barra de menús, en todos los escritorios.
final class IslandPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        titleVisibility = .hidden
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Acepta el primer clic aunque la ventana no esté activa.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Inyecta los servicios en cualquier vista de la isla.
struct ServiceEnvironment: ViewModifier {
    let services: Services
    func body(content: Content) -> some View {
        content
            .environmentObject(services.media)
            .environmentObject(services.battery)
            .environmentObject(services.audio)
            .environmentObject(services.calendar)
            .environmentObject(services.tray)
    }
}

extension View {
    func services(_ services: Services) -> some View { modifier(ServiceEnvironment(services: services)) }
}
