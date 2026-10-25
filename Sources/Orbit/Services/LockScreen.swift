import AppKit
import SwiftUI

/// Un espacio de ventanas por encima de la pantalla de bloqueo (SkyLight, privado).
final class SkyLightSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let connection: Int32
    private let space: Int32
    private let addWindows: AddWindows

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let mainSymbol = dlsym(handle, "SLSMainConnectionID"),
              let createSymbol = dlsym(handle, "SLSSpaceCreate"),
              let levelSymbol = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let showSymbol = dlsym(handle, "SLSShowSpaces"),
              let addSymbol = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return nil }
        let main = unsafeBitCast(mainSymbol, to: MainConnection.self)
        let create = unsafeBitCast(createSymbol, to: SpaceCreate.self)
        let setLevel = unsafeBitCast(levelSymbol, to: SpaceSetLevel.self)
        let show = unsafeBitCast(showSymbol, to: ShowSpaces.self)
        addWindows = unsafeBitCast(addSymbol, to: AddWindows.self)
        connection = main()
        space = create(connection, 1, 0)
        _ = setLevel(connection, space, 400)
        _ = show(connection, [NSNumber(value: space)] as CFArray)
    }

    func adopt(_ window: NSWindow) {
        _ = addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }
}

final class LockPanel: NSPanel {
    init(frame: NSRect, interactive: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        level = NSWindow.Level(rawValue: Int(Int32.max - 2))
        canBecomeVisibleWithoutLogin = true
        isReleasedWhenClosed = false
        ignoresMouseEvents = !interactive
        acceptsMouseMovedEvents = interactive
        animationBehavior = .none
    }

    // Nunca toma el teclado: lo que escribas sigue yendo al campo de contraseña.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Estado compartido

@MainActor
final class LockScreenState: ObservableObject {
    enum Phase { case hidden, shown, leaving }

    @Published var phase: Phase = .hidden
    @Published var style: LockStyle = Settings.shared.lockStyle
    @Published var badge: LockStyle?
    @Published var hint = false
    private var badgeTask: Task<Void, Never>?

    func cycle() {
        let next = style.next
        withAnimation(.spring(response: 0.66, dampingFraction: 0.84)) { style = next }
        Settings.shared.lockStyle = next
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.25)) {
            hint = false
            badge = next
        }
        badgeTask?.cancel()
        badgeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) { self?.badge = nil }
        }
    }

    func syncStyle() {
        if style != Settings.shared.lockStyle { style = Settings.shared.lockStyle }
    }
}

// MARK: - Controlador

/// Candado al bloquear/desbloquear y reproductor a pantalla completa en la pantalla de bloqueo.
@MainActor
final class LockScreenController {
    private let services: Services
    private let islandModel: IslandModel
    let state = LockScreenState()
    private var islandPanel: LockPanel?
    private var screenPanel: LockPanel?
    private var previewPanel: LockPanel?
    private var previewMonitor: Any?
    private var space: SkyLightSpace?
    private var triedSpace = false
    private var hideTask: Task<Void, Never>?
    private(set) var isLocked = false
    var onChange: ((Bool) -> Void)?

    init(services: Services) {
        self.services = services
        let screen = IslandController.preferredScreen()
        islandModel = IslandModel(metrics: NotchMetrics.measure(screen, style: Settings.shared.virtualStyle))
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked() }
        }
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unlocked() }
        }
    }

    private func prepareSpace() {
        guard !triedSpace else { return }
        triedSpace = true
        space = SkyLightSpace()
    }

    private func locked() {
        isLocked = true
        onChange?(true)
        closePreview()
        let settings = Settings.shared
        let wantsMedia = settings.lockScreenMedia && settings.musicEnabled && services.media.hasTrack
        guard settings.lockEnabled || wantsMedia else { return }
        prepareSpace()
        guard let space else { return }
        hideTask?.cancel()

        let screen = IslandController.preferredScreen()
        let metrics = NotchMetrics.measure(screen, style: settings.virtualStyle)
        islandModel.metrics = metrics
        islandModel.visibleWhenIdle = true

        if wantsMedia {
            let panel = screenPanel ?? makeScreenPanel(size: screen.frame.size)
            panel.setFrame(screen.frame, display: true)
            (panel.contentView as? FirstClickHostingView<AnyView>)?.rootView = screenRoot(size: screen.frame.size, preview: false)
            panel.orderFrontRegardless()
            space.adopt(panel)
            state.syncStyle()
            state.phase = .hidden
            if !settings.lockHintShown {
                settings.lockHintShown = true
                state.hint = true
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 80_000_000)
                self?.state.phase = .shown
            }
        }

        if settings.lockEnabled {
            let panel = islandPanel ?? makeIslandPanel()
            panel.setFrame(IslandController.frame(for: metrics), display: true)
            panel.orderFrontRegardless()
            space.adopt(panel)
            islandModel.clearTransient()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 150_000_000)
                self?.islandModel.show(.lock(locked: true), for: nil)
            }
        }
    }

    private func unlocked() {
        isLocked = false
        onChange?(false)
        hideTask?.cancel()
        if screenPanel?.isVisible == true { state.phase = .leaving }
        if islandPanel?.isVisible == true && Settings.shared.lockEnabled {
            islandModel.show(.lock(locked: false), for: nil)
        }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard let self, !Task.isCancelled else { return }
            self.islandModel.clearTransient()
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self.islandPanel?.orderOut(nil)
            self.screenPanel?.orderOut(nil)
            self.state.phase = .hidden
        }
    }

    private func screenRoot(size: CGSize, preview: Bool) -> AnyView {
        AnyView(LockScreenView(state: state, size: size, preview: preview).services(services))
    }

    private func makeIslandPanel() -> LockPanel {
        let panel = LockPanel(frame: IslandController.frame(for: islandModel.metrics), interactive: false)
        let view = IslandCanvas(model: islandModel).services(services)
        let hosting = FirstClickHostingView(rootView: AnyView(view))
        hosting.sizingOptions = []
        panel.contentView = hosting
        islandPanel = panel
        return panel
    }

    private func makeScreenPanel(size: CGSize) -> LockPanel {
        let panel = LockPanel(frame: NSRect(origin: .zero, size: size), interactive: true)
        let hosting = FirstClickHostingView(rootView: screenRoot(size: size, preview: false))
        hosting.sizingOptions = []
        panel.contentView = hosting
        screenPanel = panel
        return panel
    }

    // MARK: Vista previa a pantalla completa (desde Ajustes)

    func preview() {
        guard services.media.hasTrack || services.isDemo else { return }
        closePreview()
        let screen = NSScreen.main ?? IslandController.preferredScreen()
        let panel = LockPanel(frame: screen.frame, interactive: true)
        panel.level = .screenSaver
        let hosting = FirstClickHostingView(rootView: screenRoot(size: screen.frame.size, preview: true))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        previewPanel = panel
        state.syncStyle()
        state.phase = .hidden
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            self?.state.phase = .shown
        }
        previewMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.closePreview(animated: true) }
            return nil
        }
    }

    func closePreview(animated: Bool = false) {
        if let monitor = previewMonitor { NSEvent.removeMonitor(monitor) }
        previewMonitor = nil
        guard let panel = previewPanel else { return }
        previewPanel = nil
        guard animated else { panel.orderOut(nil); return }
        state.phase = .leaving
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            panel.orderOut(nil)
        }
    }
}

// MARK: - Medidas de cada estilo

struct LockLayout {
    enum Card { case under, cover, mini, full }

    var art: CGRect
    var artRadius: CGFloat
    var card: CGRect
    var cardKind: Card
    var cardRadius: CGFloat
    var lyrics: CGRect?
    var lyricsSize: CGFloat
    var lyricsAlign: TextAlign
    var lyricsAnchor: CGFloat
    var reflection: Bool
    var clockY: CGFloat
    var badgeY: CGFloat
    var effective: LockStyle

    init(style: LockStyle, size: CGSize, hasLyrics: Bool, settings: Settings) {
        let W = size.width, H = size.height
        let top = H * 0.31
        let floor = H * 0.80
        var style = style
        if !hasLyrics && (style == .lyrics || style == .karaoke) { style = .cover }
        effective = style
        clockY = H * 0.155
        badgeY = H * 0.252
        reflection = false
        lyrics = nil
        lyricsSize = settings.lockLyricsSize
        lyricsAlign = settings.lockLyricsAlign
        lyricsAnchor = 0.36

        switch style {
        case .lyrics:
            let side = min(W * 0.22, H * 0.34)
            let cx = W * 0.285
            art = CGRect(x: cx - side / 2, y: top, width: side, height: side)
            artRadius = side * 0.07
            card = CGRect(x: art.minX - 4, y: art.maxY + 18, width: side + 8, height: 132)
            cardKind = .under
            cardRadius = 24
            let x = W * 0.47
            lyrics = CGRect(x: x, y: top - H * 0.03, width: min(W * 0.42, 720), height: floor - top + H * 0.03)
        case .cover:
            let side = min(W * 0.23, H * 0.29)
            art = CGRect(x: W / 2 - side / 2, y: top - H * 0.04, width: side, height: side)
            artRadius = side * 0.06
            let cw = max(side + 90, 400)
            card = CGRect(x: W / 2 - cw / 2, y: art.maxY + side * 0.3, width: cw, height: 156)
            cardKind = .cover
            cardRadius = 28
            reflection = true
        case .karaoke:
            let pill = min(600, W * 0.5)
            card = CGRect(x: W / 2 - pill / 2, y: floor - 82, width: pill, height: 82)
            art = CGRect(x: card.minX + 13, y: card.minY + 13, width: 56, height: 56)
            artRadius = 12
            cardKind = .mini
            cardRadius = 30
            lyrics = CGRect(x: W * 0.12, y: top - H * 0.05, width: W * 0.76, height: card.minY - 24 - (top - H * 0.05))
            lyricsSize = settings.lockLyricsSize * 1.45
            lyricsAlign = .center
            lyricsAnchor = 0.4
        case .card:
            let cw: CGFloat = 420
            let ch: CGFloat = hasLyrics ? 318 : 222
            card = CGRect(x: W / 2 - cw / 2, y: H * 0.38, width: cw, height: ch)
            art = CGRect(x: card.minX + 22, y: card.minY + 22, width: 68, height: 68)
            artRadius = 15
            cardKind = .full
            cardRadius = 32
            if hasLyrics {
                lyrics = CGRect(x: card.minX + 22, y: card.minY + 222, width: cw - 44, height: 82)
                lyricsSize = 17
                lyricsAlign = .center
                lyricsAnchor = 0.5
            }
        }
    }
}

// MARK: - La pantalla

struct LockScreenView: View {
    @ObservedObject var state: LockScreenState
    let size: CGSize
    var preview = false
    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared
    @Environment(\.orbitStatic) private var isStatic
    @State private var tilt: CGSize = .zero

    private var morph: Animation { .spring(response: 0.66, dampingFraction: 0.84) }

    var body: some View {
        let shown = state.phase == .shown || isStatic
        let leaving = state.phase == .leaving
        let hasLyrics = settings.lockScreenLyrics && settings.lyricsEnabled && !media.lyrics.isEmpty
        let layout = LockLayout(style: state.style, size: size, hasLyrics: hasLyrics, settings: settings)

        ZStack(alignment: .topLeading) {
            LockBackdrop(size: size)
                .opacity(shown ? 1 : 0)
                .animation(.easeInOut(duration: leaving ? 0.75 : 1.0), value: state.phase)

            if settings.lockClock {
                LockClock(height: size.height)
                    .frame(width: size.width)
                    .position(x: size.width / 2, y: layout.clockY)
                    .modifier(Reveal(phase: state.phase, delay: 0.05, travel: -24, isStatic: isStatic))
            }

            if let track = media.track {
                if let rect = layout.lyrics {
                    LockLyrics(size: rect.size, fontSize: layout.lyricsSize, align: layout.lyricsAlign,
                               anchor: layout.lyricsAnchor, compact: layout.cardKind == .full)
                        .id(track.key)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .modifier(Reveal(phase: state.phase, delay: 0.32, travel: 30, isStatic: isStatic))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                LockCard(kind: layout.cardKind, track: track, size: layout.card.size, radius: layout.cardRadius,
                         artWidth: layout.art.width)
                    .frame(width: layout.card.width, height: layout.card.height)
                    .position(x: layout.card.midX, y: layout.card.midY)
                    .modifier(Reveal(phase: state.phase, delay: 0.22, travel: 34, isStatic: isStatic))

                LockArtwork(rect: leaving ? notchRect : layout.art,
                            radius: leaving ? 6 : layout.artRadius,
                            reflection: layout.reflection && !leaving,
                            tilt: settings.lockTilt ? tilt : .zero,
                            shown: shown,
                            leaving: leaving,
                            onTap: { state.cycle() })
                    .animation(leaving ? .spring(response: 0.75, dampingFraction: 0.86) : morph.delay(shown ? 0.12 : 0),
                               value: state.phase)
            }

            badge(layout)

            if preview && state.phase == .shown {
                Text(tr("Pulsa Esc para salir de la vista previa", "Press Esc to exit the preview"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .position(x: size.width / 2, y: 22)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(morph, value: state.style)
        .animation(morph, value: hasLyrics)
        .environment(\.colorScheme, .dark)
        .onContinuousHover { phase in
            guard settings.lockTilt else { return }
            switch phase {
            case .active(let point):
                let next = CGSize(width: (point.x / max(1, size.width) - 0.5) * 2, height: (point.y / max(1, size.height) - 0.5) * 2)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { tilt = next }
            case .ended:
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { tilt = .zero }
            }
        }
    }

    /// Hacia donde vuela la portada al desbloquear: el notch.
    private var notchRect: CGRect {
        CGRect(x: size.width / 2 - 11, y: 6, width: 22, height: 22)
    }

    @ViewBuilder
    private func badge(_ layout: LockLayout) -> some View {
        if let style = state.badge {
            Label(style.title, systemImage: LockStylePicture.symbol(style))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2)))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .position(x: layout.art.midX, y: layout.art.midY)
                .transition(.modifier(active: BlurFade(progress: 0, lift: 10), identity: BlurFade(progress: 1, lift: 10)))
                .id(style)
        } else if state.hint && state.phase == .shown {
            Label(tr("Toca la portada para cambiar el estilo", "Click the artwork to change the style"), systemImage: "hand.tap")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .position(x: size.width / 2, y: layout.badgeY)
                .transition(.opacity)
        }
    }
}

/// Entrada y salida de cada pieza: aparece desde un desenfoque y al salir sube.
struct Reveal: ViewModifier {
    let phase: LockScreenState.Phase
    let delay: Double
    let travel: CGFloat
    let isStatic: Bool

    func body(content: Content) -> some View {
        let shown = phase == .shown || isStatic
        let leaving = phase == .leaving
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 14)
            .offset(y: shown ? 0 : (leaving ? -travel : travel))
            .scaleEffect(shown ? 1 : 0.96)
            .animation(shown ? .spring(response: 0.75, dampingFraction: 0.84).delay(delay)
                             : .easeIn(duration: 0.35), value: phase)
    }
}

// MARK: - Fondo

struct LockBackdrop: View {
    let size: CGSize
    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared
    @Environment(\.orbitStatic) private var isStatic

    private var colors: [Color] {
        let fallback = [Color(red: 0.24, green: 0.12, blue: 0.42), Color(red: 0.5, green: 0.12, blue: 0.36),
                        Color(red: 0.1, green: 0.16, blue: 0.4)]
        var list = media.palette.isEmpty ? fallback : media.palette
        while list.count < 3 { list.append(list[list.count - 1]) }
        return list
    }

    var body: some View {
        ZStack {
            Color.black
            ZStack {
                switch settings.lockBackground {
                case .aurora: aurora
                case .blurred: blurred
                case .dark: dark
                }
            }
            .id(media.artworkSerial)
            .transition(.opacity.animation(.easeInOut(duration: 1.2)))
            // Viñeta para que el texto siempre se lea
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center,
                           startRadius: min(size.width, size.height) * 0.3, endRadius: max(size.width, size.height) * 0.8)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        // Abajo se desvanece para dejar ver tu foto y el campo de contraseña.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.74),
                                     .init(color: .black.opacity(0.35), location: 0.86), .init(color: .clear, location: 0.97)],
                             startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }

    private var diagonal: CGFloat { (size.width * size.width + size.height * size.height).squareRoot() }

    private var aurora: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !settings.lockMotion || isStatic)) { timeline in
            let t = isStatic ? 14 : timeline.date.timeIntervalSinceReferenceDate
            let c = colors
            ZStack {
                c[0]
                if let soft = media.softArtwork {
                    Image(nsImage: soft)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: diagonal * 1.2, height: diagonal * 1.2)
                        .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 3600) * 3.5))
                        .opacity(0.72)
                    Image(nsImage: soft)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: diagonal * 0.85, height: diagonal * 0.85)
                        .scaleEffect(x: -1, y: 1)
                        .rotationEffect(.degrees(90 - t.truncatingRemainder(dividingBy: 3600) * 5))
                        .blendMode(.screen)
                        .opacity(0.38)
                }
                ForEach(0..<3, id: \.self) { index in
                    blob(c[index], index: index, t: t)
                }
                Color.black.opacity(0.4)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func blob(_ color: Color, index: Int, t: Double) -> some View {
        let speeds: [(Double, Double, Double)] = [(0.11, 0.07, 0), (0.08, 0.13, 2.1), (0.14, 0.09, 4.2)]
        let s = speeds[index % speeds.count]
        let r = max(size.width, size.height) * (0.42 + 0.06 * Double(index))
        let x = size.width * (0.5 + 0.34 * cos(t * s.0 + s.2))
        let y = size.height * (0.5 + 0.3 * sin(t * s.1 + s.2 * 1.3))
        return Circle()
            .fill(RadialGradient(colors: [color.opacity(0.9), color.opacity(0)], center: .center, startRadius: 0, endRadius: r))
            .frame(width: r * 2, height: r * 2)
            .position(x: x, y: y)
            .blendMode(.plusLighter)
            .opacity(0.4)
    }

    private var blurred: some View {
        ZStack {
            if let soft = media.softArtwork {
                Image(nsImage: soft)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 30)
                    .saturation(1.25)
            } else {
                colors[0]
            }
            Color.black.opacity(0.38)
        }
    }

    private var dark: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.03)
            RadialGradient(colors: [colors[0].opacity(0.55), .clear], center: UnitPoint(x: 0.3, y: 0.5),
                           startRadius: 0, endRadius: size.width * 0.45)
        }
    }
}

// MARK: - Reloj

struct LockClock: View {
    let height: CGFloat
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            VStack(spacing: height * 0.004) {
                Text(dateText(timeline.date))
                    .font(.system(size: max(15, height * 0.022), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(timeText(timeline.date))
                    .font(timeFont)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.96), .white.opacity(0.72)],
                                                    startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText())
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            }
        }
    }

    private var timeFont: Font {
        let size = max(64, height * 0.115)
        switch settings.lockClockStyle {
        case .rounded: return .system(size: size, weight: .bold, design: .rounded)
        case .classic: return .system(size: size, weight: .semibold, design: .default)
        case .light: return .system(size: size, weight: .thin, design: .default)
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
            .replacingOccurrences(of: " a. m.", with: "")
            .replacingOccurrences(of: " p. m.", with: "")
            .replacingOccurrences(of: " AM", with: "")
            .replacingOccurrences(of: " PM", with: "")
    }
}

// MARK: - Portada

struct LockArtwork: View {
    let rect: CGRect
    let radius: CGFloat
    let reflection: Bool
    let tilt: CGSize
    var shown = true
    var leaving = false
    var onTap: () -> Void = {}
    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let glow = media.palette.first ?? media.accent
        let side = rect.width
        ZStack {
            if reflection {
                art(side)
                    .scaleEffect(x: 1, y: -1)
                    .mask(LinearGradient(colors: [.black.opacity(0.9), .clear], startPoint: .top,
                                         endPoint: UnitPoint(x: 0.5, y: 0.28)))
                    .opacity(0.3)
                    .blur(radius: 1.5)
                    .offset(y: side + 6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            art(side)
                .overlay {
                    // Brillo de vidrio que sigue la inclinación
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.16), .white.opacity(0)],
                                   startPoint: UnitPoint(x: 0.1 + tilt.width * 0.3, y: 0),
                                   endPoint: UnitPoint(x: 0.9 + tilt.width * 0.3, y: 1))
                        .blendMode(.plusLighter)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .allowsHitTesting(false)
                }
                .shadow(color: glow.opacity(0.55), radius: side * 0.16, y: side * 0.08)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
        }
        .scaleEffect(media.isPlaying ? 1 : 0.86)
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: media.isPlaying)
        .rotation3DEffect(.degrees(Double(-tilt.height) * 7), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(Double(tilt.width) * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .opacity(leaving ? 0 : (shown ? 1 : 0))
        .scaleEffect(shown || leaving ? 1 : 0.72)
        .blur(radius: shown || leaving ? 0 : 18)
        .frame(width: rect.width, height: rect.height)
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .onTapGesture { onTap() }
        .help(tr("Toca para cambiar el estilo", "Click to change the style"))
        .position(x: rect.midX, y: rect.midY)
    }

    private func art(_ side: CGFloat) -> some View {
        ZStack {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .id(media.artworkSerial)
                    .transition(settings.artworkFlip ? .cardFlip : .opacity)
            } else {
                LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: side * 0.36, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Tarjeta de controles

struct LockCard: View {
    let kind: LockLayout.Card
    let track: TrackInfo
    let size: CGSize
    let radius: CGFloat
    let artWidth: CGFloat
    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(kind == .full ? 0.1 : 0.085))
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.black.opacity(kind == .full ? 0.35 : 0.12))
                )
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            content
                .id(kind)
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .under:
            VStack(spacing: 9) {
                VStack(spacing: 2) {
                    Text(track.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(track.artist).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                MediaProgress(accent: .white)
                MediaControls(accent: media.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        case .cover:
            VStack(spacing: 10) {
                VStack(spacing: 3) {
                    Text(track.title).font(.system(size: 22, weight: .bold)).lineLimit(1)
                    Text(track.artist).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                }
                MediaProgress(accent: .white)
                MediaControls(accent: media.accent, big: true)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        case .mini:
            HStack(spacing: 14) {
                Color.clear.frame(width: artWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(track.artist).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Waveform(playing: media.isPlaying, style: settings.waveformStyle, color: media.accent, bars: 5, barWidth: 3)
                    .frame(width: 26, height: 20)
                HStack(spacing: 4) {
                    Button { media.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 17, weight: .semibold)) }
                        .buttonStyle(OrbitButtonStyle(size: 36))
                    Button { media.togglePlay() } label: {
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(OrbitButtonStyle(size: 42))
                    Button { media.next() } label: { Image(systemName: "forward.fill").font(.system(size: 17, weight: .semibold)) }
                        .buttonStyle(OrbitButtonStyle(size: 36))
                }
            }
            .padding(.leading, 13)
            .padding(.trailing, 16)
        case .full:
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    Color.clear.frame(width: artWidth, height: artWidth)
                    VStack(alignment: .leading, spacing: 3) {
                        MarqueeText(text: track.title, size: 17, weight: .bold, width: max(80, size.width - artWidth - 44 - 50))
                        Text(track.artist).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Waveform(playing: media.isPlaying, style: settings.waveformStyle, color: media.accent, bars: 5, barWidth: 3)
                        .frame(width: 28, height: 24)
                }
                MediaProgress(accent: .white)
                MediaControls(accent: media.accent, big: true)
                Spacer(minLength: 0)
            }
            .padding(22)
        }
    }
}

// MARK: - Letras al estilo Apple Music

enum LyricsMetrics {
    nonisolated(unsafe) private static var cache: [String: CGFloat] = [:]

    static func height(_ text: String, size: CGFloat, width: CGFloat) -> CGFloat {
        let key = "\(Int(size * 10))|\(Int(width))|\(text)"
        if let hit = cache[key] { return hit }
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let shown = text.isEmpty ? "♪" : text
        let rect = (shown as NSString).boundingRect(with: NSSize(width: max(10, width), height: .greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                    attributes: [.font: font])
        let value = ceil(rect.height) + 2
        if cache.count > 4000 { cache.removeAll() }
        cache[key] = value
        return value
    }
}

struct LockLyrics: View {
    let size: CGSize
    let fontSize: CGFloat
    let align: TextAlign
    var anchor: CGFloat = 0.36
    var compact = false
    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let time = media.elapsed(at: timeline.date)
            let current = media.currentLyricIndex(at: time) ?? -1
            lines(time: time, current: current)
        }
        .frame(width: size.width, height: size.height)
        .mask(
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: compact ? 0.22 : 0.1),
                                   .init(color: .black, location: compact ? 0.78 : 0.82), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
    }

    private func lines(time: Double, current: Int) -> some View {
        let lyrics = media.lyrics
        let gap = fontSize * (compact ? 0.35 : 0.55)
        let heights = lyrics.map { LyricsMetrics.height($0.text, size: fontSize, width: size.width) }
        var ys: [CGFloat] = []
        var y: CGFloat = 0
        for h in heights { ys.append(y); y += h + gap }
        let focus = max(0, current)
        let focusHeight = heights.isEmpty ? 0 : heights[min(focus, heights.count - 1)]
        let base = size.height * anchor - (ys.isEmpty ? 0 : ys[min(focus, ys.count - 1)]) - focusHeight / 2
        let first = max(0, focus - (compact ? 1 : 4))
        let last = min(lyrics.count - 1, focus + (compact ? 2 : 8))
        let textAlign: TextAlignment = align == .center ? .center : .leading
        let frameAlign: Alignment = align == .center ? .top : .topLeading

        return ZStack(alignment: frameAlign) {
            if current < 0, let firstLine = lyrics.first, firstLine.time > 2.5 {
                LyricDots(progress: time / firstLine.time, size: fontSize)
                    .frame(width: size.width, alignment: align == .center ? .center : .leading)
                    .offset(y: size.height * anchor - fontSize)
                    .transition(.opacity)
            }
            if !lyrics.isEmpty && last >= first {
                ForEach(first...last, id: \.self) { index in
                    let line = lyrics[index]
                    let next = index + 1 < lyrics.count ? lyrics[index + 1].time : line.time + 6
                    let progress = max(0, min(1, (time - line.time) / max(0.5, next - line.time)))
                    let distance = abs(index - current)
                    let isCurrent = index == current
                    Group {
                        if line.text.isEmpty || line.text == "♪" {
                            LyricDots(progress: isCurrent ? progress : 0, size: fontSize)
                                .opacity(isCurrent ? 1 : 0.35)
                        } else {
                            LyricRow(text: line.text, size: fontSize, current: isCurrent, distance: distance,
                                     progress: progress, singleLine: heights[index] < fontSize * 1.5,
                                     blur: settings.lockLyricsBlur, align: textAlign)
                        }
                    }
                    .frame(width: size.width, alignment: align == .center ? .center : .leading)
                    .offset(y: base + ys[index])
                    .animation(.spring(response: 0.7, dampingFraction: 0.86)
                        .delay(index >= current ? Double(index - max(current, 0)) * 0.045 : 0), value: current)
                    .transition(.opacity)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: frameAlign)
    }
}

struct LyricRow: View {
    let text: String
    let size: CGFloat
    let current: Bool
    let distance: Int
    let progress: Double
    let singleLine: Bool
    let blur: Bool
    let align: TextAlignment

    var body: some View {
        let label = Text(text)
            .font(.system(size: size, weight: .bold))
            .multilineTextAlignment(align)
            .fixedSize(horizontal: false, vertical: true)
        ZStack(alignment: align == .center ? .center : .leading) {
            label.foregroundStyle(.white.opacity(current ? 0.3 : max(0.14, 0.42 - 0.07 * Double(distance))))
            if current {
                label
                    .foregroundStyle(.white)
                    .mask(fill)
                    .shadow(color: .white.opacity(0.35), radius: size * 0.3)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .blur(radius: blur && !current ? min(5, CGFloat(distance) * 1.25) : 0)
        .scaleEffect(current ? 1 : 0.95, anchor: align == .center ? .center : .leading)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: current)
    }

    /// La línea se ilumina de izquierda a derecha al ritmo de la canción.
    @ViewBuilder
    private var fill: some View {
        if singleLine {
            LinearGradient(stops: [.init(color: .black, location: max(0, progress * 1.1 - 0.08)),
                                   .init(color: .black.opacity(0.0), location: min(1, progress * 1.1 + 0.04))],
                           startPoint: .leading, endPoint: .trailing)
        } else {
            Color.black
        }
    }
}

/// Los tres puntos de los silencios instrumentales; se encienden según avanza la pausa.
struct LyricDots: View {
    let progress: Double
    let size: CGFloat
    @Environment(\.orbitStatic) private var isStatic

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isStatic)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.3) {
                ForEach(0..<3, id: \.self) { index in
                    let fill = max(0, min(1, progress * 3 - Double(index)))
                    Circle()
                        .fill(Color.white.opacity(0.28 + 0.72 * fill))
                        .frame(width: size * 0.34, height: size * 0.34)
                        .scaleEffect(1 + 0.14 * sin(t * 2.6 + Double(index) * 0.7) * (1 - fill * 0.6))
                }
            }
            .frame(height: size * 1.1)
        }
    }
}

// MARK: - Dibujo pequeño de cada estilo (Ajustes)

enum LockStylePicture {
    static func symbol(_ style: LockStyle) -> String {
        switch style {
        case .lyrics: return "text.quote"
        case .cover: return "photo"
        case .karaoke: return "music.mic"
        case .card: return "rectangle.on.rectangle"
        }
    }
}

struct LockStyleThumb: View {
    let style: LockStyle
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [accent.opacity(0.55), Color(red: 0.12, green: 0.06, blue: 0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Capsule().fill(Color.white.opacity(0.7)).frame(width: W * 0.16, height: H * 0.07)
                    .position(x: W / 2, y: H * 0.15)
                switch style {
                case .lyrics:
                    art(W * 0.24).position(x: W * 0.28, y: H * 0.5)
                    lines(W * 0.38, count: 4, H: H).position(x: W * 0.7, y: H * 0.55)
                case .cover:
                    art(W * 0.28).position(x: W / 2, y: H * 0.5)
                    Capsule().fill(Color.white.opacity(0.3)).frame(width: W * 0.34, height: 3).position(x: W / 2, y: H * 0.84)
                case .karaoke:
                    lines(W * 0.6, count: 3, H: H, center: true).position(x: W / 2, y: H * 0.48)
                    Capsule().fill(Color.white.opacity(0.18)).frame(width: W * 0.5, height: H * 0.14).position(x: W / 2, y: H * 0.82)
                case .card:
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.16))
                        .frame(width: W * 0.42, height: H * 0.5).position(x: W / 2, y: H * 0.58)
                    art(W * 0.1).position(x: W * 0.36, y: H * 0.43)
                }
            }
        }
    }

    private func art(_ side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.12)
            .fill(LinearGradient(colors: [accent, accent.opacity(0.5)], startPoint: .top, endPoint: .bottom))
            .frame(width: side, height: side)
            .shadow(color: accent.opacity(0.6), radius: 4)
    }

    private func lines(_ width: CGFloat, count: Int, H: CGFloat, center: Bool = false) -> some View {
        VStack(alignment: center ? .center : .leading, spacing: H * 0.05) {
            ForEach(0..<count, id: \.self) { index in
                Capsule().fill(Color.white.opacity(index == 1 ? 0.95 : 0.3))
                    .frame(width: width * (index == 1 ? 1 : 0.72), height: H * 0.06)
            }
        }
        .frame(width: width, alignment: center ? .center : .leading)
    }
}
