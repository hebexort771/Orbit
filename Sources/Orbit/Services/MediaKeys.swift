import AppKit
import ApplicationServices

enum MediaKey {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
}

/// Brillo de la pantalla integrada (DisplayServices, framework privado de Apple).
enum Brightness {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static let getter: GetFn? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetFn.self)
    }()

    private static let setter: SetFn? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: SetFn.self)
    }()

    static var display: CGDirectDisplayID? {
        NSScreen.screens.first(where: { $0.isBuiltin })?.displayID
    }

    static func get() -> Float? {
        guard let getter, let id = display else { return nil }
        var value: Float = 0
        guard getter(id, &value) == 0 else { return nil }
        return value
    }

    @discardableResult
    static func set(_ value: Float) -> Bool {
        guard let setter, let id = display else { return false }
        return setter(id, max(0, min(1, value))) == 0
    }
}

/// Intercepta las teclas de volumen y brillo para mostrar el indicador de Orbit
/// en lugar del del sistema. Necesita permiso de Accesibilidad.
final class MediaKeyTap {
    /// Devuelve true si Orbit se encargó de la tecla (y se oculta el indicador del sistema).
    var handler: (@MainActor (MediaKey, Bool) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.isTrusted else { return false }
        let mask = CGEventMask(1) << CGEventMask(14) // NX_SYSDEFINED
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<MediaKeyTap>.fromOpaque(context).takeUnretainedValue()
                return me.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else { return false }
        tap = created
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// true = tragarse el evento
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type.rawValue == 14,
              let ns = NSEvent(cgEvent: event),
              ns.subtype.rawValue == 8 else { return false }
        let data = ns.data1
        let code = (data & 0xFFFF0000) >> 16
        let flags = data & 0x0000FFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0xA
        let key: MediaKey
        switch code {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 7: key = .mute
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        default: return false
        }
        let fine = ns.modifierFlags.contains(.option) && ns.modifierFlags.contains(.shift)
        guard let handler else { return false }
        if !isDown {
            // También nos tragamos el "soltar" de las teclas que manejamos.
            return owned.remove(code) != nil
        }
        let handled = MainActor.assumeIsolated { handler(key, fine) }
        if handled { owned.insert(code) }
        return handled
    }

    private var owned: Set<Int> = []
}
