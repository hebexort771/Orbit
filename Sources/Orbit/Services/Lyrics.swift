import Foundation

struct LyricLine: Equatable, Sendable {
    let time: Double
    let text: String
    /// Tiempos exactos de cada palabra, cuando la letra los trae (LRC mejorado). Si no, se estiman.
    var words: [LyricWord] = []
}

struct LyricWord: Equatable, Sendable {
    let text: String
    let start: Double
    let end: Double
}

/// Letras sincronizadas desde LRCLIB (gratis, sin cuenta).
actor LyricsFetcher {
    static let shared = LyricsFetcher()
    private var cache: [String: [LyricLine]] = [:]

    func lyrics(for track: TrackInfo) async -> [LyricLine] {
        if let hit = cache[track.key] { return hit }
        var lines = await exact(track)
        if lines.isEmpty { lines = await search(track) }
        cache[track.key] = lines
        if cache.count > 60 { cache.removeAll() }
        return lines
    }

    private func exact(_ track: TrackInfo) async -> [LyricLine] {
        guard var parts = URLComponents(string: "https://lrclib.net/api/get") else { return [] }
        var items = [URLQueryItem(name: "track_name", value: track.title),
                     URLQueryItem(name: "artist_name", value: track.artist)]
        if !track.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: track.album)) }
        if track.duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))) }
        parts.queryItems = items
        guard let url = parts.url, let json = await fetch(url) as? [String: Any] else { return [] }
        return Self.lines(from: json)
    }

    private func search(_ track: TrackInfo) async -> [LyricLine] {
        guard var parts = URLComponents(string: "https://lrclib.net/api/search") else { return [] }
        parts.queryItems = [URLQueryItem(name: "track_name", value: track.title),
                            URLQueryItem(name: "artist_name", value: track.artist)]
        guard let url = parts.url, let list = await fetch(url) as? [[String: Any]] else { return [] }
        for item in list.prefix(6) {
            if let duration = item["duration"] as? Double, track.duration > 0, abs(duration - track.duration) > 4 { continue }
            let found = Self.lines(from: item)
            if !found.isEmpty { return found }
        }
        return []
    }

    private func fetch(_ url: URL) async -> Any? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Orbit/1.0 (macOS notch app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func lines(from json: [String: Any]) -> [LyricLine] {
        guard let synced = json["syncedLyrics"] as? String, !synced.isEmpty else { return [] }
        return parse(synced)
    }

    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                guard let time = time(tag) else { break }
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            guard let first = times.first else { continue }
            let (text, words) = enhanced(String(rest))
            for time in times {
                let shift = time - first
                let moved = words.map { LyricWord(text: $0.text, start: $0.start + shift, end: $0.end + shift) }
                out.append(LyricLine(time: time, text: text, words: moved))
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// LRC mejorado: "<00:12.40>Hola <00:12.90>mundo<00:13.50>" trae el tiempo de cada palabra (o sílaba).
    static func enhanced(_ raw: String) -> (String, [LyricWord]) {
        guard raw.contains("<") else { return (raw.trimmingCharacters(in: .whitespaces), []) }
        var segments: [(text: String, start: Double)] = []
        var marks: [Double] = []
        var buffer = ""
        var current: Double?
        var index = raw.startIndex
        while index < raw.endIndex {
            if raw[index] == "<", let close = raw[index...].firstIndex(of: ">"),
               let stamp = time(raw[raw.index(after: index)..<close]) {
                if let start = current, !buffer.isEmpty { segments.append((buffer, start)) }
                buffer = ""
                current = stamp
                marks.append(stamp)
                index = raw.index(after: close)
                continue
            }
            buffer.append(raw[index])
            index = raw.index(after: index)
        }
        if let start = current, !buffer.isEmpty { segments.append((buffer, start)) }
        let plain = segments.map(\.text).joined().trimmingCharacters(in: .whitespaces)
        guard segments.count > 1 else { return (plain.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : plain, []) }

        // Las sílabas se juntan en palabras; cada palabra termina donde empieza la siguiente marca.
        var words: [LyricWord] = []
        var word = ""
        var wordStart = 0.0
        var wordEnd = 0.0
        for (i, segment) in segments.enumerated() {
            let end: Double
            if i + 1 < segments.count {
                end = segments[i + 1].start
            } else if let last = marks.last, last > segment.start {
                end = last
            } else {
                end = segment.start + 0.6
            }
            for ch in segment.text {
                if ch.isWhitespace {
                    if !word.isEmpty { words.append(LyricWord(text: word, start: wordStart, end: wordEnd)) }
                    word = ""
                } else {
                    if word.isEmpty { wordStart = segment.start }
                    word.append(ch)
                    wordEnd = end
                }
            }
        }
        if !word.isEmpty { words.append(LyricWord(text: word, start: wordStart, end: wordEnd)) }
        return (plain, words)
    }

    private static func time(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}

// MARK: - Palabra por palabra

struct WordTiming: Equatable {
    let text: String
    let start: Double
    let end: Double
    var duration: Double { max(0.05, end - start) }
}

/// Cuándo se canta cada palabra de una línea. Si la letra trae tiempos por palabra se usan tal cual;
/// si no, se reparten según las sílabas de cada palabra y el tiempo que hay hasta la siguiente línea,
/// como lo cantaría alguien: más rápido en líneas apuradas, más lento en las baladas.
@MainActor
enum LyricTiming {
    private static var cache: [String: [WordTiming]] = [:]

    static func words(_ lines: [LyricLine], index: Int, duration: Double) -> [WordTiming] {
        guard index >= 0, index < lines.count else { return [] }
        let line = lines[index]
        let key = "\(line.time)|\(line.text)"
        if let hit = cache[key] { return hit }
        let result: [WordTiming]
        if !line.words.isEmpty {
            result = line.words.map { WordTiming(text: $0.text, start: $0.start, end: max($0.end, $0.start + 0.08)) }
        } else {
            let next = index + 1 < lines.count ? lines[index + 1].time : min(line.time + 6, duration > 0 ? duration : line.time + 6)
            result = estimate(line.text, start: line.time, gap: max(0.4, next - line.time))
        }
        if cache.count > 800 { cache.removeAll() }
        cache[key] = result
        return result
    }

    static func estimate(_ text: String, start: Double, gap: Double) -> [WordTiming] {
        let pieces = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !pieces.isEmpty else { return [] }
        let weights = pieces.map { word -> Double in
            var weight = Double(syllables(word)) + 0.3
            if let last = word.last, ",;:.!?…".contains(last) { weight += 0.45 }
            return weight
        }
        let total = weights.reduce(0, +)
        let natural = Double(pieces.map(syllables).reduce(0, +)) * 0.27
        var sung = max(natural, gap * 0.62)
        sung = min(sung, natural * 2.2 + 0.4)
        sung = min(sung, gap * 0.94)
        sung = max(sung, min(gap * 0.94, 0.35))
        var t = start
        return zip(pieces, weights).map { word, weight in
            let length = sung * weight / total
            defer { t += length }
            return WordTiming(text: word, start: t, end: t + length)
        }
    }

    static func syllables(_ word: String) -> Int {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y", "á", "é", "í", "ó", "ú", "ü", "à", "è", "ì", "ò", "ù", "â", "ê", "î", "ô", "û", "ä", "ë", "ï", "ö"]
        var count = 0
        var previous = false
        for ch in word.lowercased() {
            let vowel = vowels.contains(ch)
            if vowel && !previous { count += 1 }
            previous = vowel
        }
        return max(1, count)
    }
}
