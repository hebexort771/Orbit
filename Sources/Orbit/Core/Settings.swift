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
    case native, orbit, smooth, snappy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .native: return tr("Nativa", "Native")
        case .orbit: return tr("Órbita", "Orbit")
        case .smooth: return tr("Suave", "Smooth")
        case .snappy: return tr("Rápida", "Snappy")
        }
    }
    var subtitle: String {
        switch self {
        case .native: return tr("Como la Dynamic Island de Apple: crece desde el notch con un muelle preciso, sin exagerar", "Like Apple's Dynamic Island: grows out of the notch with a precise spring, never overdone")
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

enum LockStyle: String, CaseIterable, PrefValue, Identifiable {
    case widget, lyrics, cover, karaoke, card
    var id: String { rawValue }
    /// El widget deja la pantalla bloqueada de macOS tal cual (tu fondo, tu reloj) y solo añade el reproductor.
    var fullScreen: Bool { self != .widget }
    var title: String {
        switch self {
        case .widget: return tr("Widget", "Widget")
        case .lyrics: return tr("Letras", "Lyrics")
        case .cover: return tr("Portada", "Cover")
        case .karaoke: return tr("Karaoke", "Karaoke")
        case .card: return tr("Tarjeta", "Card")
        }
    }
    var subtitle: String {
        switch self {
        case .widget: return tr("Un reproductor de vidrio debajo del reloj, como una Actividad en vivo; tu fondo no cambia", "A glass player below the clock, like a Live Activity; your wallpaper stays")
        case .lyrics: return tr("Portada y controles a un lado, letra al otro, como Apple Music", "Cover and controls on one side, lyrics on the other, like Apple Music")
        case .cover: return tr("La portada grande al centro, con su reflejo", "A big centered cover with its reflection")
        case .karaoke: return tr("La letra enorme al centro y un reproductor mínimo", "Huge centered lyrics and a minimal player")
        case .card: return tr("Una tarjeta compacta que deja ver tu fondo", "A compact card that lets your wallpaper show")
        }
    }
    var next: LockStyle {
        let all = LockStyle.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

enum LockBackground: String, CaseIterable, PrefValue, Identifiable {
    case aurora, blurred, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aurora: return tr("Colores en movimiento", "Moving colors")
        case .blurred: return tr("Portada difuminada", "Blurred cover")
        case .dark: return tr("Oscuro", "Dark")
        }
    }
}

/// Dónde se dibuja el fondo de la música en la pantalla bloqueada.
enum LockLayer: String, CaseIterable, PrefValue, Identifiable {
    /// Los colores de la canción pasan a ser el fondo de pantalla mientras está bloqueada:
    /// el reloj, tu foto y la contraseña de macOS quedan encima.
    case wallpaper
    /// Orbit se dibuja encima de todo y pone su propio reloj, parecido al de macOS.
    case above
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wallpaper: return tr("Con el reloj de tu Mac", "With your Mac's clock")
        case .above: return tr("Encima de todo", "Above everything")
        }
    }
    var subtitle: String {
        switch self {
        case .wallpaper:
            return tr("Mientras está bloqueada, los colores de la canción se ponen como fondo de pantalla y el reloj, tu foto y la contraseña de macOS quedan encima. Al desbloquear vuelve tu fondo de siempre.",
                      "While locked, the song colors become your wallpaper and macOS draws its own clock, photo and password on top. Your usual wallpaper comes back when you unlock.")
        case .above:
            return tr("Orbit tapa la pantalla bloqueada y dibuja un reloj parecido al de macOS. Úsalo si la otra opción no funciona en tu Mac.",
                      "Orbit covers the lock screen and draws a clock similar to macOS. Use it if the other option doesn't work on your Mac.")
        }
    }
}

enum ClockStyle: String, CaseIterable, PrefValue, Identifiable {
    case rounded, classic, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rounded: return tr("Redondeado", "Rounded")
        case .classic: return tr("Clásico", "Classic")
        case .light: return tr("Fino", "Light")
        }
    }
}

enum TextAlign: String, CaseIterable, PrefValue, Identifiable {
    case leading, center
    var id: String { rawValue }
    var title: String {
        switch self {
        case .leading: return tr("Izquierda", "Left")
        case .center: return tr("Centro", "Center")
        }
    }
}

enum AccentMode: String, CaseIterable, PrefValue, Identifiable {
    case artwork, system, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .artwork: return tr("De la portada", "From artwork")
        case .system: return tr("Del sistema", "System")
        case .custom: return tr("Personalizado", "Custom")
        }
    }
}

enum IslandSize: String, CaseIterable, PrefValue, Identifiable {
    case compact, normal, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: return tr("Compacta", "Compact")
        case .normal: return tr("Normal", "Normal")
        case .large: return tr("Amplia", "Wide")
        }
    }
}

/// De qué está hecha la isla abierta y la tarjeta de la pantalla bloqueada.
enum IslandMaterial: String, CaseIterable, PrefValue, Identifiable {
    case black, glass
    var id: String { rawValue }
    var title: String {
        switch self {
        case .black: return tr("Negro", "Black")
        case .glass: return tr("Liquid Glass", "Liquid Glass")
        }
    }
    var subtitle: String {
        switch self {
        case .black: return tr("Negro puro, se funde con el notch de la MacBook", "Pure black that blends into the MacBook notch")
        case .glass: return tr("Vidrio que deja ver lo que hay detrás, como macOS Tahoe (en versiones anteriores, un vidrio esmerilado oscuro)",
                               "Glass that shows what's behind it, like macOS Tahoe (frosted dark glass on earlier versions)")
        }
    }
}

enum TrailColor: String, CaseIterable, PrefValue, Identifiable {
    case event, accent, rainbow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .event: return tr("Según el aviso", "Per alert")
        case .accent: return tr("Color de acento", "Accent color")
        case .rainbow: return tr("Arcoíris", "Rainbow")
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
    @Pref("notchWidthAdjust") var notchWidthAdjust = 0.0
    @Pref("notchHeightAdjust") var notchHeightAdjust = 0.0
    @Pref("haptics") var haptics = true
    @Pref("animationStyle2") var animationStyle: AnimationStyle = .native
    @Pref("animationSpeed") var animationSpeed = 1.0
    @Pref("comet") var comet = true
    @Pref("ambientGlow") var ambientGlow = true
    @Pref("glowIntensity") var glowIntensity = 0.7
    @Pref("accentMode") var accentMode: AccentMode = .artwork
    @Pref("customAccent") var customAccent = "#FF5C93"
    @Pref("trailColor") var trailColor: TrailColor = .event
    @Pref("islandSize2") var islandSize: IslandSize = .compact
    @Pref("roundness") var roundness = 1.0
    @Pref("islandOutline") var islandOutline = true
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
    @Pref("lockStyle3") var lockStyle: LockStyle = .lyrics
    @Pref("lockLayer") var lockLayer: LockLayer = .wallpaper
    @Pref("lockBackground2") var lockBackground: LockBackground = .blurred
    @Pref("lockMotion") var lockMotion = true
    @Pref("lockClock") var lockClock = true
    @Pref("lockClockStyle") var lockClockStyle: ClockStyle = .rounded
    @Pref("lockLyricsSize") var lockLyricsSize = 34.0
    @Pref("lockLyricsAlign") var lockLyricsAlign: TextAlign = .leading
    @Pref("lockLyricsBlur") var lockLyricsBlur = true
    @Pref("lockTilt2") var lockTilt = false
    @Pref("lockHintShown") var lockHintShown = false

    // Reproduciendo
    @Pref("musicEnabled") var musicEnabled = true
    @Pref("musicIdle") var musicIdle = 3.0
    @Pref("waveformStyle") var waveformStyle: WaveformStyle = .colored
    @Pref("compactWaveform") var compactWaveform = true
    @Pref("artworkFlip") var artworkFlip = true
    @Pref("hideWhenSourceActive") var hideWhenSourceActive = false
    @Pref("lyricsEnabled") var lyricsEnabled = true
    @Pref("lyricsOffset") var lyricsOffset = 0.0
    @Pref("lyricsEstimateWords") var lyricsEstimateWords = false
    @Pref("hdArtwork") var hdArtwork = true
    @Pref("liquidNotch3") var liquidNotch = true
    @Pref("islandMaterial") var islandMaterial: IslandMaterial = .black
    @Pref("trackPeek") var trackPeek = true

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
