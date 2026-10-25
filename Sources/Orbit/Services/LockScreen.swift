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
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
final class LockCardState: ObservableObject {
    @Published var visible = false
}

/// Candado al bloquear/desbloquear y reproductor en la pantalla de bloqueo.
@MainActor
final class LockScreenController {
    private let services: Services
    private let islandModel: IslandModel
    private let card = LockCardState()
    private var islandPanel: LockPanel?
    private var cardPanel: LockPanel?
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

        if wantsMedia {
            let panel = cardPanel ?? makeCardPanel()
            let size = CGSize(width: 460, height: 360)
            let frame = screen.frame
            panel.setFrame(NSRect(x: frame.midX - size.width / 2,
                                  y: frame.minY + frame.height * 0.36,
                                  width: size.width, height: size.height), display: true)
            panel.orderFrontRegardless()
            space.adopt(panel)
            card.visible = false
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.card.visible = true
            }
        }
    }

    private func unlocked() {
        isLocked = false
        onChange?(false)
        hideTask?.cancel()
        card.visible = false
        if islandPanel?.isVisible == true && Settings.shared.lockEnabled {
            islandModel.show(.lock(locked: false), for: nil)
        }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard let self, !Task.isCancelled else { return }
            self.islandModel.clearTransient()
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self.islandPanel?.orderOut(nil)
            self.cardPanel?.orderOut(nil)
        }
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

    private func makeCardPanel() -> LockPanel {
        let panel = LockPanel(frame: NSRect(x: 0, y: 0, width: 460, height: 360), interactive: true)
        let view = LockMusicCard(state: card).services(services)
        let hosting = FirstClickHostingView(rootView: AnyView(view))
        hosting.sizingOptions = []
        panel.contentView = hosting
        cardPanel = panel
        return panel
    }
}

// MARK: - Reproductor en la pantalla de bloqueo

struct LockMusicCard: View {
    @ObservedObject var state: LockCardState
    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        ZStack {
            if state.visible, let track = media.track {
                card(track)
                    .transition(.modifier(active: BlurFade(progress: 0, lift: 24), identity: BlurFade(progress: 1, lift: 24)))
            }
        }
        .frame(width: 460, height: 360)
        .animation(.spring(response: 0.6, dampingFraction: 0.82), value: state.visible)
        .environment(\.colorScheme, .dark)
    }

    private var showLyrics: Bool {
        settings.lockScreenLyrics && settings.lyricsEnabled && !media.lyrics.isEmpty
    }

    private func card(_ track: TrackInfo) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ArtworkView(size: 66, radius: 15)
                    .shadow(color: media.accent.opacity(0.5), radius: 14, y: 5)
                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(text: track.title, size: 17, weight: .bold, width: 230)
                    Text(track.artist)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Waveform(playing: media.isPlaying, style: settings.waveformStyle, color: media.accent, bars: 5, barWidth: 3)
                    .frame(width: 28, height: 24)
            }
            MediaProgress(accent: media.accent)
            MediaControls(accent: media.accent, big: true)
            if showLyrics {
                LyricsLines(fontSize: 16, accent: media.accent, alignment: .center)
                    .frame(height: 78)
                    .padding(.top, 2)
            }
        }
        .padding(22)
        .frame(width: 400)
        .background {
            ZStack {
                if let art = media.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 50)
                        .saturation(1.4)
                        .opacity(0.9)
                }
                Color.black.opacity(0.42)
                LinearGradient(colors: [media.accent.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
        .foregroundStyle(.white)
    }
}
