import AppKit
import Combine
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
    /// Orbit dibuja el fondo de colores (vista previa, o modo "encima de todo").
    @Published var backdrop = true
    /// Orbit dibuja un reloj (vista previa, o modo "encima de todo"). Con el fondo de pantalla, el reloj es el de macOS.
    @Published var ownClock = true
    /// Deja ver tu foto y la contraseña de macOS a través del fondo (modo "encima de todo").
    @Published var loginHole = false
    /// Dónde están el reloj y el inicio de sesión de macOS en tu pantalla, si se encontraron.
    @Published var bands = LockSystemBands()

    /// Tocar la portada cambia de estilo al instante, sin mostrar ningún texto.
    func cycle() {
        let next = style.next
        withAnimation(.spring(response: 0.66, dampingFraction: 0.84)) { style = next }
        Settings.shared.lockStyle = next
        Haptics.tap()
    }

    func showAsPreview() {
        backdrop = true
        ownClock = true
        loginHole = false
        bands = LockSystemBands()
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
    private var reportTask: Task<Void, Never>?
    private var artworkWatch: AnyCancellable?
    private var prepareWatch: AnyCancellable?
    private var settingsWatch: AnyCancellable?
    private(set) var isLocked = false
    var onChange: ((Bool) -> Void)?

    init(services: Services) {
        self.services = services
        let screen = IslandController.preferredScreen()
        islandModel = IslandModel(metrics: NotchMetrics.measure(screen, style: Settings.shared.virtualStyle))
        let center = DistributedNotificationCenter.default()
        // El fondo de la canción se prepara en segundo plano cada vez que cambia la canción,
        // para que al bloquear no haya que dibujar nada y todo vaya fluido.
        prepareWatch = services.media.$softArtwork.combineLatest(services.media.$palette)
            .debounce(for: .milliseconds(700), scheduler: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.prepareWallpaper() } }
        settingsWatch = Settings.shared.objectWillChange
            .debounce(for: .milliseconds(700), scheduler: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.prepareWallpaper() } }
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked() }
        }
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unlocked() }
        }
    }

    private func prepareWallpaper() {
        let settings = Settings.shared
        guard !isLocked, settings.lockScreenMedia, settings.musicEnabled, settings.lockLayer == .wallpaper,
              services.media.hasTrack else { return }
        LockWallpaper.shared.prepare(media: services.media, screen: IslandController.preferredScreen())
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
            // Primero se intenta poner los colores de la canción como fondo de pantalla:
            // así macOS dibuja encima su propio reloj, tu foto y la contraseña.
            var onWallpaper = false
            if settings.lockLayer == .wallpaper {
                onWallpaper = LockWallpaper.shared.apply(media: services.media, to: screen)
            }
            state.backdrop = !onWallpaper
            state.ownClock = !onWallpaper
            state.loginHole = !onWallpaper
            state.bands = LockSystemBands()

            let panel = screenPanel ?? makeScreenPanel(for: screen)
            panel.setFrame(screen.frame, display: true)
            (panel.contentView as? FirstClickHostingView<AnyView>)?.rootView = screenRoot(for: screen, preview: false)
            panel.orderFrontRegardless()
            space.adopt(panel)
            state.syncStyle()
            state.phase = .hidden
            // La entrada empieza cuando macOS termina de mostrar su pantalla de bloqueo.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000)
                self?.state.phase = .shown
            }

            // Medir dónde quedaron el reloj y el inicio de sesión de macOS y guardar un informe.
            let mode = onWallpaper ? "fondo de pantalla (reloj de macOS)" : "encima de todo (reloj de Orbit)"
            reportTask?.cancel()
            reportTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled, self.isLocked else { return }
                let bands = LockReport.bands(on: screen)
                withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { self.state.bands = bands }
                LockReport.write(screen: screen, safeTop: LockScreenController.safeTop(of: screen), mode: mode, bands: bands)
            }

            // Si cambia la canción con la Mac bloqueada, el fondo cambia también.
            artworkWatch = onWallpaper ? services.media.$softArtwork
                .dropFirst()
                .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.isLocked else { return }
                        LockWallpaper.shared.refresh(media: self.services.media, screen: screen)
                    }
                } : nil
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
        artworkWatch = nil
        reportTask?.cancel()
        // Tu fondo vuelve con un fundido, por detrás de tus ventanas, mientras la portada vuela al notch.
        DispatchQueue.main.async { LockWallpaper.shared.restore(animated: true) }
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
            // Sin vista mientras no se usa: nada se queda trabajando de fondo.
            (self.screenPanel?.contentView as? FirstClickHostingView<AnyView>)?.rootView = AnyView(Color.clear)
            self.state.phase = .hidden
        }
    }

    private func screenRoot(for screen: NSScreen, preview: Bool) -> AnyView {
        AnyView(LockScreenView(state: state, size: screen.frame.size, safeTop: LockScreenController.safeTop(of: screen),
                               preview: preview).services(services))
    }

    /// Alto del notch de esa pantalla (o de la barra de menús si no tiene).
    static func safeTop(of screen: NSScreen) -> CGFloat {
        let notch = screen.safeAreaInsets.top
        if notch > 0 { return notch }
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        return bar > 0 ? bar : 24
    }

    private func makeIslandPanel() -> LockPanel {
        let panel = LockPanel(frame: IslandController.frame(for: islandModel.metrics), interactive: false)
        panel.level = NSWindow.Level(rawValue: Int(Int32.max - 1))
        let view = IslandCanvas(model: islandModel).services(services)
        let hosting = FirstClickHostingView(rootView: AnyView(view))
        hosting.sizingOptions = []
        panel.contentView = hosting
        islandPanel = panel
        return panel
    }

    private func makeScreenPanel(for screen: NSScreen) -> LockPanel {
        let panel = LockPanel(frame: screen.frame, interactive: true)
        let hosting = FirstClickHostingView(rootView: screenRoot(for: screen, preview: false))
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
        let hosting = FirstClickHostingView(rootView: screenRoot(for: screen, preview: true))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        previewPanel = panel
        state.syncStyle()
        state.showAsPreview()
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
    var clockDate: CGFloat
    var clockTime: CGFloat
    var badgeY: CGFloat
    var effective: LockStyle

    /// - safeTop: alto del notch (o de la barra de menús) de esa pantalla.
    init(style: LockStyle, size: CGSize, safeTop: CGFloat, hasLyrics: Bool, clock: Bool, settings: Settings,
         bands: LockSystemBands = LockSystemBands()) {
        let W = size.width, H = size.height
        // Reloj: arriba, debajo del notch, del tamaño que corresponde a la pantalla.
        clockDate = max(15, min(24, H * 0.021))
        clockTime = max(72, min(150, H * 0.112))
        let clockTop = safeTop + H * 0.045
        let clockHeight = clockDate * 1.25 + clockTime * 1.05
        clockY = clockTop + clockHeight / 2
        // Zona para el contenido: entre el reloj y la foto de usuario/contraseña de macOS.
        var top = clock ? clockTop + clockHeight + H * 0.045 : safeTop + H * 0.1
        var floor = H * 0.725
        if let bottom = bands.clockBottom { top = max(top, bottom + H * 0.035) }
        if let login = bands.loginTop { floor = min(floor, login - H * 0.03) }
        let room = max(240, floor - top)
        var style = style
        if !hasLyrics && (style == .lyrics || style == .karaoke) { style = .cover }
        effective = style
        badgeY = clock ? clockTop + clockHeight + H * 0.02 : top - 20
        reflection = false
        lyrics = nil
        lyricsSize = min(settings.lockLyricsSize, max(22, W * 0.026))
        lyricsAlign = settings.lockLyricsAlign
        lyricsAnchor = 0.36

        switch style {
        case .lyrics:
            let cardH: CGFloat = 138
            let side = max(150, min(W * 0.24, room - cardH - 20))
            let groupH = side + 20 + cardH
            let y0 = top + max(0, (room - groupH) / 2)
            // Portada + espacio + letra forman un solo bloque centrado en la pantalla.
            let gap = W * 0.06
            let lyricsW = min(W * 0.4, 640)
            let x0 = (W - (side + gap + lyricsW)) / 2
            art = CGRect(x: x0, y: y0, width: side, height: side)
            artRadius = side * 0.07
            card = CGRect(x: art.minX, y: art.maxY + 20, width: side, height: cardH)
            cardKind = .under
            cardRadius = 22
            // La letra ocupa la misma altura que portada + controles; la línea que suena queda a la altura de la portada.
            let lyricsTop = art.minY - 28
            lyrics = CGRect(x: art.maxX + gap, y: lyricsTop, width: lyricsW, height: card.maxY + 16 - lyricsTop)
            lyricsAnchor = min(0.4, (art.midY - lyricsTop) / max(1, card.maxY + 16 - lyricsTop))
        case .cover:
            let cardH: CGFloat = 156
            let side = max(150, min(W * 0.23, (room - cardH) / 1.3))
            let groupH = side * 1.3 + cardH
            let y0 = top + max(0, (room - groupH) / 2)
            art = CGRect(x: W / 2 - side / 2, y: y0, width: side, height: side)
            artRadius = side * 0.06
            let cw = max(side + 90, 400)
            card = CGRect(x: W / 2 - cw / 2, y: art.maxY + side * 0.3, width: cw, height: cardH)
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
            lyrics = CGRect(x: W * 0.12, y: top - H * 0.02, width: W * 0.76, height: max(120, card.minY - 24 - (top - H * 0.02)))
            lyricsSize = min(settings.lockLyricsSize * 1.45, max(30, W * 0.038))
            lyricsAlign = .center
            lyricsAnchor = 0.4
        case .card:
            let cw: CGFloat = 420
            let ch: CGFloat = min(hasLyrics ? 318 : 222, room)
            card = CGRect(x: W / 2 - cw / 2, y: top + max(0, (room - ch) / 2), width: cw, height: ch)
            art = CGRect(x: card.minX + 22, y: card.minY + 22, width: 68, height: 68)
            artRadius = 15
            cardKind = .full
            cardRadius = 32
            if hasLyrics {
                lyrics = CGRect(x: card.minX + 22, y: card.minY + 222, width: cw - 44, height: max(40, ch - 236))
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
    var safeTop: CGFloat = 32
    var preview = false
    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared
    @Environment(\.orbitStatic) private var isStatic
    @State private var tilt: CGSize = .zero
    @State private var straighten: Task<Void, Never>?

    private var morph: Animation { .spring(response: 0.66, dampingFraction: 0.84) }

    var body: some View {
        let shown = state.phase == .shown || isStatic
        let leaving = state.phase == .leaving
        let hasLyrics = settings.lockScreenLyrics && settings.lyricsEnabled && !media.lyrics.isEmpty
        let layout = LockLayout(style: state.style, size: size, safeTop: safeTop, hasLyrics: hasLyrics,
                                clock: true, settings: settings, bands: state.bands)

        ZStack(alignment: .topLeading) {
            if state.backdrop {
                LockBackdrop(size: size, loginHole: state.loginHole ? loginCenter : nil)
                    .opacity(shown ? 1 : 0)
                    .animation(.easeInOut(duration: leaving ? 0.75 : 1.0), value: state.phase)
            }

            if state.ownClock {
                LockClock(dateSize: layout.clockDate, timeSize: layout.clockTime)
                    .frame(width: size.width)
                    .position(x: size.width / 2, y: layout.clockY)
                    .modifier(Reveal(phase: state.phase, delay: 0.2, travel: -20, isStatic: isStatic, leaveDelay: 0.1))
            }

            if let track = media.track {
                if let rect = layout.lyrics {
                    LockLyrics(size: rect.size, fontSize: layout.lyricsSize, align: layout.lyricsAlign,
                               anchor: layout.lyricsAnchor, compact: layout.cardKind == .full, phase: state.phase)
                        .id(track.key)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                LockCard(kind: layout.cardKind, track: track, size: layout.card.size, radius: layout.cardRadius,
                         artWidth: layout.art.width)
                    .frame(width: layout.card.width, height: layout.card.height)
                    .position(x: layout.card.midX, y: layout.card.midY)
                    .modifier(Reveal(phase: state.phase, delay: 0.42, travel: 26, isStatic: isStatic, leaveDelay: 0.05))

                LockArtwork(rect: leaving ? notchRect : layout.art,
                            radius: leaving ? 6 : layout.artRadius,
                            reflection: layout.reflection && !leaving,
                            tilt: settings.lockTilt ? tilt : .zero,
                            shown: shown,
                            leaving: leaving,
                            onTap: { state.cycle() })
                    .animation(leaving ? .spring(response: 0.72, dampingFraction: 0.9)
                                       : (shown ? .spring(response: 1.0, dampingFraction: 0.8).delay(0.28) : .easeIn(duration: 0.2)),
                               value: state.phase)
            }

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
            let art = layout.art
            switch phase {
            case .active(let point) where art.insetBy(dx: -30, dy: -30).contains(point):
                let next = CGSize(width: max(-1, min(1, (point.x - art.midX) / (art.width / 2 + 30))),
                                  height: max(-1, min(1, (point.y - art.midY) / (art.height / 2 + 30))))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { tilt = next }
                straighten?.cancel()
                straighten = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.9, dampingFraction: 0.75)) { tilt = .zero }
                }
            default:
                straighten?.cancel()
                if tilt != .zero {
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) { tilt = .zero }
                }
            }
        }
    }

    /// Hacia donde vuela la portada al desbloquear: el notch.
    private var notchRect: CGRect {
        let side = max(18, safeTop - 10)
        return CGRect(x: size.width / 2 - side / 2, y: (safeTop - side) / 2, width: side, height: side)
    }

    /// Dónde está tu foto de usuario en la pantalla bloqueada de macOS.
    private var loginCenter: CGPoint {
        let y = state.bands.loginTop.map { $0 + size.height * 0.09 } ?? size.height * 0.86
        return CGPoint(x: size.width / 2, y: y)
    }
}

/// Entrada y salida de cada pieza: aparece desde un desenfoque subiendo despacio y, al desbloquear, se va hacia arriba.
struct Reveal: ViewModifier {
    let phase: LockScreenState.Phase
    let delay: Double
    let travel: CGFloat
    let isStatic: Bool
    var leaveDelay: Double = 0

    func body(content: Content) -> some View {
        let shown = phase == .shown || isStatic
        let leaving = phase == .leaving
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : (leaving ? 8 : 16))
            .offset(y: shown ? 0 : (leaving ? -travel * 0.7 : travel))
            .scaleEffect(shown ? 1 : (leaving ? 0.98 : 0.94))
            .animation(shown ? .spring(response: 0.95, dampingFraction: 0.86).delay(delay)
                             : (leaving ? .easeInOut(duration: 0.5).delay(leaveDelay) : .easeIn(duration: 0.2)),
                       value: phase)
    }
}

/// Cada línea de la letra entra una detrás de otra, como una cascada.
struct LineReveal: ViewModifier {
    let phase: LockScreenState.Phase
    let rank: Int
    let isStatic: Bool

    func body(content: Content) -> some View {
        let shown = phase == .shown || isStatic
        let leaving = phase == .leaving
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 10)
            .offset(y: shown ? 0 : (leaving ? -22 : 30 + CGFloat(rank) * 6))
            .animation(shown ? .spring(response: 0.95, dampingFraction: 0.86).delay(0.5 + Double(rank) * 0.065)
                             : (leaving ? .easeIn(duration: 0.38).delay(Double(rank) * 0.035) : .easeIn(duration: 0.2)),
                       value: phase)
    }
}

// MARK: - Fondo

struct LockBackdrop: View {
    let size: CGSize
    /// Centro del inicio de sesión de macOS que debe verse a través del fondo (nil = pantalla completa).
    var loginHole: CGPoint? = nil
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
        .mask(holeMask)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var holeMask: some View {
        if let center = loginHole {
            ZStack {
                Color.black
                // Un círculo que se desvanece hasta su borde (sin líneas), estirado a lo ancho.
                let radius = size.height * 0.2
                Circle()
                    .fill(RadialGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.9), location: 0.45),
                                                 .init(color: .black.opacity(0), location: 1)],
                                         center: .center, startRadius: 0, endRadius: radius))
                    .frame(width: radius * 2, height: radius * 2)
                    .scaleEffect(x: 1.5, y: 1)
                    .position(center)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        } else {
            Color.black
        }
    }

    private var diagonal: CGFloat { (size.width * size.width + size.height * size.height).squareRoot() }

    private var aurora: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !settings.lockMotion || isStatic)) { timeline in
            let t = isStatic ? 14 : timeline.date.timeIntervalSinceReferenceDate
            let c = colors
            ZStack {
                c[0]
                if let soft = media.softArtwork {
                    // Cada capa es más grande que la diagonal de la pantalla y se desvanece en los bordes:
                    // al girar nunca se ve una esquina ni una línea recta.
                    Image(nsImage: soft)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: diagonal * 1.3, height: diagonal * 1.3)
                        .mask(softEdge(diagonal * 1.3))
                        .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 3600) * 3.5))
                        .opacity(0.72)
                    Image(nsImage: soft)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: diagonal * 1.3, height: diagonal * 1.3)
                        .mask(softEdge(diagonal * 1.3))
                        .scaleEffect(x: -1, y: 1)
                        .rotationEffect(.degrees(90 - t.truncatingRemainder(dividingBy: 3600) * 5))
                        .blendMode(.screen)
                        .opacity(0.34)
                }
                ForEach(0..<3, id: \.self) { index in
                    blob(c[index], index: index, t: t)
                }
                Color.black.opacity(0.4)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func softEdge(_ side: CGFloat) -> some View {
        RadialGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.62),
                               .init(color: .clear, location: 1)],
                       center: .center, startRadius: 0, endRadius: side / 2)
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
    let dateSize: CGFloat
    let timeSize: CGFloat
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            // Como el de macOS: medio transparente, deja ver los colores de atrás.
            VStack(spacing: dateSize * 0.15) {
                Text(dateText(timeline.date))
                    .font(.system(size: dateSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(LockClock.time(timeline.date))
                    .font(.system(size: timeSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .contentTransition(.numericText())
            }
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Como el reloj de macOS: solo horas y minutos, sin "a. m." ni "p. m.",
    /// respetando si usas formato de 12 o de 24 horas.
    static func time(_ date: Date) -> String {
        let locale = Lang.locale
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H"
        let twelve = pattern.contains("h") || pattern.contains("K") || pattern.contains("a")
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = twelve ? "h:mm" : "H:mm"
        return formatter.string(from: date)
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
        .modifier(Tilt(tilt: tilt, enabled: settings.lockTilt))
        .opacity(leaving ? 0 : (shown ? 1 : 0))
        .animation(leaving ? .easeIn(duration: 0.26).delay(0.4) : nil, value: leaving)
        .scaleEffect(shown || leaving ? 1 : 0.8)
        .blur(radius: shown || leaving ? 0 : 22)
        .frame(width: rect.width, height: rect.height)
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .onTapGesture { onTap() }
        .position(x: rect.midX, y: rect.midY)
    }

    private func art(_ side: CGFloat) -> some View {
        ZStack {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
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

/// Inclinación 3D de la portada. Solo se aplica si está activada: así la portada se dibuja plana
/// y a resolución completa (una transformación 3D, aunque sea de 0°, puede suavizar la imagen).
struct Tilt: ViewModifier {
    let tilt: CGSize
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .rotation3DEffect(.degrees(Double(-tilt.height) * 4), axis: (x: 1, y: 0, z: 0), perspective: 0.3)
                .rotation3DEffect(.degrees(Double(tilt.width) * 5), axis: (x: 0, y: 1, z: 0), perspective: 0.3)
        } else {
            content
        }
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
            if kind != .under {
                card
            }
            content
                .id(kind)
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
        }
        .foregroundStyle(.white)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(kind == .full ? 0.1 : 0.085))
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black.opacity(kind == .full ? 0.35 : 0.12))
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .under:
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(track.artist).font(.system(size: 14, weight: .regular)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LockProgress()
                LockControlsRow()
            }
            .frame(maxHeight: .infinity, alignment: .top)
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

/// Barra de progreso de Apple Music: fina, con los tiempos debajo en las dos puntas.
struct LockProgress: View {
    @EnvironmentObject private var media: NowPlayingService
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let duration = media.track?.duration ?? 0
            let live = media.elapsed(at: timeline.date)
            let elapsed = dragFraction.map { $0 * duration } ?? live
            let fraction = duration > 0 ? min(1, max(0, elapsed / duration)) : 0
            VStack(spacing: 5) {
                GeometryReader { geo in
                    let height: CGFloat = dragFraction == nil ? 5 : 8
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(Color.white.opacity(0.75))
                            .frame(width: max(height, geo.size.width * CGFloat(fraction)))
                            .animation(dragFraction == nil ? .linear(duration: 0.5) : nil, value: fraction)
                    }
                    .frame(height: height)
                    .frame(maxHeight: .infinity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragFraction == nil)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragFraction = min(1, max(0, Double(value.location.x / max(1, geo.size.width))))
                            }
                            .onEnded { value in
                                media.seek(to: min(1, max(0, Double(value.location.x / max(1, geo.size.width)))) * duration)
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 10)
                HStack {
                    Text(TimeText.clock(elapsed))
                    Spacer()
                    Text("−" + TimeText.clock(max(0, duration - elapsed)))
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

/// Aleatorio a la izquierda, anterior/reproducir/siguiente al centro y repetir a la derecha.
struct LockControlsRow: View {
    @EnvironmentObject private var media: NowPlayingService

    var body: some View {
        HStack(spacing: 0) {
            Button { media.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(media.shuffleOn ? Color.white : Color.white.opacity(0.55))
            }
            .buttonStyle(OrbitButtonStyle(size: 34))
            Spacer(minLength: 4)
            HStack(spacing: 14) {
                Button { media.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(OrbitButtonStyle(size: 44))
                Button { media.togglePlay() } label: {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(OrbitButtonStyle(size: 52))
                Button { media.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(OrbitButtonStyle(size: 44))
            }
            Spacer(minLength: 4)
            Button { media.cycleRepeat() } label: {
                Image(systemName: media.repeatMode == 2 ? "repeat.1" : "repeat")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(media.repeatMode != 1 ? Color.white : Color.white.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(OrbitButtonStyle(size: 34))
        }
        .foregroundStyle(.white)
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
    var phase: LockScreenState.Phase = .shown
    var glow: Color = .white
    @Environment(\.orbitStatic) private var isStatic
    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { timeline in
            let time = media.lyricsTime(at: timeline.date)
            // Como Apple Music: la línea se enciende justo cuando empieza a cantarse.
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
        let intro = current < 0 && (lyrics.first?.time ?? 0) > 2.5
        let dotsHeight = fontSize * 1.1
        let base = intro
            ? size.height * anchor + dotsHeight / 2 + gap
            : size.height * anchor - (ys.isEmpty ? 0 : ys[min(focus, ys.count - 1)]) - focusHeight / 2
        let first = max(0, focus - (compact ? 1 : 4))
        let last = min(lyrics.count - 1, focus + (compact ? 2 : 8))
        let textAlign: TextAlignment = align == .center ? .center : .leading
        let frameAlign: Alignment = align == .center ? .top : .topLeading

        return ZStack(alignment: frameAlign) {
            if intro, let firstLine = lyrics.first {
                LyricDots(progress: time / firstLine.time, size: fontSize)
                    .frame(width: size.width, alignment: align == .center ? .center : .leading)
                    .offset(y: size.height * anchor - dotsHeight / 2)
                    .transition(.opacity)
                    .modifier(LineReveal(phase: phase, rank: 0, isStatic: isStatic))
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
                                     blur: settings.lockLyricsBlur, align: textAlign,
                                     words: isCurrent && (!line.words.isEmpty || settings.lyricsEstimateWords)
                                        ? LyricTiming.words(lyrics, index: index, duration: media.track?.duration ?? 0) : [],
                                     glow: glow, sung: index < current)
                        }
                    }
                    .frame(width: size.width, alignment: align == .center ? .center : .leading)
                    .offset(y: base + ys[index])
                    .animation(.spring(response: 0.7, dampingFraction: 0.86)
                        .delay(index >= current ? Double(index - max(current, 0)) * 0.045 : 0), value: current)
                    .animation(.spring(response: 0.7, dampingFraction: 0.86), value: intro)
                    .transition(.opacity)
                    .modifier(LineReveal(phase: phase, rank: index - first + (intro ? 1 : 0), isStatic: isStatic))
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
    var words: [WordTiming] = []
    var glow: Color = .white
    var sung = false

    var body: some View {
        let label = Text(text)
            .font(.system(size: size, weight: .bold))
            .multilineTextAlignment(align)
            .fixedSize(horizontal: false, vertical: true)
        ZStack(alignment: align == .center ? .center : .leading) {
            if current && !words.isEmpty {
                // Palabra por palabra, al ritmo del cantante.
                KaraokeLive(words: words, size: size, center: align == .center, glow: glow)
                    .transition(.opacity)
            } else {
                // Como Apple Music cuando la letra no trae el tiempo de cada palabra:
                // la línea entera se enciende en el momento exacto en que se canta.
                label
                    .foregroundStyle(.white.opacity(current ? 1 : max(0.14, (sung ? 0.34 : 0.42) - 0.07 * Double(distance))))
                    .shadow(color: glow.opacity(current ? 0.35 : 0), radius: current ? size * 0.32 : 0)
            }
        }
        .blur(radius: blur && !current ? min(5, CGFloat(distance) * 1.25) : 0)
        .scaleEffect(current ? 1 : 0.95, anchor: align == .center ? .center : .leading)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: current)
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
