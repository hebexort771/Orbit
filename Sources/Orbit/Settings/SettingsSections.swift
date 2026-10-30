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

        MacSection()

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

/// El Mac detectado y sus medidas, con ajuste fino del notch.
struct MacSection: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let screen = IslandController.preferredScreen()
        let metrics = NotchMetrics.measure(screen, style: settings.virtualStyle)
        let pixels = DeviceInfo.pixels(of: screen)
        let size = screen.frame.size
        Section(tr("Tu Mac", "Your Mac")) {
            LabeledContent(tr("Modelo", "Model")) {
                Text(DeviceInfo.name).textSelection(.enabled)
            }
            LabeledContent(tr("Pantalla", "Display")) {
                Text(displayText(screen: screen, size: size, pixels: pixels))
            }
            LabeledContent(tr("Notch", "Notch")) {
                Text(metrics.hasNotch
                     ? "\(Int(metrics.notchWidth)) × \(Int(metrics.notchHeight)) pt"
                     : tr("Esta pantalla no tiene notch; Orbit dibuja uno virtual", "No notch on this display; Orbit draws a virtual one"))
            }
            if metrics.hasNotch {
                SliderRow(title: tr("Ajuste fino del ancho", "Width fine-tune"),
                          subtitle: tr("Si la isla sobresale del notch o no lo cubre del todo", "If the island sticks out of the notch or doesn’t fully cover it"),
                          value: $settings.notchWidthAdjust, range: -20...20, step: 1,
                          format: { String(format: "%+.0f pt", $0) })
                    .onChange(of: settings.notchWidthAdjust) { AppDelegate.shared?.island?.calibrate() }
                SliderRow(title: tr("Ajuste fino del alto", "Height fine-tune"),
                          value: $settings.notchHeightAdjust, range: -6...8, step: 1,
                          format: { String(format: "%+.0f pt", $0) })
                    .onChange(of: settings.notchHeightAdjust) { AppDelegate.shared?.island?.calibrate() }
                HStack {
                    Text(tr("Mientras ajustas, el borde de la isla se marca en azul sobre el notch.",
                            "While you adjust, the island outline is drawn in blue over the notch."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("Ver contorno", "Show outline")) { AppDelegate.shared?.island?.calibrate() }
                    Button(tr("Restablecer", "Reset")) {
                        settings.notchWidthAdjust = 0
                        settings.notchHeightAdjust = 0
                        AppDelegate.shared?.island?.calibrate()
                    }
                    .disabled(settings.notchWidthAdjust == 0 && settings.notchHeightAdjust == 0)
                }
            }
        }
    }

    private func displayText(screen: NSScreen, size: CGSize, pixels: CGSize) -> String {
        var parts: [String] = []
        if let inches = DeviceInfo.inches(of: screen) {
            parts.append(String(format: tr("%.1f pulgadas", "%.1f-inch"), inches))
        }
        parts.append("\(Int(size.width)) × \(Int(size.height)) pt")
        parts.append("\(Int(pixels.width)) × \(Int(pixels.height)) px")
        return parts.joined(separator: ", ")
    }
}

struct AnimationStylePreview: View {
    let style: AnimationStyle
    @State private var open = false

    var body: some View {
        let response: Double
        let damping: Double
        switch style {
        case .native: response = 0.36; damping = 0.8
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
            Toggle(isOn: $settings.trackPeek) {
                Text(tr("Anunciar cada canción nueva", "Announce each new song"))
                Text(tr("La isla muestra un momento la portada, el título y el artista", "The island briefly shows the artwork, title and artist"))
            }
            Toggle(isOn: $settings.lyricsEnabled) {
                Text(tr("Letras sincronizadas", "Synced lyrics"))
                Text(tr("Desde LRCLIB. Como en Apple Music: cada línea se enciende justo cuando se canta, y palabra por palabra si la letra trae esos tiempos",
                        "From LRCLIB. Like Apple Music: each line lights up right when it's sung, and word by word when the lyrics include word timings"))
            }
            if settings.lyricsEnabled {
                SliderRow(title: tr("Sincronía de la letra", "Lyrics timing"), value: $settings.lyricsOffset,
                          range: -1.5...1.5, step: 0.1,
                          format: { abs($0) < 0.05 ? tr("Exacta", "Exact") : String(format: "%+.1f s", $0) })
                Text(tr("Si la letra va atrasada respecto al cantante, súbelo (+); si va adelantada, bájalo (−).",
                        "If lyrics lag behind the singer, raise it (+); if they run ahead, lower it (−)."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle(isOn: $settings.lyricsEstimateWords) {
                    Text(tr("Calcular palabra por palabra", "Estimate word by word"))
                    Text(tr("Para letras que solo traen el tiempo de cada línea. Es aproximado: puede adelantarse o atrasarse al cantante",
                            "For lyrics that only have line timings. It's approximate and may drift from the singer"))
                }
            }
            Toggle(isOn: $settings.hdArtwork) {
                Text(tr("Portadas en alta calidad", "High-quality artwork"))
                Text(tr("Si la app de música entrega una portada pequeña, Orbit busca la original en 1200 px en el catálogo de Apple",
                        "If the music app provides a small cover, Orbit finds the original at 1200 px in Apple's catalog"))
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
    @ObservedObject private var demoMedia = Services.demo.media
    @StateObject private var state = LockScreenState()

    var body: some View {
        Section {
            LockPreviewBox(state: state)
            HStack(alignment: .firstTextBaseline) {
                Text(state.style.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    AppDelegate.shared?.previewLockScreen()
                } label: {
                    Label(tr("Ver en pantalla completa", "View full screen"), systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
        }

        Section {
            Toggle(isOn: $settings.lockScreenMedia) {
                Text(tr("Reproductor en la pantalla bloqueada", "Player on the lock screen"))
                Text(tr("Controla la música y lee la letra sin desbloquear tu Mac", "Control music and read lyrics without unlocking your Mac"))
            }
        }

        Section(tr("Pantalla completa y reloj", "Full screen and clock")) {
            Picker(tr("Cómo se muestra", "How it's shown"), selection: $settings.lockLayer) {
                ForEach(LockLayer.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(settings.lockLayer.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section(tr("Estilo", "Style")) {
            StyleCards(LockStyle.allCases,
                       selection: Binding(get: { settings.lockStyle },
                                          set: { value in
                                              settings.lockStyle = value
                                              withAnimation(.spring(response: 0.66, dampingFraction: 0.84)) { state.style = value }
                                          }),
                       title: { $0.title }) { style in
                LockStyleThumb(style: style, accent: demoMedia.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(4)
            }
            Label(tr("En la pantalla bloqueada, toca la portada para pasar al siguiente estilo.",
                     "On the lock screen, click the artwork to switch to the next style."), systemImage: "hand.tap")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Section(tr("Fondo", "Background")) {
            Picker(tr("Fondo", "Background"), selection: $settings.lockBackground) {
                ForEach(LockBackground.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $settings.lockMotion) {
                Text(tr("Colores en movimiento", "Moving colors"))
                Text(tr("Los colores de la portada se mueven despacio, como en Apple Music", "The artwork colors drift slowly, like Apple Music"))
            }
            .disabled(settings.lockBackground != .aurora)
        }


        Section(tr("Letra", "Lyrics")) {
            Toggle(tr("Mostrar la letra", "Show lyrics"), isOn: $settings.lockScreenLyrics)
            SliderRow(title: tr("Tamaño", "Size"), value: $settings.lockLyricsSize, range: 24...48, step: 1,
                      format: { String(format: "%.0f pt", $0) })
            Picker(tr("Alineación", "Alignment"), selection: $settings.lockLyricsAlign) {
                ForEach(TextAlign.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $settings.lockLyricsBlur) {
                Text(tr("Desenfocar las otras líneas", "Blur the other lines"))
                Text(tr("Solo la línea que suena queda nítida", "Only the line being sung stays sharp"))
            }
        }

        Section(tr("Portada", "Artwork")) {
            Toggle(isOn: $settings.lockTilt) {
                Text(tr("Inclinar con el cursor", "Tilt with the pointer"))
                Text(tr("La portada se inclina un poco al pasar el cursor por encima y vuelve a quedar recta sola", "The artwork tilts slightly while the pointer is over it, then straightens itself"))
            }
            Toggle(tr("Girar la portada al cambiar de canción", "Flip the artwork on track change"), isOn: $settings.artworkFlip)
        }

        LockReportSection()
    }
}

/// La pantalla bloqueada real, en miniatura.
struct LockPreviewBox: View {
    @ObservedObject var state: LockScreenState
    /// Las medidas de tu propia pantalla, para que la miniatura sea idéntica a lo que verás.
    private let screen = IslandController.preferredScreen()
    private var base: CGSize {
        let size = screen.frame.size
        return size.width > 400 && size.height > 300 ? size : CGSize(width: 1470, height: 956)
    }

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / base.width
            ZStack(alignment: .topLeading) {
                PreviewWallpaper()
                LockScreenView(state: state, size: base, safeTop: LockScreenController.safeTop(of: screen))
                    .services(Services.demo)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: base.width * scale, height: base.height * scale, alignment: .topLeading)
            }
        }
        .aspectRatio(base.width / base.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .padding(.vertical, 4)
        .task {
            state.syncStyle()
            state.phase = .hidden
            try? await Task.sleep(nanoseconds: 250_000_000)
            state.phase = .shown
        }
    }
}

// MARK: - Apariencia

struct AppearanceSettings: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var demoMedia = Services.demo.media

    var body: some View {
        Section {
            IslandPreview(steps: [.music(1.6), .transient(.battery(.charging(80)), 2.4), .expanded(.music, 3.2),
                                  .transient(.track(title: "Luz de Neón", artist: "Aurora Vale"), 2.6)],
                          height: 214, scale: 0.88)
            TryButton { island?.demo(.battery(.charging(80))) }
        }

        Section(tr("Color de acento", "Accent color")) {
            AccentPicker()
            Text(accentCaption)
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Section(tr("Luz", "Light")) {
            Toggle(isOn: $settings.comet) {
                Text(tr("Estela orbital", "Orbit trail"))
                Text(tr("Un destello recorre el borde de la isla cuando llega algo nuevo", "A streak of light runs along the island when something new arrives"))
            }
            Picker(tr("Color de la estela", "Trail color"), selection: $settings.trailColor) {
                ForEach(TrailColor.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.comet)
            Toggle(isOn: $settings.ambientGlow) {
                Text(tr("Brillo ambiental", "Ambient glow"))
                Text(tr("La isla brilla con el color de la portada o del aviso", "The island glows with the artwork or alert color"))
            }
            SliderRow(title: tr("Intensidad del brillo", "Glow intensity"), value: $settings.glowIntensity, range: 0.2...1, step: 0.05,
                      format: { String(format: "%.0f%%", $0 * 100) })
                .disabled(!settings.ambientGlow)
        }

        Section(tr("Material", "Material")) {
            Picker(tr("Isla abierta y pantalla bloqueada", "Open island and lock screen"), selection: $settings.islandMaterial) {
                ForEach(IslandMaterial.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(settings.islandMaterial.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Section(tr("Forma de la isla", "Island shape")) {
            Picker(tr("Tamaño al abrirse", "Open size"), selection: $settings.islandSize) {
                ForEach(IslandSize.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            SliderRow(title: tr("Redondez", "Roundness"), value: $settings.roundness, range: 0.5...1.4, step: 0.05,
                      format: { String(format: "%.0f%%", $0 * 100) })
            Toggle(isOn: $settings.islandOutline) {
                Text(tr("Borde sutil", "Subtle edge"))
                Text(tr("Una línea fina para que la isla abierta se distinga en fondos oscuros", "A thin line so the open island stands out on dark wallpapers"))
            }
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
            Toggle(isOn: $settings.liquidNotch) {
                Text(tr("Notch líquido", "Liquid notch"))
                Text(tr("Al acercar el cursor, el notch se estira como agua hacia él y suelta una gota; al abrirse o cerrarse, ondula",
                        "As the pointer comes close, the notch stretches toward it like water and lets a drop hang; it ripples as it opens and closes"))
            }
        }
    }

    private var accentCaption: String {
        switch settings.accentMode {
        case .artwork: return tr("Cada canción tiñe la isla con el color de su portada.", "Each song tints the island with its artwork color.")
        case .system: return tr("Usa el color de acento de Ajustes del Sistema.", "Uses the accent color from System Settings.")
        case .custom: return tr("Tu color se usa en la barra de progreso, la onda, los controles y el brillo.", "Your color is used for the progress bar, waveform, controls and glow.")
        }
    }
}

/// Fila de colores como la de Ajustes del Sistema → Apariencia.
struct AccentPicker: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 10) {
            swatch(selected: settings.accentMode == .artwork,
                   fill: AnyShapeStyle(AngularGradient(colors: [.pink, .orange, .yellow, .green, .cyan, .blue, .purple, .pink], center: .center)),
                   help: tr("De la portada", "From artwork")) { settings.accentMode = .artwork }
            swatch(selected: settings.accentMode == .system,
                   fill: AnyShapeStyle(Color(nsColor: .controlAccentColor)),
                   help: tr("Del sistema", "System")) { settings.accentMode = .system }
            Divider().frame(height: 22)
            ForEach(Color.accentPresets, id: \.0) { preset in
                swatch(selected: settings.accentMode == .custom && settings.customAccent.uppercased() == preset.0,
                       fill: AnyShapeStyle(Color(hex: preset.0) ?? .white),
                       help: preset.1) {
                    settings.customAccent = preset.0
                    settings.accentMode = .custom
                }
            }
            ColorPicker("", selection: Binding(get: { Color(hex: settings.customAccent) ?? .pink },
                                               set: { color in
                                                   settings.customAccent = color.hexString
                                                   settings.accentMode = .custom
                                               }),
                        supportsOpacity: false)
                .labelsHidden()
                .help(tr("Otro color", "Another color"))
        }
        .padding(.vertical, 4)
    }

    private func swatch(selected: Bool, fill: AnyShapeStyle, help: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { action() }
        }) {
            Circle()
                .fill(fill)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: selected ? 2.5 : 0).padding(2))
                .shadow(color: .black.opacity(selected ? 0.25 : 0), radius: 3, y: 1)
                .scaleEffect(selected ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .help(help)
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

/// Copia el informe de la última vez que se bloqueó la Mac, para ajustar Orbit a tu pantalla.
struct LockReportSection: View {
    @State private var copied = false

    var body: some View {
        Section(tr("Si algo no se ve bien", "If something looks wrong")) {
            HStack {
                Text(tr("Informe de la última vez que bloqueaste la Mac", "Report from the last time you locked your Mac"))
                Spacer()
                Button(copied ? tr("Copiado", "Copied") : tr("Copiar informe", "Copy report")) {
                    guard let text = LockReport.text else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation { copied = true }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation { copied = false }
                    }
                }
                .disabled(LockReport.text == nil)
            }
        }
    }
}
