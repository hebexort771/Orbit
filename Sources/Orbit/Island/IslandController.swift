import AppKit
import SwiftUI
import Combine

/// Todos los servicios de la app en un solo lugar.
@MainActor
final class Services {
    let media: NowPlayingService
    let battery: BatteryService
    let audio: AudioService
    let bluetooth: BluetoothService
    let calendar: CalendarService
    let tray: TrayStore
    let keys = MediaKeyTap()
    let isDemo: Bool

    init(demo: Bool = false) {
        isDemo = demo
        media = NowPlayingService(demo: demo)
        battery = BatteryService(demo: demo)
        audio = AudioService(demo: demo)
        bluetooth = BluetoothService()
        calendar = CalendarService(demo: demo)
        tray = TrayStore(demo: demo)
    }

    func start() {
        guard !isDemo else { return }
        media.start()
        battery.start()
        audio.start()
        bluetooth.start()
        calendar.start()
    }

    static let demo = Services(demo: true)
}

/// Coloca la isla, sigue el cursor y convierte los eventos del sistema en animaciones.
@MainActor
final class IslandController {
    let model: IslandModel
    let services: Services
    private let panel: IslandPanel
    private let settings = Settings.shared
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var dragEndTask: Task<Void, Never>?
    private var screen: NSScreen?
    private var dragCount = -1
    private var swipe: CGFloat = 0
    private var suspended = false

    init(services: Services) {
        self.services = services
        let target = Self.preferredScreen()
        let metrics = NotchMetrics.measure(target, style: Settings.shared.virtualStyle)
        model = IslandModel(metrics: metrics)
        screen = target
        panel = IslandPanel(frame: Self.frame(for: metrics))
        let root = IslandCanvas(model: model).services(services)
        let hosting = FirstClickHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.frame = NSRect(origin: .zero, size: metrics.canvasSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        applyVisibility()
        panel.orderFrontRegardless()

        installMonitors()
        wireServices()
        observeSettings()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relocate(force: true) }
        }
    }

    // MARK: Pantalla y posición

    static func preferredScreen() -> NSScreen {
        let screens = NSScreen.screens
        switch Settings.shared.display {
        case .builtin:
            return screens.first(where: { $0.hasNotch }) ?? screens.first(where: { $0.isBuiltin }) ?? NSScreen.main ?? screens[0]
        case .main:
            return screens.first ?? NSScreen.main!
        case .cursor:
            let point = NSEvent.mouseLocation
            return screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main ?? screens[0]
        }
    }

    static func frame(for metrics: NotchMetrics) -> NSRect {
        let size = metrics.canvasSize
        let screen = metrics.screenFrame
        return NSRect(x: (screen.midX - size.width / 2).rounded(),
                      y: screen.maxY - size.height,
                      width: size.width, height: size.height)
    }

    func relocate(force: Bool = false, to target: NSScreen? = nil) {
        let next = target ?? Self.preferredScreen()
        let metrics = NotchMetrics.measure(next, style: settings.virtualStyle)
        guard force || metrics != model.metrics else { return }
        screen = next
        model.metrics = metrics
        panel.setFrame(Self.frame(for: metrics), display: true)
        applyVisibility()
    }

    private func applyVisibility() {
        model.visibleWhenIdle = model.metrics.hasNotch || settings.virtualVisibility == .always
    }

    // MARK: Cursor

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.pointerMoved(dragging: dragging) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.pointerMoved(dragging: dragging) }
            return event
        }) { monitors.append(local) }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }) { monitors.append(down) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }) { monitors.append(up) }
        if let localUp = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseUp() }
            return event
        }) { monitors.append(localUp) }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] event in
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let ended = event.phase == .ended || event.phase == .cancelled
            let began = event.phase == .began
            MainActor.assumeIsolated { self?.scrolled(dx: dx, dy: dy, began: began, ended: ended) }
            return event
        }) { monitors.append(scroll) }
    }

    /// Zona activa de la isla en coordenadas de pantalla.
    private func hotRect() -> CGRect {
        let metrics = model.metrics
        let frame = metrics.screenFrame
        let presentation = model.presentation
        var layout = model.layout(for: presentation)
        if presentation == .hidden { layout = model.layout(for: .idle) }
        let width = layout.outerWidth
        let height = layout.height + metrics.topInset
        var rect = CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
        if presentation.isExpanded {
            rect = rect.insetBy(dx: -12, dy: -14)
        } else {
            rect = rect.insetBy(dx: -8, dy: 0)
            rect.size.height += 2
            rect.origin.y -= 2
        }
        return rect
    }

    private func pointerMoved(dragging: Bool) {
        guard !suspended else { return }
        let point = NSEvent.mouseLocation
        if settings.display == .cursor && !model.expanded && !model.dragActive,
           let current = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
           current != screen {
            relocate(force: true, to: current)
        }
        if dragging {
            handleDrag(at: point)
            return
        }
        let inside = hotRect().contains(point)
        panel.ignoresMouseEvents = !inside
        feedLiquid(point, inside: inside)
        setHovering(inside)
    }

    /// Le cuenta al agua del notch dónde está el cursor (solo si está cerca).
    private func feedLiquid(_ point: NSPoint, inside: Bool) {
        guard settings.liquidNotch else { return }
        let local = liquidPoint(point)
        let layout = model.currentLayout
        let near = abs(local.x) < layout.outerWidth / 2 + 170 && local.y > -24 && local.y < layout.height + 170
        model.liquid.point(near ? local : nil, inside: inside)
    }

    /// El cursor medido desde el centro de arriba de la isla.
    private func liquidPoint(_ point: NSPoint) -> CGPoint {
        let frame = panel.frame
        return CGPoint(x: point.x - frame.midX, y: frame.maxY - point.y - model.metrics.topInset)
    }

    private func setHovering(_ inside: Bool) {
        if inside {
            leaveTask?.cancel()
            guard !model.hovering else { return }
            model.hovering = true
            if settings.liquidNotch { model.liquid.splash(at: liquidPoint(NSEvent.mouseLocation).x, strength: 3) }
            Haptics.tap()
            guard settings.hoverToOpen, !model.expanded else { return }
            hoverTask?.cancel()
            let delay = max(0, settings.hoverDelay)
            hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, !Task.isCancelled, self.model.hovering else { return }
                self.expand()
            }
        } else {
            guard model.hovering else { return }
            model.hovering = false
            hoverTask?.cancel()
            guard model.expanded else { return }
            leaveTask?.cancel()
            leaveTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard let self, !Task.isCancelled, !self.model.hovering else { return }
                self.collapse()
            }
        }
    }

    func expand(page: IslandPage? = nil) {
        if let page { model.select(page) }
        else if !model.pages.contains(model.page) { model.page = model.pages[0] }
        else if model.page == .music && !services.media.hasTrack && model.pages.contains(.calendar) && !model.liveMusic {
            // Sin música: mejor mostrar algo útil.
            model.page = .calendar
        }
        if !model.expanded {
            Haptics.level()
            if settings.liquidNotch { model.liquid.splash(strength: 3.5) }
        }
        model.expanded = true
        model.clearTransient()
    }

    func collapse() {
        if model.expanded && settings.liquidNotch { model.liquid.splash(strength: 4) }
        model.expanded = false
        panel.ignoresMouseEvents = !hotRect().contains(NSEvent.mouseLocation)
    }

    private func scrolled(dx: CGFloat, dy: CGFloat, began: Bool, ended: Bool) {
        guard model.expanded, settings.swipePages else { return }
        if began { swipe = 0 }
        if abs(dx) > abs(dy) { swipe += dx }
        if ended {
            if swipe > 60 { withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { model.shiftPage(-1) }; Haptics.tap() }
            if swipe < -60 { withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { model.shiftPage(1) }; Haptics.tap() }
            swipe = 0
        }
    }

    // MARK: Arrastrar archivos

    private func mouseDown() {
        dragCount = NSPasteboard(name: .drag).changeCount
    }

    private func mouseUp() {
        guard model.dragActive else { return }
        dragEndTask?.cancel()
        dragEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled else { return }
            self.model.dragActive = false
            self.panel.ignoresMouseEvents = !self.hotRect().contains(NSEvent.mouseLocation)
        }
    }

    private func handleDrag(at point: NSPoint) {
        guard settings.trayEnabled, settings.trayOpenOnDrag else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragCount,
              pasteboard.types?.contains(.fileURL) == true else { return }
        let frame = model.metrics.screenFrame
        let near = CGRect(x: frame.midX - 260, y: frame.maxY - 190, width: 520, height: 190)
        let inside = near.contains(point)
        if inside != model.dragActive {
            dragEndTask?.cancel()
            if inside { Haptics.tap() }
            model.dragActive = inside
            panel.ignoresMouseEvents = !inside
        }
    }

    // MARK: Servicios → isla

    private func wireServices() {
        let media = services.media

        media.$isPlaying
            .combineLatest(media.$track.map { $0?.key }.removeDuplicates(), media.$frontmostBundleID)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLiveMusic() }
            .store(in: &bag)

        // Canción nueva: la isla la anuncia un momento con su portada.
        media.$track
            .map { $0?.key }
            .removeDuplicates()
            .scan((nil, nil) as (String?, String?)) { pair, key in (pair.1, key) }
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] (pair: (String?, String?)) in
                guard let self, pair.0 != nil, pair.1 != nil else { return }
                self.announceTrack()
            }
            .store(in: &bag)

        services.battery.onEvent = { [weak self] event in
            guard let self, self.settings.batteryEnabled else { return }
            if case .low = event, !self.settings.batteryLow { return }
            self.model.show(.battery(event), for: self.settings.batteryDuration)
        }

        services.audio.onChange = { [weak self] volume, muted in
            guard let self, self.settings.soundEnabled else { return }
            self.showVolume(volume, muted: muted)
        }

        services.bluetooth.onEvent = { [weak self] event in
            guard let self, self.settings.bluetoothEnabled else { return }
            if !event.connected && !self.settings.bluetoothDisconnect { return }
            self.model.show(.bluetooth(name: event.name, symbol: event.symbol, battery: event.battery,
                                       connected: event.connected),
                            for: self.settings.bluetoothDuration)
        }

        services.calendar.onUpcoming = { [weak self] event, minutes in
            self?.model.show(.calendar(title: event.title, minutes: minutes, color: event.color), for: 6)
        }

        services.keys.handler = { [weak self] key, fine in
            self?.handleKey(key, fine: fine) ?? false
        }
        updateKeyTap()
    }

    private func announceTrack() {
        let media = services.media
        guard settings.trackPeek, settings.musicEnabled, media.isPlaying, !model.expanded,
              let track = media.track else { return }
        if settings.hideWhenSourceActive && media.sourceIsFrontmost { return }
        model.show(.track(title: track.title, artist: track.artist), for: 3.2)
    }

    private func updateLiveMusic() {
        let media = services.media
        guard settings.musicEnabled, media.hasTrack else {
            idleTask?.cancel()
            model.liveMusic = false
            return
        }
        if settings.hideWhenSourceActive && media.sourceIsFrontmost {
            model.liveMusic = false
            return
        }
        if media.isPlaying {
            idleTask?.cancel()
            if !model.liveMusic {
                model.liveMusic = true
                if !model.expanded { model.fireComet(media.accent) }
            }
        } else if model.liveMusic {
            idleTask?.cancel()
            let wait = max(0.5, settings.musicIdle)
            idleTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard let self, !Task.isCancelled, !self.services.media.isPlaying else { return }
                self.model.liveMusic = false
            }
        }
    }

    private func showVolume(_ volume: Float, muted: Bool) {
        model.show(.volume(level: volume, muted: muted, output: services.audio.output), for: settings.soundDuration)
    }

    private func handleKey(_ key: MediaKey, fine: Bool) -> Bool {
        guard settings.replaceSystemHUD else { return false }
        let audio = services.audio
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0
        switch key {
        case .volumeUp, .volumeDown:
            guard settings.soundEnabled, audio.canSetVolume else { return false }
            let target = key == .volumeUp ? audio.volume + step : audio.volume - step
            audio.setVolume(target)
            showVolume(audio.volume, muted: audio.muted)
            return true
        case .mute:
            guard settings.soundEnabled else { return false }
            audio.toggleMute()
            showVolume(audio.volume, muted: audio.muted)
            return true
        case .brightnessUp, .brightnessDown:
            guard settings.brightnessEnabled, let current = Brightness.get() else { return false }
            let target = max(0, min(1, key == .brightnessUp ? current + step : current - step))
            guard Brightness.set(target) else { return false }
            model.show(.brightness(level: target), for: settings.soundDuration)
            return true
        }
    }

    func updateKeyTap() {
        if settings.replaceSystemHUD {
            if !services.keys.start() && !MediaKeyTap.isTrusted {
                MediaKeyTap.requestTrust()
            }
        } else {
            services.keys.stop()
        }
    }

    private func observeSettings() {
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.relocate()
                self.applyVisibility()
                self.updateLiveMusic()
                if self.settings.replaceSystemHUD != self.services.keys.isRunning { self.updateKeyTap() }
            }
            .store(in: &bag)
    }

    // MARK: Demostraciones (botón "Probar")

    func demo(_ kind: TransientKind) {
        model.expanded = false
        model.show(kind, for: 3)
    }

    func demoExpanded(_ page: IslandPage) {
        expand(page: page)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self, !self.model.hovering else { return }
            self.collapse()
        }
    }

    private var calibrateTask: Task<Void, Never>?

    /// Marca el contorno de la isla sobre el notch para ajustarlo a mano.
    func calibrate() {
        relocate(force: true)
        model.expanded = false
        model.clearTransient()
        model.calibrating = true
        calibrateTask?.cancel()
        calibrateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.model.calibrating = false
        }
    }

    func welcome() {
        model.show(.welcome, for: 4.2)
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        if value {
            model.expanded = false
            model.hovering = false
            panel.ignoresMouseEvents = true
        }
        panel.alphaValue = value ? 0 : 1
    }

    var isSuspended: Bool { suspended }
}
