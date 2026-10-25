import SwiftUI
import AppKit
import ApplicationServices

@MainActor
private var island: IslandController? { AppDelegate.shared?.island }

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject private var settings = Settings.shared
    @State private var launchAtLogin = AppDelegate.launchAtLogin

    var body: some View {
        Section {
            IslandPreview(steps: [.idle(1.1), .transient(.welcome, 2.8), .music(2.2), .expanded(.music, 3.2), .music(1.4)],
                          height: 200, scale: 0.9, floating: false)
            TryButton { island?.welcome() }
        }

        Section(tr("Comportamiento", "Behavior")) {
            Toggle(isOn: $launchAtLogin) {
                Text(tr("Abrir al iniciar sesión", "Open at login"))
            }
            .onChange(of: launchAtLogin) { _, value in AppDelegate.launchAtLogin = value }

            Toggle(isOn: $settings.hoverToOpen) {
                Text(tr("Abrir al pasar el cursor", "Open on hover"))
                Text(tr("Si lo desactivas, haz clic en el notch para abrirlo", "When off, click the notch to open it"))
            }
            if settings.hoverToOpen {
                SliderRow(title: tr("Retraso al pasar el cursor", "Hover delay"), value: $settings.hoverDelay,
                          range: 0...0.8, step: 0.05, format: { String(format: "%.2f s", $0) })
            }
            Toggle(isOn: $settings.swipePages) {
                Text(tr("Deslizar para cambiar de página", "Swipe to change pages"))
                Text(tr("Desliza con dos dedos en el trackpad sobre la isla abierta", "Two-finger swipe over the open island"))
            }
            Toggle(tr("Respuesta háptica del trackpad", "Trackpad haptic feedback"), isOn: $settings.haptics)
            Toggle(tr("Icono en la barra de menús", "Menu bar icon"), isOn: $settings.menuBarIcon)
        }

        Section(tr("Animación", "Animation")) {
            StyleCards(AnimationStyle.allCases, selection: $settings.animationStyle, title: { $0.title }) { style in
                AnimationStylePreview(style: style)
            }
            Text(settings.animationStyle.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            SliderRow(title: tr("Velocidad", "Speed"), value: $settings.animationSpeed, range: 0.6...1.6, step: 0.05,
                      format: { String(format: "%.0f%%", $0 * 100) })
            Toggle(isOn: $settings.comet) {
                Text(tr("Estela orbital", "Orbit trail"))
                Text(tr("Un destello de luz recorre la isla cuando llega algo nuevo", "A streak of light circles the island when something new arrives"))
            }
            Toggle(isOn: $settings.ambientGlow) {
                Text(tr("Brillo ambiental", "Ambient glow"))
                Text(tr("La isla brilla con el color de la portada o del aviso", "The island glows with the artwork or alert color"))
            }
        }

        Section(tr("Pantallas", "Displays")) {
            Picker(tr("Mostrar en", "Show on"), selection: $settings.display) {
                ForEach(DisplayChoice.allCases) { Text($0.title).tag($0) }
            }
            Picker(selection: $settings.virtualStyle) {
                ForEach(VirtualStyle.allCases) { Text($0.title).tag($0) }
            } label: {
                Text(tr("En pantallas sin notch", "On screens without a notch"))
                Text(tr("Monitores externos y Mac sin notch", "External monitors and Macs without a notch"))
            }
            Picker(tr("Visibilidad sin notch", "Visibility without notch"), selection: $settings.virtualVisibility) {
                ForEach(VirtualVisibility.allCases) { Text($0.title).tag($0) }
            }
        }

        Section(tr("Idioma", "Language")) {
            Picker(tr("Idioma de Orbit", "Orbit language"), selection: $settings.language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
        }
    }
}

struct AnimationStylePreview: View {
    let style: AnimationStyle
    @State private var open = false

    var body: some View {
        let response: Double
        let damping: Double
        switch style {
        case .orbit: response = 0.45; damping = 0.6
        case .smooth: response = 0.55; damping = 1
        case .snappy: response = 0.22; damping = 0.9
        }
        return VStack {
            IslandShape(ear: open ? 7 : 3, bottom: open ? 14 : 6, topCorner: 0)
                .fill(Color.black)
                .overlay(
                    IslandShape(ear: open ? 7 : 3, bottom: open ? 14 : 6, topCorner: 0)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .frame(width: open ? 104 : 54, height: open ? 34 : 12)
                .animation(.spring(response: response, dampingFraction: damping), value: open)
            Spacer(minLength: 0)
        }
        .padding(.top, 0)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                open.toggle()
            }
        }
    }
}

// MARK: - Batería

struct BatterySettings: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Section {
            IslandPreview(steps: [.idle(1), .transient(.battery(.charging(80)), 2.6), .idle(0.9),
                                  .transient(.battery(.low(15)), 2.6), .idle(0.9), .transient(.battery(.full), 2.4)])
            TryButton { island?.demo(.battery(.charging(80))) }
        }
        Section {
            Toggle(isOn: $settings.batteryEnabled) {
                Text(tr("Avisos de batería", "Battery alerts"))
                Text(tr("Al conectar o desconectar el cargador", "When you plug in or unplug the charger"))
            }
            Toggle(tr("Mostrar porcentaje", "Show percentage"), isOn: $settings.batteryPercent)
            Toggle(tr("Avisar con batería baja (20 %, 10 % y 5 %)", "Warn on low battery (20%, 10% and 5%)"), isOn: $settings.batteryLow)
            Toggle(tr("Avisar cuando termine de cargar", "Tell me when fully charged"), isOn: $settings.batteryFull)
            SliderRow(title: tr("Duración", "Duration"), value: $settings.batteryDuration, range: 1...6, step: 0.2)
        }
    }
}

// MARK: - Conectividad

struct ConnectivitySettings: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Section {
            IslandPreview(steps: [.idle(1), .transient(.bluetooth(name: "AirPods Pro", symbol: "airpodspro", battery: 85, connected: true), 2.8),
                                  .idle(0.9), .transient(.bluetooth(name: "Magic Keyboard", symbol: "keyboard.fill", battery: nil, connected: true), 2.4)])
            TryButton { island?.demo(.bluetooth(name: "AirPods Pro", symbol: "airpodspro", battery: 85, connected: true)) }
        }
        Section {
            Toggle(isOn: $settings.bluetoothEnabled) {
                Text(tr("Dispositivos Bluetooth", "Bluetooth devices"))
                Text(tr("AirPods, audífonos, teclados, ratones y mandos", "AirPods, headphones, keyboards, mice and controllers"))
            }
            Toggle(tr("Mostrar batería (AirPods y Beats)", "Show battery (AirPods and Beats)"), isOn: $settings.bluetoothBattery)
            Toggle(tr("Avisar también al desconectar", "Also alert on disconnect"), isOn: $settings.bluetoothDisconnect)
            SliderRow(title: tr("Duración", "Duration"), value: $settings.bluetoothDuration, range: 1...6, step: 0.2)
        }
    }
}

// MARK: - Pantalla

struct DisplaySettings: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Section {
            IslandPreview(steps: [.idle(1), .transient(.brightness(level: 0.35), 1.2), .transient(.brightness(level: 0.55), 1.1),
                                  .transient(.brightness(level: 0.8), 1.6)])
            TryButton { island?.demo(.brightness(level: Brightness.get() ?? 0.7)) }
        }
        Section {
            Toggle(isOn: $settings.brightnessEnabled) {
                Text(tr("Indicador de brillo", "Brightness indicator"))
                Text(tr("Funciona junto con «Reemplazar el indicador del sistema» en Sonido", "Works together with “Replace the system indicator” in Sound"))
            }
            AccessibilityRow()
        }
    }
}

// MARK: - Sonido

struct SoundSettings: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Section {
            IslandPreview(steps: [.idle(0.9), .transient(.volume(level: 0.3, muted: false, output: .speaker), 0.8),
                                  .transient(.volume(level: 0.45, muted: false, output: .speaker), 0.7),
                                  .transient(.volume(level: 0.62, muted: false, output: .speaker), 1.6),
                                  .transient(.volume(level: 0.62, muted: true, output: .speaker), 1.4)])
            TryButton { island?.demo(.volume(level: AppDelegate.shared?.services?.audio.volume ?? 0.5, muted: false, output: .speaker)) }
        }
        Section {
            Toggle(isOn: $settings.soundEnabled) {
                Text(tr("Indicador de volumen", "Volume indicator"))
            }
            Toggle(isOn: $settings.replaceSystemHUD) {
                Text(tr("Reemplazar el indicador del sistema", "Replace the system indicator"))
                Text(tr("Oculta el de macOS y usa solo el de Orbit (también para el brillo)", "Hides macOS’s and uses only Orbit’s (brightness too)"))
            }
            if settings.replaceSystemHUD { AccessibilityRow() }
            Toggle(tr("Mostrar el dispositivo de salida", "Show the output device"), isOn: $settings.soundShowDevice)
            Toggle(tr("Mostrar porcentaje", "Show percentage"), isOn: $settings.soundPercent)
            SliderRow(title: tr("Duración", "Duration"), value: $settings.soundDuration, range: 0.6...4, step: 0.1)
        }
        Section(tr("Estilo de la barra", "Bar style")) {
            StyleCards(BarStyle.allCases, selection: $settings.soundBarStyle, title: { $0.title }) { style in
                LevelBar(value: 0.62, style: style, accent: .accentColor, animation: nil)
                    .frame(width: 70, height: 6)
            }
            Picker(tr("Animación", "Animation"), selection: $settings.soundAnimation) {
                ForEach(HUDAnimation.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct AccessibilityRow: View {
    @State private var trusted = MediaKeyTap.isTrusted

    var body: some View {
        LabeledContent {
            if trusted {
                Label(tr("Permitido", "Allowed"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(tr("Dar permiso…", "Grant access…")) {
                    MediaKeyTap.requestTrust()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } label: {
            Text(tr("Accesibilidad", "Accessibility"))
            Text(tr("Necesario para leer las teclas de volumen y brillo", "Needed to read the volume and brightness keys"))
        }
        .task {
            while !Task.isCancelled {
                let now = MediaKeyTap.isTrusted
                if now != trusted {
                    trusted = now
                    if now { island?.updateKeyTap() }
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }
}

// MARK: - Bloqueo

struct LockSettings: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Section {
            IslandPreview(steps: [.idle(1), .transient(.lock(locked: true), 2.2), .transient(.lock(locked: false), 1.6)])
            TryButton { island?.demo(.lock(locked: true)) }
        }
        Section {
            Toggle(isOn: $settings.lockEnabled) {
                Text(tr("Candado al bloquear y desbloquear", "Lock icon when locking and unlocking"))
                Text(tr("Aparece en la pantalla de bloqueo y se abre al entrar", "Appears on the lock screen and opens when you log in"))
            }
        }
    }
}

// MARK: - Reproduciendo

struct NowPlayingSettings: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var demoMedia = Services.demo.media

    var body: some View {
        Section {
            IslandPreview(steps: [.music(2.2), .expanded(.music, 3.4), .lyrics(3.2), .music(1.2)], height: 214, scale: 0.88)
            TryButton { island?.demoExpanded(.music) }
        }
        Section {
            Toggle(isOn: $settings.musicEnabled) {
                Text(tr("Mostrar lo que se reproduce", "Show what’s playing"))
                Text(tr("Música, Spotify, Podcasts, YouTube en el navegador y más", "Music, Spotify, Podcasts, YouTube in the browser and more"))
            }
            SliderRow(title: tr("Tiempo en pausa", "Idle duration"),
                      subtitle: tr("Cuánto sigue visible después de pausar", "How long it stays after pausing"),
                      value: $settings.musicIdle, range: 1...15, step: 0.5)
        }
        Section(tr("Onda de audio", "Waveform")) {
            StyleCards(WaveformStyle.allCases, selection: $settings.waveformStyle, title: { $0.title }) { style in
                Waveform(playing: true, style: style, color: demoMedia.accent, bars: 5, barWidth: 3.5)
                    .frame(width: 34, height: 26)
            }
            Toggle(tr("Onda en la vista compacta", "Compact waveform"), isOn: $settings.compactWaveform)
        }
        Section(tr("Detalles", "Details")) {
            Toggle(tr("Girar la portada al cambiar de canción", "Flip the artwork on track change"), isOn: $settings.artworkFlip)
            Toggle(tr("Colores de la portada", "Artwork colors"), isOn: $settings.artworkAccent)
            Toggle(isOn: $settings.lyricsEnabled) {
                Text(tr("Letras sincronizadas", "Synced lyrics"))
                Text(tr("Desde LRCLIB, se buscan automáticamente", "From LRCLIB, fetched automatically"))
            }
            Toggle(tr("Ocultar si la app de música está al frente", "Hide while the music app is in front"), isOn: $settings.hideWhenSourceActive)
        }
    }
}

// MARK: - Calendario

struct CalendarSettings: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Section {
            IslandPreview(steps: [.expanded(.calendar, 3.6), .idle(0.8),
                                  .transient(.calendar(title: tr("Diseño de la app", "App design"), minutes: 5, color: .orbitBlue), 3)],
                          height: 228, scale: 0.88)
            TryButton { island?.demoExpanded(.calendar) }
        }
        Section {
            Toggle(tr("Página de calendario", "Calendar page"), isOn: $settings.calendarEnabled)
            Toggle(tr("Avisar antes de cada evento", "Alert before each event"), isOn: $settings.calendarAlerts)
            Stepper(value: $settings.calendarAlertMinutes, in: 1...30) {
                Text(tr("Minutos de anticipación: \(settings.calendarAlertMinutes)", "Minutes before: \(settings.calendarAlertMinutes)"))
            }
        }
    }
}

// MARK: - Bandeja

struct TraySettings: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Section {
            IslandPreview(steps: [.expanded(.tray, 3.5), .idle(0.8), .transient(.tray(count: 2), 2)], height: 200, scale: 0.88)
            TryButton { island?.demoExpanded(.tray) }
        }
        Section {
            Toggle(isOn: $settings.trayEnabled) {
                Text(tr("Bandeja de archivos", "File tray"))
                Text(tr("Arrastra archivos al notch y llévalos a donde quieras", "Drag files onto the notch and take them anywhere"))
            }
            Toggle(tr("Abrir al arrastrar archivos cerca del notch", "Open when dragging files near the notch"), isOn: $settings.trayOpenOnDrag)
            Toggle(tr("Zona de AirDrop", "AirDrop zone"), isOn: $settings.trayAirDrop)
        }
    }
}

// MARK: - Pantalla bloqueada

struct LockScreenSettings: View {
    @ObservedObject private var settings = Settings.shared
    @StateObject private var card = LockCardState()

    var body: some View {
        Section {
            ZStack {
                PreviewWallpaper()
                VStack(spacing: 2) {
                    Text(tr("viernes, 20 de junio", "Friday, June 20"))
                        .font(.system(size: 13, weight: .semibold))
                    Text("9:41")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 14)
                LockMusicCard(state: card)
                    .services(Services.demo)
                    .scaleEffect(0.62)
                    .frame(width: 290, height: 230)
                    .offset(y: 46)
            }
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear { card.visible = true }
        }
        Section {
            Toggle(isOn: $settings.lockScreenMedia) {
                Text(tr("Reproductor en la pantalla bloqueada", "Player on the lock screen"))
                Text(tr("Controla la música sin desbloquear tu Mac", "Control music without unlocking your Mac"))
            }
            Toggle(tr("Letras en la pantalla bloqueada", "Lyrics on the lock screen"), isOn: $settings.lockScreenLyrics)
        }
    }
}

// MARK: - Acerca de

struct AboutSettings: View {
    @State private var update: String?
    @State private var checking = false
    @State private var releaseURL: URL?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        Section {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                Text("Orbit")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(tr("Versión \(version)", "Version \(version)"))
                    .foregroundStyle(.secondary)
                Text(tr("Tu notch, vivo. Música, avisos, calendario y archivos con animaciones fluidas.",
                        "Your notch, alive. Music, alerts, calendar and files with fluid animations."))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        Section {
            LabeledContent(tr("Actualizaciones", "Updates")) {
                HStack {
                    if let update { Text(update).foregroundStyle(.secondary) }
                    if let releaseURL {
                        Button(tr("Descargar", "Download")) { NSWorkspace.shared.open(releaseURL) }
                    } else {
                        Button(checking ? tr("Buscando…", "Checking…") : tr("Buscar", "Check")) { Task { await check() } }
                            .disabled(checking)
                    }
                }
            }
            Button(tr("Restablecer todos los ajustes", "Reset all settings"), role: .destructive) {
                Settings.shared.resetAll()
            }
        }
        Section {
            Text(tr("Orbit es software libre con licencia MIT. Usa mediaremote-adapter (BSD-3) para leer lo que se reproduce y LRCLIB para las letras.",
                    "Orbit is free software under the MIT license. It uses mediaremote-adapter (BSD-3) to read what’s playing and LRCLIB for lyrics."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        guard let url = URL(string: "https://api.github.com/repos/hebexort771/Orbit/releases/latest") else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            update = tr("No se pudo comprobar", "Couldn’t check")
            return
        }
        let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        if latest.compare(version, options: .numeric) == .orderedDescending {
            update = tr("Nueva versión \(latest)", "New version \(latest)")
            releaseURL = (json["html_url"] as? String).flatMap(URL.init(string:))
        } else {
            update = tr("Tienes la última versión", "You’re up to date")
        }
    }
}
