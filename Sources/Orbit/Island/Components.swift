import SwiftUI
import AppKit

/// Acciones globales (las conecta AppDelegate).
@MainActor
enum AppActions {
    static var openSettings: () -> Void = {}
    static var quit: () -> Void = { NSApp.terminate(nil) }
    static var showOutputMenu: () -> Void = {}
    static var collapse: () -> Void = {}
}

// MARK: - Alas a los lados del notch

struct Wings<Left: View, Right: View>: View {
    let notch: CGFloat
    let wing: CGFloat
    let height: CGFloat
    let left: Left
    let right: Right

    init(notch: CGFloat, wing: CGFloat, height: CGFloat,
         @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.notch = notch
        self.wing = wing
        self.height = height
        self.left = left()
        self.right = right()
    }

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: wing, height: height)
            Color.clear.frame(width: notch, height: height)
            right.frame(width: wing, height: height)
        }
    }
}

// MARK: - Portada con giro 3D

struct FlipModifier: ViewModifier {
    var angle: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .opacity(abs(angle) > 88 ? 0 : 1)
    }
}

extension AnyTransition {
    static var cardFlip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0))
                .animation(.spring(response: 0.42, dampingFraction: 0.72).delay(0.16)),
            removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))
                .animation(.easeIn(duration: 0.16))
        )
    }
}

struct ArtworkView: View {
    @EnvironmentObject private var media: NowPlayingService
    @ObservedObject private var settings = Settings.shared
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        ZStack {
            art(media.artwork)
                .id(media.artworkSerial)
                .transition(settings.artworkFlip ? .cardFlip : .opacity.animation(.easeInOut(duration: 0.3)))
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func art(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Onda de audio

struct Waveform: View {
    var playing: Bool
    var style: WaveformStyle
    var color: Color
    var bars: Int = 4
    var barWidth: CGFloat = 3
    @Environment(\.orbitStatic) private var isStatic

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing || isStatic)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = max(1, bars)
                let gap = count > 1 ? (size.width - CGFloat(count) * barWidth) / CGFloat(count - 1) : 0
                for index in 0..<count {
                    let level = playing ? amplitude(index, t) : (isStatic ? staticLevel(index) : 0.2)
                    let height = max(barWidth, size.height * level)
                    let rect = CGRect(x: CGFloat(index) * (barWidth + gap),
                                      y: (size.height - height) / 2,
                                      width: barWidth, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: shading(size))
                }
            }
        }
    }

    private func amplitude(_ index: Int, _ t: Double) -> CGFloat {
        let i = Double(index)
        let a = sin(t * (5.1 + i * 1.9) + i * 1.3) * 0.5 + 0.5
        let b = sin(t * (2.3 + i * 0.7) + i * 2.9) * 0.5 + 0.5
        let c = sin(t * (11.0 - i) + i * 0.7) * 0.5 + 0.5
        return CGFloat(0.18 + 0.82 * (a * 0.55 + b * 0.3 + c * 0.15))
    }

    private func staticLevel(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [0.45, 0.95, 0.6, 0.8, 0.4]
        return pattern[index % pattern.count]
    }

    private func shading(_ size: CGSize) -> GraphicsContext.Shading {
        switch style {
        case .mono:
            return .color(.white)
        case .colored:
            return .color(color)
        case .gradient:
            return .linearGradient(Gradient(colors: [color, Color.white]),
                                   startPoint: CGPoint(x: 0, y: size.height),
                                   endPoint: CGPoint(x: size.width, y: 0))
        }
    }
}

// MARK: - Barra de nivel (volumen / brillo)

struct LevelBar: View {
    var value: Double
    var style: BarStyle
    var accent: Color
    var animation: Animation?

    private var fill: Color { style == .accent ? accent : .white }

    var body: some View {
        GeometryReader { geo in
            if style == .segments {
                HStack(spacing: 2) {
                    ForEach(0..<10, id: \.self) { index in
                        Capsule()
                            .fill(Double(index) < (value * 10).rounded(.up) ? Color.white : Color.white.opacity(0.18))
                    }
                }
            } else {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(fill)
                        .frame(width: max(geo.size.height, geo.size.width * CGFloat(value)))
                        .opacity(value > 0.001 ? 1 : 0)
                }
            }
        }
        .animation(animation, value: value)
    }
}

// MARK: - Batería

struct BatteryGlyph: View {
    var level: Int
    var color: Color
    var charging: Bool
    var width: CGFloat = 25
    var animated = true
    @Environment(\.orbitStatic) private var isStatic
    @State private var filled = false

    var body: some View {
        let height = width * 0.5
        let inner = width - 4.4
        let shown = filled || isStatic || !animated
        let fraction = CGFloat(min(100, max(0, level))) / 100
        HStack(spacing: 1.2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.42), lineWidth: 1.1)
                RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2.5, inner * (shown ? fraction : fraction * 0.12)), height: height - 4.4)
                    .shadow(color: charging ? color.opacity(0.8) : .clear, radius: 3)
                    .padding(.leading, 2.2)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.72, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .symbolEffect(.pulse, options: .repeating, isActive: !isStatic && animated)
                        .frame(width: width)
                }
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .frame(width: 1.8, height: height * 0.36)
        }
        .onAppear {
            guard animated, !isStatic else { return }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.82).delay(0.2)) { filled = true }
        }
    }
}

struct RingGauge: View {
    var value: Double
    var color: Color
    var lineWidth: CGFloat = 2.6
    @Environment(\.orbitStatic) private var isStatic
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: (shown || isStatic) ? value : 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.25)) { shown = true }
        }
    }
}

// MARK: - Texto que se desplaza si no cabe

struct MarqueeText: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let width: CGFloat
    var color: Color = .white

    @Environment(\.orbitStatic) private var isStatic
    @State private var running = false

    private var nsWeight: NSFont.Weight {
        switch weight {
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        default: return .regular
        }
    }

    private var textWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: nsWeight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
    }

    var body: some View {
        let overflow = textWidth > width
        let gap: CGFloat = 36
        let label = Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
        HStack(spacing: gap) {
            label
            if overflow { label }
        }
        .offset(x: running && overflow && !isStatic ? -(textWidth + gap) : 0)
        .animation(running && overflow && !isStatic
                   ? .linear(duration: Double(textWidth + gap) / 28).delay(1.6).repeatForever(autoreverses: false)
                   : .default,
                   value: running)
        .frame(width: width, alignment: .leading)
        .clipped()
        .mask {
            if overflow {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                       .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            } else {
                Rectangle()
            }
        }
        .onAppear { running = true }
        .onChange(of: text) {
            running = false
            Task { @MainActor in running = true }
        }
    }
}

// MARK: - Botones

struct OrbitButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    var highlighted = false

    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration, size: size, highlighted: highlighted)
    }
}

private struct HoverButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let highlighted: Bool
    @State private var hovered = false

    var body: some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                Circle().fill(Color.white.opacity(highlighted ? 0.16 : (hovered ? 0.12 : 0)))
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.82 : (hovered ? 1.06 : 1))
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovered)
            .onHover { hovered = $0 }
    }
}

// MARK: - Progreso de la canción

struct MediaProgress: View {
    @EnvironmentObject private var media: NowPlayingService
    var accent: Color
    var compactTimes = false
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let duration = media.track?.duration ?? 0
            let live = media.elapsed(at: timeline.date)
            let elapsed = dragFraction.map { $0 * duration } ?? live
            let fraction = duration > 0 ? min(1, max(0, elapsed / duration)) : 0
            HStack(spacing: 10) {
                Text(TimeText.clock(elapsed))
                    .frame(width: 38, alignment: .trailing)
                bar(fraction, duration: duration)
                Text("-" + TimeText.clock(max(0, duration - elapsed)))
                    .frame(width: 42, alignment: .leading)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
        .frame(height: 16)
    }

    private func bar(_ fraction: Double, duration: Double) -> some View {
        GeometryReader { geo in
            let active = hovering || dragFraction != nil
            let height: CGFloat = active ? 7 : 4.5
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.75), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * CGFloat(fraction)))
                    .shadow(color: accent.opacity(active ? 0.6 : 0), radius: 6)
                    .animation(dragFraction == nil ? .linear(duration: 0.5) : nil, value: fraction)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = min(1, max(0, Double(value.location.x / max(1, geo.size.width))))
                    }
                    .onEnded { value in
                        let f = min(1, max(0, Double(value.location.x / max(1, geo.size.width))))
                        media.seek(to: f * duration)
                        dragFraction = nil
                    }
            )
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
        }
    }
}

// MARK: - Controles

struct MediaControls: View {
    @EnvironmentObject private var media: NowPlayingService
    var accent: Color
    var big = false

    var body: some View {
        HStack(spacing: big ? 18 : 10) {
            Button { media.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(media.shuffleOn ? accent : Color.white.opacity(0.55))
            }
            .buttonStyle(OrbitButtonStyle(size: 30))

            Button { media.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: big ? 20 : 17, weight: .semibold))
            }
            .buttonStyle(OrbitButtonStyle(size: big ? 42 : 36))

            Button { media.togglePlay() } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: big ? 28 : 24, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(OrbitButtonStyle(size: big ? 50 : 42))

            Button { media.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: big ? 20 : 17, weight: .semibold))
            }
            .buttonStyle(OrbitButtonStyle(size: big ? 42 : 36))

            Button { media.cycleRepeat() } label: {
                Image(systemName: media.repeatMode == 2 ? "repeat.1" : "repeat")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(media.repeatMode != 1 ? accent : Color.white.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(OrbitButtonStyle(size: 30))
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Letras sincronizadas

struct LyricsLines: View {
    @EnvironmentObject private var media: NowPlayingService
    var fontSize: CGFloat = 14
    var accent: Color
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let current = media.currentLyricIndex(at: media.elapsed(at: timeline.date)) ?? -1
            content(current)
        }
        .clipped()
    }

    @ViewBuilder
    private func content(_ current: Int) -> some View {
        if media.lyrics.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: media.lyricsState == .loading ? "ellipsis" : "quote.bubble")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: media.lyricsState == .loading)
                Text(media.lyricsState == .loading ? tr("Buscando la letra…", "Looking for lyrics…")
                                                   : tr("Letra no disponible", "Lyrics unavailable"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let indices = Array(max(-1, current - 1)...(current + 1)).filter { $0 >= 0 && $0 < media.lyrics.count }
            VStack(alignment: alignment, spacing: 5) {
                ForEach(indices, id: \.self) { index in
                    let text = media.lyrics[index].text
                    Text(text.isEmpty ? "♪" : text)
                        .font(.system(size: index == current ? fontSize + 1 : fontSize - 1,
                                      weight: index == current ? .bold : .semibold))
                        .foregroundStyle(index == current ? Color.white : Color.white.opacity(0.32))
                        .lineLimit(1)
                        .shadow(color: index == current ? accent.opacity(0.55) : .clear, radius: 8)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: current)
        }
    }
}
