import SwiftUI
import Combine

enum IslandPage: String, CaseIterable, Identifiable {
    case music, calendar, tray
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .tray: return "tray.full.fill"
        }
    }

    var title: String {
        switch self {
        case .music: return tr("Música", "Music")
        case .calendar: return tr("Calendario", "Calendar")
        case .tray: return tr("Bandeja", "Tray")
        }
    }
}

enum OutputKind: Equatable {
    case speaker, headphones, airpods, airpodsPro, airpodsMax, bluetooth, display, airplay

    var symbol: String {
        switch self {
        case .speaker: return "laptopcomputer"
        case .headphones: return "headphones"
        case .airpods: return "airpods"
        case .airpodsPro: return "airpodspro"
        case .airpodsMax: return "airpodsmax"
        case .bluetooth: return "hifispeaker.fill"
        case .display: return "display"
        case .airplay: return "airplayaudio"
        }
    }

    static func guess(name: String, bluetooth: Bool) -> OutputKind {
        let n = name.lowercased()
        if n.contains("airpods max") { return .airpodsMax }
        if n.contains("airpods pro") { return .airpodsPro }
        if n.contains("airpods") { return .airpods }
        if n.contains("beats") || n.contains("headphone") || n.contains("auricular") || n.contains("buds") { return .headphones }
        if bluetooth { return .bluetooth }
        return .speaker
    }
}

enum BatteryEvent: Equatable {
    case charging(Int)
    case unplugged(Int)
    case low(Int)
    case full
}

enum TransientKind: Equatable {
    case volume(level: Float, muted: Bool, output: OutputKind)
    case brightness(level: Float)
    case battery(BatteryEvent)
    case bluetooth(name: String, symbol: String, battery: Int?, connected: Bool)
    case lock(locked: Bool)
    case calendar(title: String, minutes: Int, color: Color)
    case tray(count: Int)
    case welcome
    case track(title: String, artist: String)

    var family: String {
        switch self {
        case .volume: return "volume"
        case .brightness: return "brightness"
        case .battery: return "battery"
        case .bluetooth: return "bluetooth"
        case .lock: return "lock"
        case .calendar: return "calendar"
        case .tray: return "tray"
        case .welcome: return "welcome"
        case .track: return "track"
        }
    }

    /// Color de la estela de luz.
    var tint: Color {
        switch self {
        case .volume: return .white
        case .brightness: return .orbitYellow
        case .battery(let event):
            switch event {
            case .low: return .orbitRed
            case .unplugged: return .white
            default: return .orbitGreen
            }
        case .bluetooth: return .orbitBlue
        case .lock(let locked): return locked ? .white : .orbitGreen
        case .calendar(_, _, let color): return color
        case .tray: return .orbitBlue
        case .welcome: return .orbitViolet
        case .track: return AccentStore.current
        }
    }

    /// Ancho de cada ala a los lados del notch.
    var wing: CGFloat {
        switch self {
        case .volume, .brightness: return Settings.shared.soundPercent ? 84 : 66
        case .battery(let event):
            switch event {
            case .charging, .full: return 92
            case .low: return 98
            case .unplugged: return 84
            }
        case .bluetooth: return 52
        case .lock: return 40
        case .calendar: return 80
        case .tray: return 64
        case .welcome: return 74
        case .track: return 46
        }
    }

    /// Altura extra debajo del notch (para un subtítulo).
    var extraHeight: CGFloat {
        switch self {
        case .calendar, .welcome: return 30
        case .track: return 46
        default: return 0
        }
    }
}

enum Presentation: Equatable {
    case hidden
    case idle
    case music
    case transient(TransientKind)
    case expanded(IslandPage)

    var key: String {
        switch self {
        case .hidden: return "hidden"
        case .idle: return "idle"
        case .music: return "music"
        case .transient(let kind): return "t." + kind.family
        case .expanded(let page): return "x." + page.rawValue
        }
    }

    var isExpanded: Bool {
        if case .expanded = self { return true }
        return false
    }

    var isResting: Bool {
        switch self {
        case .hidden, .idle: return true
        default: return false
        }
    }
}

struct IslandLayout: Equatable {
    var width: CGFloat
    var height: CGFloat
    var ear: CGFloat
    var bottom: CGFloat
    var topCorner: CGFloat

    var outerWidth: CGFloat { width + 2 * ear }
}

struct CometRequest: Equatable {
    var serial = 0
    var color: Color = .white
    var rainbow = false
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var metrics: NotchMetrics
    @Published var hovering = false
    @Published var expanded = false
    @Published var page: IslandPage = .music
    @Published private(set) var transient: TransientKind?
    @Published var liveMusic = false
    @Published var dragActive = false
    @Published var dropTargeted = false
    @Published var lyricsMode = false
    @Published var visibleWhenIdle = true
    @Published private(set) var comet = CometRequest()
    @Published var pressed = false
    @Published var calibrating = false

    let isPreview: Bool
    /// El agua del notch: tiene su propio ritmo de dibujo y no redibuja el resto de la isla.
    let liquid = LiquidField()
    private var dismissTask: Task<Void, Never>?

    init(metrics: NotchMetrics, isPreview: Bool = false) {
        self.metrics = metrics
        self.isPreview = isPreview
    }

    var presentation: Presentation {
        if dragActive { return .expanded(.tray) }
        if expanded { return .expanded(page) }
        if let transient { return .transient(transient) }
        if liveMusic { return .music }
        return (visibleWhenIdle || hovering) ? .idle : .hidden
    }

    /// Medidas actuales, incluido el pequeño "respiro" al pasar el cursor.
    var currentLayout: IslandLayout {
        let current = presentation
        var result = layout(for: current)
        if hovering && !current.isExpanded && current != .hidden && !isPreview {
            // Un respiro sutil, como la Dynamic Island cuando la rozas: no se abre de golpe.
            result.width += 10
            result.height += 2
            if !metrics.floating {
                result.ear = max(result.ear, 7)
                result.bottom = max(result.bottom, 12)
            }
        }
        return result
    }

    var pages: [IslandPage] {
        let s = Settings.shared
        var list: [IslandPage] = []
        if s.musicEnabled { list.append(.music) }
        if s.calendarEnabled { list.append(.calendar) }
        if s.trayEnabled { list.append(.tray) }
        return list.isEmpty ? [.music] : list
    }

    func show(_ kind: TransientKind, for duration: Double?) {
        let isNew = transient?.family != kind.family
        transient = kind
        if isNew && !expanded { fireComet(kind.tint) }
        dismissTask?.cancel()
        guard let duration else { return }
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.3, duration) * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.transient = nil
        }
    }

    func clearTransient() {
        dismissTask?.cancel()
        transient = nil
    }

    func fireComet(_ color: Color) {
        let settings = Settings.shared
        guard settings.comet else { return }
        let tint = settings.trailColor == .accent ? AccentStore.current : color
        comet = CometRequest(serial: comet.serial + 1, color: tint, rainbow: settings.trailColor == .rainbow)
    }

    func select(_ page: IslandPage) {
        guard pages.contains(page) else { return }
        self.page = page
    }

    func shiftPage(_ delta: Int) {
        let list = pages
        guard let index = list.firstIndex(of: page) else { page = list[0]; return }
        let next = index + delta
        guard next >= 0, next < list.count else { return }
        page = list[next]
    }

    // MARK: Medidas

    func layout(for presentation: Presentation) -> IslandLayout {
        let n = metrics.notchWidth
        let h = metrics.notchHeight
        let floating = metrics.floating

        let round = CGFloat(max(0.5, min(1.4, Settings.shared.roundness)))
        func compact(_ wing: CGFloat, extra: CGFloat = 0) -> IslandLayout {
            let tall = extra > 0
            return IslandLayout(width: n + 2 * wing,
                                height: h + extra,
                                ear: floating ? 0 : 7,
                                bottom: floating ? (tall ? 22 * round : h / 2) : (tall ? 20 : 12) * round,
                                topCorner: floating ? (tall ? 22 * round : h / 2) : 0)
        }

        switch presentation {
        case .hidden:
            return IslandLayout(width: n * 0.62, height: 0, ear: 0, bottom: 0, topCorner: floating ? 0 : 0)
        case .idle:
            if floating {
                return IslandLayout(width: n, height: h, ear: 0, bottom: h / 2, topCorner: h / 2)
            }
            return IslandLayout(width: n, height: h, ear: metrics.hasNotch ? 0 : 5,
                                bottom: metrics.hasNotch ? 10 : 9, topCorner: 0)
        case .music:
            return compact(max(h + 8, 40))
        case .transient(let kind):
            return compact(kind.wing, extra: kind.extraHeight)
        case .expanded(let page):
            let size = Settings.shared.islandSize
            let width: CGFloat
            switch size {
            case .compact: width = max(n + 2 * 104, 400)
            case .normal: width = max(n + 2 * 128, 452)
            case .large: width = max(n + 2 * 166, 524)
            }
            let extra: CGFloat
            switch page {
            case .music: extra = size == .compact ? 132 : 144
            case .calendar: extra = size == .compact ? 150 : 160
            case .tray: extra = size == .compact ? 122 : 130
            }
            return IslandLayout(width: width, height: h + extra, ear: floating ? 0 : 14,
                                bottom: 32 * round, topCorner: floating ? 32 * round : 0)
        }
    }

    var canvasSize: CGSize { metrics.canvasSize }
}
