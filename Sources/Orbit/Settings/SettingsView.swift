import SwiftUI
import AppKit

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general, battery, connectivity, display, sound, lock, nowPlaying, calendar, tray, lockScreen, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return tr("General", "General")
        case .battery: return tr("Batería", "Battery")
        case .connectivity: return tr("Conectividad", "Connectivity")
        case .display: return tr("Pantalla", "Display")
        case .sound: return tr("Sonido", "Sound")
        case .lock: return tr("Bloqueo", "Lock")
        case .nowPlaying: return tr("Reproduciendo", "Now Playing")
        case .calendar: return tr("Calendario", "Calendar")
        case .tray: return tr("Bandeja de archivos", "File Tray")
        case .lockScreen: return tr("Pantalla bloqueada", "Lock Screen")
        case .about: return tr("Acerca de Orbit", "About Orbit")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .battery: return "battery.75percent"
        case .connectivity: return "airpodspro"
        case .display: return "sun.max.fill"
        case .sound: return "speaker.wave.2.fill"
        case .lock: return "lock.fill"
        case .nowPlaying: return "music.note"
        case .calendar: return "calendar"
        case .tray: return "tray.full.fill"
        case .lockScreen: return "lock.rectangle.stack.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return Color(white: 0.55)
        case .battery: return .green
        case .connectivity: return .blue
        case .display: return .cyan
        case .sound: return .pink
        case .lock: return Color(white: 0.35)
        case .nowPlaying: return .red
        case .calendar: return .orange
        case .tray: return .indigo
        case .lockScreen: return .purple
        case .about: return Color(white: 0.55)
        }
    }
}

struct SettingsIcon: View {
    let section: SettingsSection
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(section.color.gradient)
            .overlay {
                Image(systemName: section.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
    }
}

struct SettingsRoot: View {
    @ObservedObject var router: SettingsRouter
    @ObservedObject private var settings = Settings.shared

    private let notifications: [SettingsSection] = [.battery, .connectivity, .display, .sound, .lock]
    private let activities: [SettingsSection] = [.nowPlaying, .calendar, .tray, .lockScreen]

    var body: some View {
        NavigationSplitView {
            List(selection: $router.selection) {
                Section {
                    row(.general)
                }
                Section(tr("Notificaciones", "Notifications")) {
                    ForEach(notifications) { row($0) }
                }
                Section(tr("Actividades en vivo", "Live Activities")) {
                    ForEach(activities) { row($0) }
                }
                Section {
                    row(.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            SectionDetail(section: router.selection ?? .general)
                .id(router.selection ?? .general)
        }
        .frame(minWidth: 740, minHeight: 520)
    }

    private func row(_ section: SettingsSection) -> some View {
        NavigationLink(value: section) {
            Label {
                Text(section.title)
            } icon: {
                SettingsIcon(section: section)
            }
        }
    }
}

// MARK: - Detalle

struct SectionDetail: View {
    let section: SettingsSection
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            switch section {
            case .general: GeneralSettings()
            case .battery: BatterySettings()
            case .connectivity: ConnectivitySettings()
            case .display: DisplaySettings()
            case .sound: SoundSettings()
            case .lock: LockSettings()
            case .nowPlaying: NowPlayingSettings()
            case .calendar: CalendarSettings()
            case .tray: TraySettings()
            case .lockScreen: LockScreenSettings()
            case .about: AboutSettings()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(section.title)
    }
}

// MARK: - Piezas reutilizables

struct SliderRow: View {
    let title: String
    var subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.1
    var format: (Double) -> String = { String(format: "%.1f s", $0) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { value },
                                      set: { value = min(range.upperBound, max(range.lowerBound, ($0 / step).rounded() * step)) }),
                       in: range)
                    .frame(minWidth: 160, maxWidth: 240)
                Text(format(value))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        } label: {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
    }
}

struct TryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String = tr("Probar en el notch", "Try it on the notch"), action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HStack {
            Spacer()
            Button(action: action) {
                Label(title, systemImage: "sparkles")
            }
            .controlSize(.regular)
        }
    }
}

/// Selector visual con tarjetas, como los de Ajustes del Sistema.
struct StyleCards<Value: Hashable & Identifiable, Preview: View>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    let preview: (Value) -> Preview

    init(_ options: [Value], selection: Binding<Value>, title: @escaping (Value) -> String,
         @ViewBuilder preview: @escaping (Value) -> Preview) {
        self.options = options
        self._selection = selection
        self.title = title
        self.preview = preview
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selection = option }
                } label: {
                    VStack(spacing: 7) {
                        preview(option)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.black.opacity(0.88))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1),
                                                  lineWidth: selected ? 2.5 : 1)
                            )
                            .scaleEffect(selected ? 1 : 0.97)
                        Text(title(option))
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Vista previa animada de la isla

enum PreviewStep {
    case idle(Double)
    case music(Double)
    case expanded(IslandPage, Double)
    case transient(TransientKind, Double)
    case lyrics(Double)

    var duration: Double {
        switch self {
        case .idle(let d), .music(let d), .lyrics(let d): return d
        case .expanded(_, let d), .transient(_, let d): return d
        }
    }
}

struct IslandPreview: View {
    let steps: [PreviewStep]
    var height: CGFloat = 150
    var scale: CGFloat = 1
    var floating = false
    @StateObject private var model = IslandModel(metrics: .preview, isPreview: true)

    var body: some View {
        ZStack(alignment: .top) {
            PreviewWallpaper()
            PreviewMenuBar(scale: scale)
            IslandCanvas(model: model)
                .services(Services.demo)
                .scaleEffect(scale, anchor: .top)
                .frame(width: model.canvasSize.width * scale, height: model.canvasSize.height * scale, alignment: .top)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .padding(.vertical, 4)
        .task {
            model.metrics = floating ? .previewFloating() : .preview
            await loop()
        }
    }

    private func loop() async {
        guard !steps.isEmpty else { return }
        while !Task.isCancelled {
            for step in steps {
                apply(step)
                try? await Task.sleep(nanoseconds: UInt64(step.duration * 1_000_000_000))
                if Task.isCancelled { return }
            }
        }
    }

    private func apply(_ step: PreviewStep) {
        switch step {
        case .idle:
            model.expanded = false
            model.liveMusic = false
            model.clearTransient()
        case .music:
            model.clearTransient()
            model.expanded = false
            model.lyricsMode = false
            model.liveMusic = true
        case .lyrics:
            model.page = .music
            model.lyricsMode = true
            model.expanded = true
        case .expanded(let page, _):
            model.lyricsMode = false
            model.page = page
            model.expanded = true
        case .transient(let kind, _):
            model.expanded = false
            model.show(kind, for: nil)
        }
    }
}

struct PreviewWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.08, blue: 0.3),
                                    Color(red: 0.36, green: 0.16, blue: 0.5),
                                    Color(red: 0.93, green: 0.45, blue: 0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 1, green: 0.75, blue: 0.45).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.85, y: 1.1), startRadius: 10, endRadius: 320)
            RadialGradient(colors: [Color(red: 0.3, green: 0.55, blue: 1).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.1, y: 0.2), startRadius: 10, endRadius: 260)
        }
    }
}

struct PreviewMenuBar: View {
    var scale: CGFloat = 1

    var body: some View {
        let size = 12 * scale
        HStack(spacing: 14 * scale) {
            Image(systemName: "apple.logo").font(.system(size: size, weight: .semibold))
            Text("Finder").font(.system(size: size, weight: .bold))
            Text(tr("Archivo", "File")).font(.system(size: size))
            Text(tr("Edición", "Edit")).font(.system(size: size))
            Spacer()
            Image(systemName: "wifi").font(.system(size: size - 1, weight: .semibold))
            Image(systemName: "battery.75percent").font(.system(size: size))
            Text(tr("vie 9:41", "Fri 9:41")).font(.system(size: size, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 14 * scale)
        .frame(height: 32 * scale)
        .background(Color.white.opacity(0.12))
    }
}
