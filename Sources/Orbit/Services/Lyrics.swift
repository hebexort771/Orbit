import Foundation

struct LyricLine: Equatable, Sendable {
    let time: Double
    let text: String
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
            guard !times.isEmpty else { continue }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times { out.append(LyricLine(time: time, text: text)) }
        }
        return out.sorted { $0.time < $1.time }
    }

    private static func time(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}
