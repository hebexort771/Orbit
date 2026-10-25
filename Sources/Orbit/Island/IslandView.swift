import SwiftUI
import AppKit

/// Toda la ventana transparente; la isla vive arriba al centro.
struct IslandCanvas: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let presentation = model.presentation
        let layout = model.currentLayout
        VStack(spacing: 0) {
            IslandBody(model: model, presentation: presentation, layout: layout, motion: Motion.current(settings))
                .padding(.top, model.metrics.topInset)
            Spacer(minLength: 0)
        }
        .frame(width: model.canvasSize.width, height: model.canvasSize.height, alignment: .top)
    }
}

struct Jelly {
    var x: CGFloat = 1
    var y: CGFloat = 1
}

struct IslandBody: View {
    @ObservedObject var model: IslandModel
    let presentation: Presentation
    let layout: IslandLayout
    let motion: Motion

    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared

    private var shape: IslandShape {
        IslandShape(ear: layout.ear, bottom: layout.bottom, topCorner: layout.topCorner)
    }

    var body: some View {
        ZStack(alignment: .top) {
            glow
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(presentation.isExpanded ? 0.55 : 0), radius: 18, y: 10)
            content
                .clipShape(shape)
            IslandEdge(island: shape)
                .stroke(Color.white.opacity(presentation.isExpanded ? 0.09 : 0), lineWidth: 1)
                .allowsHitTesting(false)
            CometOverlay(island: shape, request: model.comet)
                .allowsHitTesting(false)
        }
        .frame(width: layout.outerWidth)
        .animation(motion.width, value: layout.outerWidth)
        .frame(height: layout.height, alignment: .top)
        .animation(motion.height, value: layout.height)
        .animation(motion.height, value: layout.bottom)
        .keyframeAnimator(initialValue: Jelly(), trigger: motion.liquid ? presentation.key : "") { view, jelly in
            view.scaleEffect(x: jelly.x, y: jelly.y, anchor: .top)
        } keyframes: { _ in
            KeyframeTrack(\Jelly.x) {
                CubicKeyframe(1.035, duration: 0.11)
                SpringKeyframe(1, duration: 0.6, spring: Spring(response: 0.42, dampingRatio: 0.5))
            }
            KeyframeTrack(\Jelly.y) {
                CubicKeyframe(0.965, duration: 0.11)
                SpringKeyframe(1, duration: 0.6, spring: Spring(response: 0.42, dampingRatio: 0.5))
            }
        }
        .contentShape(shape)
        .onTapGesture {
            guard !model.expanded, !model.isPreview else { return }
            Haptics.level()
            model.expanded = true
        }
        .contextMenu {
            Button(tr("Ajustes de Orbit…", "Orbit Settings…")) { AppActions.openSettings() }
            Divider()
            Button(tr("Salir de Orbit", "Quit Orbit")) { AppActions.quit() }
        }
    }

    // MARK: Brillo ambiental

    private var glowColor: Color {
        switch presentation {
        case .music, .expanded(.music): return media.accent
        case .transient(let kind): return kind.tint
        default: return .clear
        }
    }

    private var glowOpacity: Double {
        guard settings.ambientGlow else { return 0 }
        switch presentation {
        case .music: return media.isPlaying ? 0.4 : 0.14
        case .expanded(.music): return media.hasTrack ? 0.45 : 0
        case .transient(let kind):
            switch kind {
            case .battery, .bluetooth, .calendar, .welcome: return 0.36
            case .lock(let locked): return locked ? 0 : 0.3
            default: return 0
            }
        default: return 0
        }
    }

    private var glow: some View {
        shape
            .fill(glowColor)
            .blur(radius: presentation.isExpanded ? 30 : 14)
            .opacity(glowOpacity)
            .scaleEffect(x: 0.94, y: 0.92, anchor: .top)
            .offset(y: presentation.isExpanded ? 12 : 5)
            .animation(.easeInOut(duration: 0.7), value: glowOpacity)
            .animation(.easeInOut(duration: 0.7), value: glowColor)
            .allowsHitTesting(false)
    }

    // MARK: Contenido

    private var content: some View {
        ZStack(alignment: .top) {
            pageContent
                .id(presentation.contentKey)
                .transition(.orbitContent(motion))
        }
        .frame(width: layout.outerWidth, height: layout.height, alignment: .top)
        .animation(motion.content, value: presentation.contentKey)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch presentation {
        case .hidden, .idle:
            Color.clear.frame(width: 1, height: 1)
        case .music:
            CompactMusic(model: model, layout: layout)
        case .transient(let kind):
            TransientContent(kind: kind, model: model, layout: layout)
        case .expanded(let page):
            ExpandedContent(model: model, page: page, layout: layout)
        }
    }
}

extension Presentation {
    /// El encabezado se mantiene al cambiar de página dentro de la vista expandida.
    var contentKey: String {
        if case .expanded = self { return "x" }
        return key
    }
}

// MARK: - Estela orbital

struct CometFrame {
    var phase: CGFloat = 0
    var opacity: Double = 0
    var burst: CGFloat = 0
}

/// Dos destellos bajan por los lados de la isla y se encuentran abajo en un pulso de luz.
struct CometOverlay: View {
    let island: IslandShape
    let request: CometRequest

    var body: some View {
        Color.clear
            .keyframeAnimator(initialValue: CometFrame(), trigger: request.serial) { view, frame in
                view.overlay {
                    ZStack {
                        trails(frame)
                        trails(frame).scaleEffect(x: -1, y: 1)
                        burst(frame)
                    }
                    .opacity(frame.opacity)
                }
            } keyframes: { _ in
                KeyframeTrack(\CometFrame.phase) {
                    LinearKeyframe(0, duration: 0.01)
                    CubicKeyframe(1.3, duration: 0.95)
                }
                KeyframeTrack(\CometFrame.opacity) {
                    LinearKeyframe(1, duration: 0.05)
                    LinearKeyframe(1, duration: 0.9)
                    LinearKeyframe(0, duration: 0.35)
                }
                KeyframeTrack(\CometFrame.burst) {
                    LinearKeyframe(0, duration: 0.72)
                    CubicKeyframe(1, duration: 0.6)
                }
            }
    }

    private func trails(_ frame: CometFrame) -> some View {
        let color = request.color
        return ZStack {
            CometTrail(island: island, phase: frame.phase, length: 0.36)
                .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .blur(radius: 5)
            CometTrail(island: island, phase: frame.phase, length: 0.2)
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .blur(radius: 1)
            CometTrail(island: island, phase: frame.phase, length: 0.06)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func burst(_ frame: CometFrame) -> some View {
        let b = frame.burst
        let fade = Double(b > 0 && b < 1 ? sin(Double(b) * .pi) : 0)
        return VStack {
            Spacer(minLength: 0)
            ZStack {
                Capsule()
                    .fill(request.color)
                    .frame(width: 30 + 120 * b, height: 6 + 4 * b)
                    .blur(radius: 8)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 8 + 50 * b, height: 2)
                    .blur(radius: 1.5)
            }
            .offset(y: 3)
            .opacity(fade)
        }
    }
}

// MARK: - Música compacta

struct CompactMusic: View {
    @ObservedObject var model: IslandModel
    let layout: IslandLayout
    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let metrics = model.metrics
        let h = metrics.notchHeight
        let wing = max(0, (layout.width - metrics.notchWidth) / 2)
        Wings(notch: metrics.notchWidth, wing: wing, height: h) {
            ArtworkView(size: h - 12, radius: 6)
                .shadow(color: media.accent.opacity(0.45), radius: 5)
        } right: {
            if settings.compactWaveform {
                Waveform(playing: media.isPlaying, style: settings.waveformStyle, color: media.accent,
                         bars: 4, barWidth: 2.6)
                    .frame(width: 17, height: 13)
            }
        }
    }
}

// MARK: - Avisos temporales

struct TransientContent: View {
    let kind: TransientKind
    @ObservedObject var model: IslandModel
    let layout: IslandLayout
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let metrics = model.metrics
        let wing = max(0, (layout.width - metrics.notchWidth) / 2)
        VStack(spacing: 0) {
            Wings(notch: metrics.notchWidth, wing: wing, height: metrics.notchHeight) {
                left
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
            } right: {
                right
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 14)
            }
            if kind.extraHeight > 0 {
                subtitle
                    .frame(height: kind.extraHeight - 6)
                    .frame(maxWidth: layout.width - 30)
            }
        }
        .foregroundStyle(.white)
    }

    private var label: Font { .system(size: 12, weight: .semibold) }

    @ViewBuilder
    private var left: some View {
        switch kind {
        case .volume(let level, let muted, let output):
            if settings.soundShowDevice && output != .speaker {
                Image(systemName: output.symbol)
                    .font(.system(size: 14, weight: .semibold))
            } else {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: Double(level))
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22, alignment: .leading)
            }
        case .brightness(let level):
            Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.orbitYellow)
                .contentTransition(.symbolEffect(.replace))
        case .battery(let event):
            switch event {
            case .charging: Text(tr("Cargando", "Charging")).font(label)
            case .full: Text(tr("Cargado", "Charged")).font(label)
            case .unplugged: Text(tr("Batería", "Battery")).font(label)
            case .low: Text(tr("Batería baja", "Low Battery")).font(label).foregroundStyle(Color.orbitRed)
            }
        case .bluetooth(_, let symbol, _, let connected):
            BouncingSymbol(name: symbol)
                .font(.system(size: 15, weight: .semibold))
                .opacity(connected ? 1 : 0.5)
        case .lock(let locked):
            Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(locked ? Color.white : Color.orbitGreen)
                .contentTransition(.symbolEffect(.replace))
        case .calendar(_, _, let color):
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        case .tray:
            BouncingSymbol(name: "tray.and.arrow.down.fill")
                .font(.system(size: 14, weight: .semibold))
        case .welcome:
            OrbitMark(size: 18)
        }
    }

    @ViewBuilder
    private var right: some View {
        switch kind {
        case .volume(let level, let muted, _):
            levelRow(value: muted ? 0 : Double(level))
        case .brightness(let level):
            levelRow(value: Double(level))
        case .battery(let event):
            batteryRow(event)
        case .bluetooth(_, _, let battery, let connected):
            if !connected {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.45))
            } else if let battery, settings.bluetoothBattery {
                RingGauge(value: Double(battery) / 100, color: battery < 20 ? .orbitRed : .orbitGreen)
                    .frame(width: 17, height: 17)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.orbitGreen)
            }
        case .lock:
            EmptyView()
        case .calendar(_, let minutes, _):
            Text(tr("en \(minutes) min", "in \(minutes) min")).font(label)
        case .tray(let count):
            Text("+\(count)").font(label).contentTransition(.numericText(value: Double(count)))
        case .welcome:
            Text(tr("Hola", "Hello")).font(label)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch kind {
        case .calendar(let title, _, _):
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        case .welcome:
            Text(tr("Pasa el cursor por aquí", "Hover here to open"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        default:
            EmptyView()
        }
    }

    private func levelRow(value: Double) -> some View {
        let percent = settings.soundPercent
        return HStack(spacing: 7) {
            LevelBar(value: value, style: settings.soundBarStyle, accent: .accentColor,
                     animation: settings.soundAnimation.animation)
                .frame(width: percent ? 36 : 48, height: 5)
            if percent {
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText(value: value))
                    .animation(settings.soundAnimation.animation, value: value)
                    .frame(width: 24, alignment: .trailing)
            }
        }
    }

    private func batteryRow(_ event: BatteryEvent) -> some View {
        let level: Int
        let color: Color
        let charging: Bool
        switch event {
        case .charging(let l): level = l; color = .orbitGreen; charging = true
        case .full: level = 100; color = .orbitGreen; charging = false
        case .unplugged(let l): level = l; color = l <= 20 ? .orbitRed : .white; charging = false
        case .low(let l): level = l; color = .orbitRed; charging = false
        }
        return HStack(spacing: 6) {
            if settings.batteryPercent {
                Text("\(level)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color == .white ? Color.white : color)
            }
            BatteryGlyph(level: level, color: color, charging: charging)
        }
    }
}

/// Un símbolo que rebota al aparecer.
struct BouncingSymbol: View {
    let name: String
    @State private var bounce = false
    var body: some View {
        Image(systemName: name)
            .symbolEffect(.bounce, value: bounce)
            .onAppear { bounce.toggle() }
    }
}

/// El logo de Orbit: un pequeño planeta con anillo y una luna en órbita.
struct OrbitMark: View {
    var size: CGFloat
    @Environment(\.orbitStatic) private var isStatic

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isStatic)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = isStatic ? 0.9 : t * 2.2
            let front = sin(angle) > 0
            let ringHeight = size * 0.34
            let line = max(1, size * 0.075)
            ZStack {
                Ellipse()
                    .trim(from: 0.5, to: 1)
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: size, height: ringHeight)
                if !front { moon(angle, ringHeight) }
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.72, green: 0.52, blue: 1), Color(red: 1, green: 0.42, blue: 0.62)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.56, height: size * 0.56)
                Ellipse()
                    .trim(from: 0, to: 0.5)
                    .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: size, height: ringHeight)
                if front { moon(angle, ringHeight) }
            }
            .rotationEffect(.degrees(-22))
            .frame(width: size, height: size)
        }
    }

    private func moon(_ angle: Double, _ ringHeight: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: size * 0.18, height: size * 0.18)
            .shadow(color: .white.opacity(0.9), radius: size * 0.12)
            .offset(x: cos(angle) * size / 2, y: sin(angle) * ringHeight / 2)
    }
}

/// Contorno visible de la isla (sin el borde pegado a la pantalla).
struct IslandEdge: Shape {
    var island: IslandShape

    var animatableData: IslandShape.AnimatableData {
        get { island.animatableData }
        set { island.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = island.leftHalf(in: rect)
        let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0)
        path.addPath(island.leftHalf(in: rect), transform: mirror)
        return path
    }
}
