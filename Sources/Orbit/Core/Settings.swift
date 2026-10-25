import Foundation
import Combine
import SwiftUI

// MARK: - Valores que se pueden guardar

protocol PrefValue {
    static func readPref(_ defaults: UserDefaults, _ key: String) -> Self?
    func writePref(_ defaults: UserDefaults, _ key: String)
}

extension Bool: PrefValue {
    static func readPref(_ defaults: UserDefaults, _ key: String) -> Bool? {
        (defaults.object(forKey: key) as? NSNumber)?.boolValue
    }
    func writePref(_ defaults: UserDefaults, _ key: String) { defaults.set(self, forKey: key) }
}

extension Double: PrefValue {
    static func readPref(_ defaults: UserDefaults, _ key: String) -> Double? {
        (defaults.object(forKey: key) as? NSNumber)?.doubleValue
    }
    func writePref(_ defaults: UserDefaults, _ key: String) { defaults.set(self, forKey: key) }
}

extension Int: PrefValue {
    static func readPref(_ defaults: UserDefaults, _ key: String) -> Int? {
        (defaults.object(forKey: key) as? NSNumber)?.intValue
    }
    func writePref(_ defaults: UserDefaults, _ key: String) { defaults.set(self, forKey: key) }
}

extension String: PrefValue {
    static func readPref(_ defaults: UserDefaults, _ key: String) -> String? {
        defaults.string(forKey: key)
    }
    func writePref(_ defaults: UserDefaults, _ key: String) { defaults.set(self, forKey: key) }
}

extension PrefValue where Self: RawRepresentable, Self.RawValue == String {
    static func readPref(_ defaults: UserDefaults, _ key: String) -> Self? {
        defaults.string(forKey: key).flatMap { Self(rawValue: $0) }
    }
    func writePref(_ defaults: UserDefaults, _ key: String) { defaults.set(rawValue, forKey: key) }
}

/// Preferencia guardada en UserDefaults que avisa a SwiftUI cuando cambia.
@propertyWrapper
struct Pref<Value: PrefValue> {
    let key: String
    let defaultValue: Value

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
    }

    @available(*, unavailable, message: "Pref solo se usa dentro de Settings")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    static subscript(
        _enclosingInstance instance: Settings,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Settings, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Settings, Pref<Value>>
    ) -> Value {
        get {
            let pref = instance[keyPath: storageKeyPath]
            return Value.readPref(instance.defaults, pref.key) ?? pref.defaultValue
        }
        set {
            instance.objectWillChange.send()
            let pref = instance[keyPath: storageKeyPath]
            newValue.writePref(instance.defaults, pref.key)
        }
    }
}

// MARK: - Opciones

enum DisplayChoice: String, CaseIterable, PrefValue, Identifiable {
    case builtin, main, cursor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .builtin: return tr("Pantalla integrada", "Built-in display")
        case .main: return tr("Pantalla principal", "Main display")
        case .cursor: return tr("Seguir al cursor", "Follow the cursor")
        }
    }
}

enum VirtualStyle: String, CaseIterable, PrefValue, Identifiable {
    case notch, floating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notch: return tr("Notch virtual", "Virtual notch")
        case .floating: return tr("Isla flotante", "Floating island")
        }
    }
}

enum VirtualVisibility: String, CaseIterable, PrefValue, Identifiable {
    case always, activity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .always: return tr("Siempre visible", "Always visible")
        case .activity: return tr("Solo con actividad", "Only with activity")
        }
    }
}

enum AnimationStyle: String, CaseIterable, PrefValue, Identifiable {
    case orbit, smooth, snappy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .orbit: return tr("Órbita", "Orbit")
        case .smooth: return tr("Suave", "Smooth")
        case .snappy: return tr("Rápida", "Snappy")
        }
    }
    var subtitle: String {
        switch self {
        case .orbit: return tr("Líquida, con rebote y estela de luz", "Liquid, bouncy, with a light trail")
        case .smooth: return tr("Elegante y sin rebote", "Elegant, no bounce")
        case .snappy: return tr("Directa y veloz", "Quick and direct")
        }
    }
}

enum WaveformStyle: String, CaseIterable, PrefValue, Identifiable {
    case mono, colored, gradient
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mono: return tr("Monocromo", "Monochrome")
        case .colored: return tr("Color", "Colored")
        case .gradient: return tr("Degradado", "Gradient")
        }
    }
}

enum BarStyle: String, CaseIterable, PrefValue, Identifiable {
    case white, accent, segments
    var id: String { rawValue }
    var title: String {
        switch self {
        case .white: return tr("Blanco", "White")
        case .accent: return tr("Acento", "Accent")
        case .segments: return tr("Segmentos", "Segments")
        }
    }
}

enum HUDAnimation: String, CaseIterable, PrefValue, Identifiable {
    case smooth, fast, instant
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smooth: return tr("Suave", "Smooth")
        case .fast: return tr("Rápida", "Fast")
        case .instant: return tr("Instantánea", "Instant")
        }
    }
    var animation: Animation? {
        switch self {
        case .smooth: return .spring(response: 0.38, dampingFraction: 0.78)
        case .fast: return .spring(response: 0.2, dampingFraction: 0.9)
        case .instant: return nil
        }
    }
}

enum AppLanguage: String, CaseIterable, PrefValue, Identifiable {
    case system, es, en
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return tr("Como el sistema", "Same as system")
        case .es: return "Español"
        case .en: return "English"
        }
    }
}

// MARK: - Ajustes

final class Settings: ObservableObject {
    static let shared = Settings()
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // General
    @Pref("display") var display: DisplayChoice = .builtin
    @Pref("virtualStyle") var virtualStyle: VirtualStyle = .notch
    @Pref("virtualVisibility") var virtualVisibility: VirtualVisibility = .always
    @Pref("hoverToOpen") var hoverToOpen = true
    @Pref("hoverDelay") var hoverDelay = 0.12
    @Pref("haptics") var haptics = true
    @Pref("animationStyle") var animationStyle: AnimationStyle = .orbit
    @Pref("animationSpeed") var animationSpeed = 1.0
    @Pref("comet") var comet = true
    @Pref("ambientGlow") var ambientGlow = true
    @Pref("language") var language: AppLanguage = .system
    @Pref("menuBarIcon") var menuBarIcon = true
    @Pref("swipePages") var swipePages = true
    @Pref("welcomeShown") var welcomeShown = false

    // Batería
    @Pref("batteryEnabled") var batteryEnabled = true
    @Pref("batteryPercent") var batteryPercent = true
    @Pref("batteryLow") var batteryLow = true
    @Pref("batteryFull") var batteryFull = true
    @Pref("batteryDuration") var batteryDuration = 2.6

    // Conectividad
    @Pref("bluetoothEnabled") var bluetoothEnabled = true
    @Pref("bluetoothBattery") var bluetoothBattery = true
    @Pref("bluetoothDisconnect") var bluetoothDisconnect = false
    @Pref("bluetoothDuration") var bluetoothDuration = 2.6

    // Pantalla (brillo)
    @Pref("brightnessEnabled") var brightnessEnabled = true

    // Sonido
    @Pref("soundEnabled") var soundEnabled = true
    @Pref("soundShowDevice") var soundShowDevice = false
    @Pref("soundDuration") var soundDuration = 1.5
    @Pref("soundBarStyle") var soundBarStyle: BarStyle = .white
    @Pref("soundAnimation") var soundAnimation: HUDAnimation = .smooth
    @Pref("soundPercent") var soundPercent = true
    @Pref("replaceSystemHUD") var replaceSystemHUD = false

    // Bloqueo
    @Pref("lockEnabled") var lockEnabled = true
    @Pref("lockScreenMedia") var lockScreenMedia = true
    @Pref("lockScreenLyrics") var lockScreenLyrics = true

    // Reproduciendo
    @Pref("musicEnabled") var musicEnabled = true
    @Pref("musicIdle") var musicIdle = 3.0
    @Pref("waveformStyle") var waveformStyle: WaveformStyle = .colored
    @Pref("compactWaveform") var compactWaveform = true
    @Pref("artworkFlip") var artworkFlip = true
    @Pref("hideWhenSourceActive") var hideWhenSourceActive = false
    @Pref("lyricsEnabled") var lyricsEnabled = true
    @Pref("artworkAccent") var artworkAccent = true

    // Calendario
    @Pref("calendarEnabled") var calendarEnabled = true
    @Pref("calendarAlerts") var calendarAlerts = true
    @Pref("calendarAlertMinutes") var calendarAlertMinutes = 5

    // Bandeja
    @Pref("trayEnabled") var trayEnabled = true
    @Pref("trayAirDrop") var trayAirDrop = true
    @Pref("trayOpenOnDrag") var trayOpenOnDrag = true
    @Pref("trayPaths") var trayPaths = ""

    func resetAll() {
        if let domain = Bundle.main.bundleIdentifier {
            objectWillChange.send()
            defaults.removePersistentDomain(forName: domain)
        }
    }
}
