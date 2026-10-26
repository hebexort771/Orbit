import AppKit
import SwiftUI
import Combine

struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var bundleID: String?

    var key: String { title + "\u{1F}" + artist }
}

/// Lo que se está reproduciendo en el Mac (Música, Spotify, navegadores, etc.).
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: TrackInfo?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkSerial = 0
    @Published private(set) var accent: Color = .white
    @Published private(set) var palette: [Color] = []
    @Published private(set) var softArtwork: NSImage?
    @Published private(set) var shuffleOn = false
    @Published private(set) var repeatMode = 1
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var lyricsState: LyricsState = .none
    @Published private(set) var frontmostBundleID: String?

    private(set) var elapsedAnchor: Double = 0
    private(set) var anchorDate = Date()
    private(set) var rate: Double = 1
    private var adapter: MediaAdapter?
    private var restarts: [Date] = []
    private var lyricsTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var workspaceObserver: NSObjectProtocol?
    private var artworkAccent: Color = .white
    private var settingsSink: AnyCancellable?
    let isDemo: Bool

    enum LyricsState: Equatable { case none, loading, ready, missing }

    init(demo: Bool = false) {
        isDemo = demo
        if demo { loadDemo() }
        settingsSink = Settings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resolveAccent() }
        resolveAccent()
    }

    /// Aplica el modo de color elegido en Ajustes → Apariencia.
    func resolveAccent() {
        let settings = Settings.shared
        let color: Color
        switch settings.accentMode {
        case .artwork: color = artworkAccent
        case .system: color = Color(nsColor: .controlAccentColor)
        case .custom: color = Color(hex: settings.customAccent) ?? .pink
        }
        if color != accent { accent = color }
        if !isDemo { AccentStore.current = color }
    }

    func start() {
        guard !isDemo else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.frontmostBundleID = id }
        }
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        launchAdapter()
    }

    func stop() {
        adapter?.stop()
        adapter = nil
    }

    var hasTrack: Bool { track != nil }

    func elapsed(at date: Date = Date()) -> Double {
        guard let track else { return 0 }
        var value = elapsedAnchor
        if isPlaying { value += date.timeIntervalSince(anchorDate) * max(rate, 0) }
        if isDemo && value > 116 { value = 44 + (value - 44).truncatingRemainder(dividingBy: 72) }
        if track.duration > 0 { value = min(value, track.duration) }
        return max(0, value)
    }

    /// El tiempo que usa la letra: el de la canción más el ajuste de sincronía de Ajustes.
    func lyricsTime(at date: Date = Date()) -> Double {
        elapsed(at: date) + Settings.shared.lyricsOffset
    }

    func progress(at date: Date = Date()) -> Double {
        guard let duration = track?.duration, duration > 0 else { return 0 }
        return elapsed(at: date) / duration
    }

    // MARK: Controles

    func togglePlay() {
        if isDemo { setPlaying(!isPlaying); return }
        setPlaying(!isPlaying)
        adapter?.run(["send", "2"])
    }

    func next() {
        if isDemo { return }
        adapter?.run(["send", "4"])
    }

    func previous() {
        if isDemo { return }
        if elapsed() > 4 {
            seek(to: 0)
        } else {
            adapter?.run(["send", "5"])
        }
    }

    func toggleShuffle() {
        shuffleOn.toggle()
        if isDemo { return }
        adapter?.run(["shuffle", shuffleOn ? "3" : "1"])
    }

    func cycleRepeat() {
        // apagado → lista → canción → apagado
        let next: Int
        switch repeatMode {
        case 3: next = 2
        case 2: next = 1
        default: next = 3
        }
        repeatMode = next
        if isDemo { return }
        adapter?.run(["repeat", String(next)])
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, track?.duration ?? seconds))
        elapsedAnchor = clamped
        anchorDate = Date()
        objectWillChange.send()
        if isDemo { return }
        adapter?.run(["seek", String(Int((clamped * 1_000_000).rounded()))])
    }

    func openSourceApp() {
        guard let id = track?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    var sourceAppIcon: NSImage? {
        guard let id = track?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var sourceIsFrontmost: Bool {
        guard let id = track?.bundleID else { return false }
        return id == frontmostBundleID
    }

    private func setPlaying(_ playing: Bool) {
        if playing == isPlaying { return }
        elapsedAnchor = elapsed()
        anchorDate = Date()
        isPlaying = playing
    }

    // MARK: Adaptador

    private func launchAdapter() {
        guard let adapter = MediaAdapter.bundled() else {
            NSLog("Orbit: MediaRemoteAdapter no está incluido; la música no se mostrará.")
            return
        }
        self.adapter = adapter
        adapter.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in self?.apply(snapshot) }
        }
        adapter.onExit = { [weak self] status in
            Task { @MainActor in self?.adapterExited(status) }
        }
        adapter.start()
    }

    private func adapterExited(_ status: Int32) {
        guard let adapter else { return }
        restarts.append(Date())
        restarts = restarts.filter { Date().timeIntervalSince($0) < 60 }
        guard restarts.count < 6 else {
            NSLog("Orbit: el adaptador de música se detuvo demasiadas veces (código \(status)).")
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            adapter.start()
        }
    }

    private func apply(_ snapshot: MediaSnapshot?) {
        guard let s = snapshot, let title = s.title, !title.isEmpty else {
            if track != nil { clear() }
            return
        }
        let newTrack = TrackInfo(title: title,
                                 artist: s.artist ?? "",
                                 album: s.album ?? "",
                                 duration: (s.durationMicros ?? 0) / 1_000_000,
                                 bundleID: s.bundleID)
        let changed = newTrack.key != track?.key
        if newTrack != track { track = newTrack }

        if let micros = s.elapsedMicros {
            elapsedAnchor = micros / 1_000_000
            if let stamp = s.timestampMicros, stamp > 0 {
                anchorDate = Date(timeIntervalSince1970: stamp / 1_000_000)
            } else {
                anchorDate = Date()
            }
        } else if changed {
            elapsedAnchor = 0
            anchorDate = Date()
        }
        let r = s.rate ?? 1
        rate = r > 0 ? r : 1
        if isPlaying != s.playing { isPlaying = s.playing }
        if let mode = s.shuffleMode { shuffleOn = mode > 1 }
        if let mode = s.repeatMode { repeatMode = mode }

        switch s.artwork {
        case .data(let data):
            setArtwork(NSImage(data: data))
            upgradeArtwork(for: newTrack, thumbnail: data)
        case .removed:
            setArtwork(nil)
            upgradeArtwork(for: newTrack, thumbnail: nil)
        case .unchanged:
            if changed && s.artworkMissing {
                setArtwork(nil)
                upgradeArtwork(for: newTrack, thumbnail: nil)
            }
        }
        if changed { loadLyrics(for: newTrack) }
        objectWillChange.send()
    }

    private func clear() {
        track = nil
        isPlaying = false
        setArtwork(nil)
        lyrics = []
        lyricsState = .none
    }

    private func setArtwork(_ image: NSImage?) {
        artwork = image
        artworkSerial += 1
        if let image {
            artworkAccent = ArtworkPalette.accent(from: image).map { Color(nsColor: $0) } ?? .white
            palette = ArtworkPalette.palette(from: image).map { Color(nsColor: $0) }
            softArtwork = ArtworkPalette.soft(from: image)
        } else {
            artworkAccent = .white
            palette = []
            softArtwork = nil
        }
        resolveAccent()
    }

    /// Cambia la portada pequeña por la original en alta calidad, sin animación (se ve igual, pero nítida).
    private func upgradeArtwork(for track: TrackInfo, thumbnail: Data?) {
        artworkTask?.cancel()
        guard Settings.shared.hdArtwork, !isDemo else { return }
        let serial = artworkSerial
        artworkTask = Task { @MainActor [weak self] in
            guard let data = await ArtworkFetcher.shared.hiRes(title: track.title, artist: track.artist, album: track.album,
                                                               duration: track.duration, thumbnail: thumbnail),
                  let self, !Task.isCancelled, self.track?.key == track.key,
                  let image = NSImage(data: data) else { return }
            if self.artwork == nil || self.artworkSerial != serial {
                // No había portada: la de alta calidad pasa a ser la portada (con sus colores).
                self.setArtwork(image)
            } else {
                self.artwork = image
            }
        }
    }

    // MARK: Letras

    /// La línea que se está cantando, exactamente en su momento (como Apple Music).
    func currentLyricIndex(at time: Double) -> Int? {
        guard !lyrics.isEmpty else { return nil }
        var low = 0, high = lyrics.count - 1, found: Int?
        let t = time + 0.02
        while low <= high {
            let mid = (low + high) / 2
            if lyrics[mid].time <= t { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }

    private func loadLyrics(for track: TrackInfo) {
        lyricsTask?.cancel()
        lyrics = []
        guard Settings.shared.lyricsEnabled, !isDemo else { lyricsState = .none; return }
        lyricsState = .loading
        lyricsTask = Task { @MainActor [weak self] in
            let lines = await LyricsFetcher.shared.lyrics(for: track)
            guard let self, !Task.isCancelled, self.track?.key == track.key else { return }
            self.lyrics = lines
            self.lyricsState = lines.isEmpty ? .missing : .ready
        }
    }

    // MARK: Demostración

    private func loadDemo() {
        track = TrackInfo(title: "Luz de Neón", artist: "Aurora Vale", album: "Órbitas", duration: 214, bundleID: "com.apple.Music")
        isPlaying = true
        elapsedAnchor = 69
        anchorDate = Date()
        let image = DemoArt.make()
        artwork = image
        artworkSerial = 1
        artworkAccent = Color(nsColor: ArtworkPalette.accent(from: image) ?? .systemPink)
        accent = artworkAccent
        palette = ArtworkPalette.palette(from: image).map { Color(nsColor: $0) }
        softArtwork = ArtworkPalette.soft(from: image)
        lyrics = [
            LyricLine(time: 46, text: "Las calles brillan cuando pasas"),
            LyricLine(time: 53, text: "Y el cielo cambia de color"),
            LyricLine(time: 60, text: "Brillas aunque apague la ciudad"),
            LyricLine(time: 66, text: "Giro a tu alrededor sin pensar"),
            LyricLine(time: 72, text: "Somos luz de neón en la oscuridad"),
            LyricLine(time: 79, text: "Y no quiero volver a aterrizar"),
            LyricLine(time: 86, text: ""),
            LyricLine(time: 94, text: "Una órbita más, una vez más"),
            LyricLine(time: 101, text: "Tu voz es la señal que sigo al regresar"),
            LyricLine(time: 108, text: "Y en la noche te vuelvo a encontrar")
        ]
        lyricsState = .ready
    }

    func demoSet(playing: Bool) { setPlaying(playing) }

    /// Solo para las capturas de prueba: salta a un segundo concreto de la canción de ejemplo.
    func demoSeek(to value: Double) {
        guard isDemo else { return }
        elapsedAnchor = value
        anchorDate = Date()
    }
}

// MARK: - Portada de ejemplo

enum DemoArt {
    /// Una portada inventada: un sol retro sobre un horizonte de neón.
    static func make(size: CGFloat = 300) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSGradient(colors: [
            NSColor(srgbRed: 1.0, green: 0.36, blue: 0.56, alpha: 1),
            NSColor(srgbRed: 0.55, green: 0.16, blue: 0.62, alpha: 1),
            NSColor(srgbRed: 0.09, green: 0.05, blue: 0.27, alpha: 1)
        ])?.draw(in: rect, angle: 90)

        let horizon = size * 0.3
        let sun = NSBezierPath(ovalIn: NSRect(x: size * 0.22, y: horizon - size * 0.12, width: size * 0.56, height: size * 0.56))
        NSGradient(colors: [
            NSColor(srgbRed: 1.0, green: 0.38, blue: 0.5, alpha: 1),
            NSColor(srgbRed: 1.0, green: 0.86, blue: 0.36, alpha: 1)
        ])?.draw(in: sun, angle: 90)

        let band = NSColor(srgbRed: 0.93, green: 0.33, blue: 0.56, alpha: 1)
        band.setFill()
        for index in 0..<5 {
            let y = horizon + size * (0.02 + 0.045 * CGFloat(index))
            let height = size * (0.026 - 0.004 * CGFloat(index))
            NSBezierPath(rect: NSRect(x: 0, y: y, width: size, height: height)).fill()
        }

        NSColor(srgbRed: 0.1, green: 0.03, blue: 0.2, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: horizon)).fill()
        let grid = NSColor(srgbRed: 1.0, green: 0.4, blue: 0.75, alpha: 0.85)
        grid.setStroke()
        let vanishing = NSPoint(x: size / 2, y: horizon)
        for index in -6...6 {
            let line = NSBezierPath()
            line.move(to: vanishing)
            line.line(to: NSPoint(x: size / 2 + CGFloat(index) * size * 0.16, y: 0))
            line.lineWidth = size * 0.006
            line.stroke()
        }
        for index in 1...5 {
            let t = CGFloat(index) / 5
            let y = horizon * (1 - t * t)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: y))
            line.line(to: NSPoint(x: size, y: y))
            line.lineWidth = size * 0.006
            line.stroke()
        }
        image.unlockFocus()
        return image
    }
}

// MARK: - Proceso del adaptador

enum ArtworkUpdate: Sendable {
    case unchanged
    case removed
    case data(Data)
}

struct MediaSnapshot: Sendable {
    var bundleID: String?
    var playing: Bool
    var title: String?
    var artist: String?
    var album: String?
    var durationMicros: Double?
    var elapsedMicros: Double?
    var timestampMicros: Double?
    var rate: Double?
    var shuffleMode: Int?
    var repeatMode: Int?
    var artwork: ArtworkUpdate
    var artworkMissing: Bool
}

/// Ejecuta mediaremote-adapter (perl + framework) y traduce su salida JSON.
final class MediaAdapter: @unchecked Sendable {
    let script: URL
    let framework: URL
    var onSnapshot: (@Sendable (MediaSnapshot?) -> Void)?
    var onExit: (@Sendable (Int32) -> Void)?

    private let queue = DispatchQueue(label: "orbit.media-adapter")
    private var process: Process?
    private var buffer = Data()
    private var merged: [String: Any] = [:]
    private var lastArtwork: String?
    private var stopping = false

    init(script: URL, framework: URL) {
        self.script = script
        self.framework = framework
    }

    static func bundled() -> MediaAdapter? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let folder = resources.appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
        let script = folder.appendingPathComponent("mediaremote-adapter.pl")
        let framework = folder.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: script.path), fm.fileExists(atPath: framework.path) else { return nil }
        // Si la app se descargó de internet, quitamos la cuarentena del adaptador para que perl pueda cargarlo.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", folder.path]
        xattr.standardOutput = FileHandle.nullDevice
        xattr.standardError = FileHandle.nullDevice
        try? xattr.run()
        xattr.waitUntilExit()
        return MediaAdapter(script: script, framework: framework)
    }

    func start() {
        queue.async { self.launch() }
    }

    func stop() {
        queue.async {
            self.stopping = true
            self.process?.terminate()
            self.process = nil
        }
    }

    /// Comando de una sola vez (play, siguiente, seek…).
    func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, framework.path] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { NSLog("Orbit: no se pudo enviar el comando \(args): \(error)") }
    }

    private func launch() {
        stopping = false
        buffer = Data()
        merged = [:]
        lastArtwork = nil
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, framework.path, "stream", "--micros", "--debounce=40"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.queue.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.queue.async {
                if self.stopping { return }
                self.onExit?(proc.terminationStatus)
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            NSLog("Orbit: no se pudo iniciar el adaptador de música: \(error)")
            onExit?(-1)
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty { handle(line) }
        }
    }

    private func handle(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return }
        let diff = (object["diff"] as? Bool) ?? false
        if diff {
            for (key, value) in payload {
                if value is NSNull { merged.removeValue(forKey: key) } else { merged[key] = value }
            }
        } else {
            merged = payload
        }

        var artwork = ArtworkUpdate.unchanged
        let currentArt = merged["artworkData"] as? String
        if currentArt != lastArtwork {
            if let currentArt, let data = Data(base64Encoded: currentArt, options: .ignoreUnknownCharacters) {
                artwork = .data(data)
            } else {
                artwork = .removed
            }
            lastArtwork = currentArt
        }

        func number(_ key: String) -> Double? { (merged[key] as? NSNumber)?.doubleValue }
        func int(_ key: String) -> Int? { (merged[key] as? NSNumber)?.intValue }

        guard merged["title"] != nil else {
            onSnapshot?(nil)
            return
        }
        let snapshot = MediaSnapshot(
            bundleID: (merged["parentApplicationBundleIdentifier"] as? String) ?? (merged["bundleIdentifier"] as? String),
            playing: (merged["playing"] as? Bool) ?? false,
            title: merged["title"] as? String,
            artist: merged["artist"] as? String,
            album: merged["album"] as? String,
            durationMicros: number("durationMicros"),
            elapsedMicros: number("elapsedTimeMicros"),
            timestampMicros: number("timestampEpochMicros"),
            rate: number("playbackRate"),
            shuffleMode: int("shuffleMode"),
            repeatMode: int("repeatMode"),
            artwork: artwork,
            artworkMissing: currentArt == nil
        )
        onSnapshot?(snapshot)
    }
}
