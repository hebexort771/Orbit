import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExpandedContent: View {
    @ObservedObject var model: IslandModel
    let page: IslandPage
    let layout: IslandLayout

    var body: some View {
        let motion = Motion.current()
        VStack(spacing: 0) {
            IslandHeader(model: model, layout: layout)
                .staggered(0)
            ZStack(alignment: .top) {
                pageView
                    .id(page)
                    .transition(.orbitContent(motion))
            }
            .frame(width: layout.width)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(motion.content, value: page)
        }
        .frame(width: layout.width, height: layout.height, alignment: .top)
    }

    @ViewBuilder
    private var pageView: some View {
        switch page {
        case .music: ExpandedMusic(model: model, width: layout.width)
        case .calendar: CalendarPage()
        case .tray: TrayPage(model: model)
        }
    }
}

// MARK: - Encabezado

struct IslandHeader: View {
    @ObservedObject var model: IslandModel
    let layout: IslandLayout
    @EnvironmentObject private var battery: BatteryService
    @Namespace private var tabs

    var body: some View {
        let metrics = model.metrics
        let side = max(0, (layout.width - metrics.notchWidth) / 2)
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                if model.pages.count > 1 {
                    ForEach(model.pages) { page in tab(page) }
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.white.opacity(model.pages.count > 1 ? 0.07 : 0)))
            .padding(.leading, 16)
            .frame(width: side, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if battery.hasBattery {
                    HStack(spacing: 4) {
                        Text("\(battery.level)%")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        BatteryGlyph(level: battery.level,
                                     color: battery.charging ? .orbitGreen : (battery.level <= 20 ? .orbitRed : .white),
                                     charging: battery.charging, width: 21)
                    }
                }
                Button { AppActions.openSettings() } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(OrbitButtonStyle(size: 24))
            }
            .padding(.trailing, 14)
            .frame(width: side, alignment: .trailing)
        }
        .frame(width: layout.width, height: metrics.notchHeight)
        .foregroundStyle(.white.opacity(0.85))
    }

    private func tab(_ page: IslandPage) -> some View {
        let selected = model.page == page && !model.dragActive
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) { model.page = page }
        } label: {
            Image(systemName: page.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.62))
                .frame(width: 30, height: 20)
                .background {
                    if selected {
                        Capsule().fill(Color.white).matchedGeometryEffect(id: "tab", in: tabs)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(page.title)
    }
}

// MARK: - Música expandida

struct ExpandedMusic: View {
    @ObservedObject var model: IslandModel
    let width: CGFloat
    @EnvironmentObject private var media: NowPlayingService
    @EnvironmentObject private var audio: AudioService
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        if let track = media.track {
            VStack(spacing: 9) {
                Group {
                    if model.lyricsMode && settings.lyricsEnabled {
                        LyricsLines(fontSize: 14, accent: media.accent)
                            .frame(height: 62)
                    } else {
                        info(track)
                    }
                }
                .staggered(1)
                MediaProgress(accent: media.accent)
                    .staggered(2)
                controls
                    .staggered(3)
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
        } else {
            empty.staggered(1)
        }
    }

    private func info(_ track: TrackInfo) -> some View {
        HStack(spacing: 14) {
            ArtworkView(size: 60, radius: 14)
                .modifier(MatchedArt())
                .shadow(color: media.accent.opacity(0.55), radius: 14, y: 4)
                .onTapGesture { media.openSourceApp() }
                .help(tr("Abrir la app", "Open the app"))
            VStack(alignment: .leading, spacing: 3) {
                MarqueeText(text: track.title, size: 15, weight: .semibold, width: max(80, width - 44 - 74 - 50))
                Text(track.artist.isEmpty ? track.album : track.artist)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Waveform(playing: media.isPlaying, style: settings.waveformStyle, color: media.accent, bars: 5, barWidth: 3)
                .frame(width: 28, height: 22)
        }
        .frame(height: 62)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { model.lyricsMode.toggle() }
            } label: {
                Image(systemName: model.lyricsMode ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.lyricsMode ? media.accent : Color.white.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(OrbitButtonStyle(size: 30))
            .opacity(settings.lyricsEnabled ? 1 : 0)
            .disabled(!settings.lyricsEnabled)
            .help(tr("Letra", "Lyrics"))

            Spacer(minLength: 0)
            MediaControls(accent: media.accent)
            Spacer(minLength: 0)

            Button { AppActions.showOutputMenu() } label: {
                Image(systemName: audio.output.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(OrbitButtonStyle(size: 30))
            .help(audio.deviceName)
        }
        .foregroundStyle(.white)
    }

    private var empty: some View {
        VStack(spacing: 7) {
            Image(systemName: "music.note.list")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(tr("Nada en reproducción", "Nothing playing"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(tr("Pon música en Música, Spotify o tu navegador", "Play something in Music, Spotify or your browser"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Button {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            } label: {
                Text(tr("Abrir Música", "Open Music"))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Calendario

struct CalendarPage: View {
    @EnvironmentObject private var calendar: CalendarService
    @State private var selected = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            dayColumn
                .frame(width: 168, alignment: .leading)
                .staggered(1)
            MonthGrid(selected: $selected)
                .staggered(2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
    }

    private var weekday: String {
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.dateFormat = "EEE"
        return formatter.string(from: selected).replacingOccurrences(of: ".", with: "").uppercased()
    }

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: selected))
    }

    private var dayColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(weekday)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.orbitRed)
            Text(dayNumber)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .padding(.bottom, 4)
            events
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
    }

    @ViewBuilder
    private var events: some View {
        if calendar.access != .granted {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Ve tus eventos aquí", "See your events here"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Button { calendar.requestAccess() } label: {
                    Label(tr("Conectar calendario", "Connect calendar"), systemImage: "calendar.badge.plus")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        } else {
            let list = calendar.events(on: selected)
            if list.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("No hay eventos", "No events"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(Calendar.current.isDateInToday(selected) ? tr("Tu día está libre", "Your day is clear")
                                                                   : tr("Día libre", "Free day"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(list.prefix(2)) { event in
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3, height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(timeText(event))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    if list.count > 2 {
                        Text(tr("y \(list.count - 2) más", "and \(list.count - 2) more"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
        }
    }

    private func timeText(_ event: DayEvent) -> String {
        if event.allDay { return tr("Todo el día", "All day") }
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: event.start) + " – " + formatter.string(from: event.end)
    }
}

struct MonthGrid: View {
    @Binding var selected: Date
    @State private var offset = 0

    private let cell: CGFloat = 28
    private let row: CGFloat = 17

    var body: some View {
        let calendar = Calendar.current
        let month = calendar.date(byAdding: .month, value: offset, to: monthStart(Date())) ?? Date()
        let days = gridDays(month)
        VStack(spacing: 3) {
            HStack {
                Text(title(month))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { withAnimation(.spring(response: 0.35)) { offset -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(OrbitButtonStyle(size: 18))
                Button { withAnimation(.spring(response: 0.35)) { offset += 1 } } label: {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(OrbitButtonStyle(size: 18))
            }
            .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols().enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: cell)
                }
            }
            ForEach(0..<(days.count / 7), id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        dayCell(days[week * 7 + index], month: month)
                    }
                }
            }
        }
        .frame(width: cell * 7)
        .id(offset)
        .transition(.opacity)
    }

    private func dayCell(_ day: Date, month: Date) -> some View {
        let calendar = Calendar.current
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        return Text("\(calendar.component(.day, from: day))")
            .font(.system(size: 10.5, weight: isToday ? .bold : .medium).monospacedDigit())
            .foregroundStyle(isToday ? Color.white : Color.white.opacity(inMonth ? 0.85 : 0.22))
            .frame(width: 20, height: 16)
            .background {
                if isToday {
                    Capsule().fill(Color.orbitRed)
                } else if isSelected {
                    Capsule().fill(Color.white.opacity(0.18))
                }
            }
            .frame(width: cell, height: row)
            .contentShape(Rectangle())
            .onTapGesture { selected = day }
    }

    private func monthStart(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func gridDays(_ month: Date) -> [Date] {
        let calendar = Calendar.current
        let start = monthStart(month)
        let weekday = calendar.component(.weekday, from: start)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let rows = Int(ceil(Double(lead + count) / 7.0))
        guard let first = calendar.date(byAdding: .day, value: -lead, to: start) else { return [] }
        return (0..<(rows * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private func weekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        let symbols = formatter.veryShortWeekdaySymbols ?? ["D", "L", "M", "X", "J", "V", "S"]
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func title(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        let text = formatter.string(from: month)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

// MARK: - Bandeja de archivos

struct TrayPage: View {
    @ObservedObject var model: IslandModel
    @Environment(\.orbitStatic) private var isStatic
    @EnvironmentObject private var tray: TrayStore
    @ObservedObject private var settings = Settings.shared
    @State private var trayTargeted = false
    @State private var airTargeted = false
    @State private var pageTargeted = false

    var body: some View {
        Group {
            if model.dragActive {
                dropZones
            } else if tray.items.isEmpty {
                empty
            } else {
                list
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .live(!isStatic) {
            $0.onDrop(of: [UTType.fileURL], isTargeted: $pageTargeted) { providers in
                receive(providers)
                return true
            }
        }
    }

    private func receive(_ providers: [NSItemProvider]) {
        TrayStore.loadURLs(from: providers) { urls in
            let added = tray.add(urls)
            if added > 0 { Haptics.level() }
            model.page = .tray
            model.expanded = true
            model.dragActive = false
        }
    }

    private var dropZones: some View {
        HStack(spacing: 12) {
            zone(symbol: "tray.and.arrow.down.fill", title: tr("Guardar en la bandeja", "Keep in tray"),
                 color: .orbitBlue, targeted: trayTargeted)
                .live(!isStatic) {
                    $0.onDrop(of: [UTType.fileURL], isTargeted: $trayTargeted) { providers in
                        receive(providers)
                        return true
                    }
                }
                .staggered(1)
            if settings.trayAirDrop {
                zone(symbol: "dot.radiowaves.left.and.right", title: "AirDrop",
                     color: .orbitViolet, targeted: airTargeted)
                    .live(!isStatic) {
                        $0.onDrop(of: [UTType.fileURL], isTargeted: $airTargeted) { providers in
                            TrayStore.loadURLs(from: providers) { urls in
                                model.dragActive = false
                                tray.airDrop(urls)
                            }
                            return true
                        }
                    }
                    .staggered(2)
            }
        }
    }

    private func zone(symbol: String, title: String, color: Color, targeted: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(targeted ? color : Color.white.opacity(0.75))
                .symbolEffect(.bounce, value: targeted)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(targeted ? 1 : 0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color.opacity(targeted ? 0.18 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(targeted ? color : Color.white.opacity(0.25),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .scaleEffect(targeted ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: targeted)
    }

    private var empty: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(pageTargeted ? Color.orbitBlue : Color.white.opacity(0.55))
            Text(tr("Arrastra archivos al notch", "Drag files onto the notch"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(tr("Quedan aquí para usarlos cuando quieras", "They stay here until you need them"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .staggered(1)
    }

    private var list: some View {
        VStack(spacing: 6) {
            HStack {
                Text(tr("\(tray.items.count) en la bandeja", "\(tray.items.count) in tray"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if settings.trayAirDrop {
                    Button { tray.airDrop(tray.items.map(\.url)) } label: {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(OrbitButtonStyle(size: 22))
                    .help("AirDrop")
                }
                Button { withAnimation(.spring(response: 0.35)) { tray.clear() } } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(OrbitButtonStyle(size: 22))
                .help(tr("Vaciar", "Clear"))
            }
            .foregroundStyle(.white.opacity(0.7))
            if isStatic {
                tiles.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) { tiles }
            }
        }
        .staggered(1)
    }
}

extension TrayPage {
    fileprivate var tiles: some View {
        HStack(spacing: 8) {
            ForEach(Array(tray.items.enumerated()), id: \.element.id) { index, item in
                TrayTile(item: item)
                    .staggered(index + 1)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 2)
    }
}

struct TrayTile: View {
    let item: TrayItem
    @EnvironmentObject private var tray: TrayStore
    @Environment(\.orbitStatic) private var isStatic
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: tray.icon(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 66)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovered ? 0.1 : 0)))
        .scaleEffect(hovered ? 1.05 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        .onHover { hovered = $0 }
        .live(!isStatic) { $0.onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() } }
        .onTapGesture(count: 2) { tray.open(item) }
        .contextMenu {
            Button(tr("Abrir", "Open")) { tray.open(item) }
            Button(tr("Mostrar en Finder", "Show in Finder")) { tray.reveal(item) }
            Button("AirDrop") { tray.airDrop([item.url]) }
            Divider()
            Button(tr("Quitar de la bandeja", "Remove from tray")) { withAnimation { tray.remove(item) } }
        }
        .help(item.name)
    }
}
