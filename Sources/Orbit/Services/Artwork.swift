import AppKit
import ImageIO

/// Portadas en alta calidad. Las apps de música le pasan al Mac una portada pequeña (a veces 300 px),
/// que se ve borrosa en grande. Aquí se busca la misma portada en el catálogo público de Apple
/// (iTunes Search API, gratis y sin cuenta) en 1200 × 1200, y solo se usa si es de verdad la misma imagen.
actor ArtworkFetcher {
    static let shared = ArtworkFetcher()
    private var cache: [String: Data] = [:]
    private var misses: Set<String> = []

    /// Devuelve la portada grande, o nil si no hay una que coincida con seguridad.
    func hiRes(title: String, artist: String, album: String, duration: Double, thumbnail: Data?) async -> Data? {
        let key = title + "\u{1F}" + artist
        if let hit = cache[key] { return hit }
        if misses.contains(key) { return nil }
        if let thumbnail, Self.pixelWidth(thumbnail) >= 1000 { return nil }

        let found = await search(title: title, artist: artist, album: album, duration: duration, thumbnail: thumbnail)
        if let found {
            cache[key] = found
            if cache.count > 40 { cache.removeAll() }
        } else {
            misses.insert(key)
        }
        return found
    }

    private struct Candidate {
        let artwork: URL
        let score: Int
    }

    private func search(title: String, artist: String, album: String, duration: Double, thumbnail: Data?) async -> Data? {
        let country = Locale.current.region?.identifier.lowercased() ?? "us"
        var parts = URLComponents(string: "https://itunes.apple.com/search")
        parts?.queryItems = [URLQueryItem(name: "term", value: "\(Self.clean(artist)) \(Self.clean(title))"),
                             URLQueryItem(name: "entity", value: "song"),
                             URLQueryItem(name: "limit", value: "12"),
                             URLQueryItem(name: "country", value: country)]
        guard let url = parts?.url, let json = await fetchJSON(url),
              let results = json["results"] as? [[String: Any]] else { return nil }

        let wantTitle = Self.normalize(title)
        let wantArtist = Self.normalize(artist)
        let wantAlbum = Self.normalize(album)
        var candidates: [Candidate] = []
        for item in results {
            guard let name = item["trackName"] as? String, let by = item["artistName"] as? String,
                  let small = item["artworkUrl100"] as? String else { continue }
            let gotTitle = Self.normalize(name)
            let gotArtist = Self.normalize(by)
            let titleOK = gotTitle == wantTitle || gotTitle.hasPrefix(wantTitle) || wantTitle.hasPrefix(gotTitle)
            let artistOK = gotArtist.contains(wantArtist) || wantArtist.contains(gotArtist)
            guard titleOK, artistOK else { continue }
            var score = 4
            if gotTitle == wantTitle { score += 2 }
            if let millis = item["trackTimeMillis"] as? Double, duration > 0 {
                let diff = abs(millis / 1000 - duration)
                if diff < 2.5 { score += 3 } else if diff > 8 { score -= 2 }
            }
            if !wantAlbum.isEmpty, let collection = item["collectionName"] as? String {
                let gotAlbum = Self.normalize(collection)
                if gotAlbum == wantAlbum { score += 3 } else if gotAlbum.contains(wantAlbum) || wantAlbum.contains(gotAlbum) { score += 1 }
            }
            guard let big = URL(string: small.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")) else { continue }
            if !candidates.contains(where: { $0.artwork == big }) { candidates.append(Candidate(artwork: big, score: score)) }
        }
        candidates.sort { $0.score > $1.score }

        // Se compara con la portada pequeña: tiene que ser la misma imagen, no otra edición del disco.
        let reference = thumbnail.flatMap(Self.signature)
        for candidate in candidates.prefix(3) {
            if reference == nil && candidate.score < 9 { continue }
            guard let data = await fetchData(candidate.artwork) else { continue }
            if let reference {
                guard let other = Self.signature(data), Self.distance(reference, other) < 30 else { continue }
            }
            return data
        }
        return nil
    }

    // MARK: Red

    private func fetchJSON(_ url: URL) async -> [String: Any]? {
        guard let data = await fetchData(url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func fetchData(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Orbit/1.0 (macOS notch app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return data
    }

    // MARK: Comparar imágenes

    static func pixelWidth(_ data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 0 }
        return (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
    }

    /// Una huella de 8 × 8 colores de la imagen.
    static func signature(_ data: Data) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let bytes = ctx.data else { return nil }
        let buffer = bytes.bindMemory(to: UInt8.self, capacity: 8 * 8 * 4)
        var out: [UInt8] = []
        for i in 0..<64 {
            out.append(buffer[i * 4]); out.append(buffer[i * 4 + 1]); out.append(buffer[i * 4 + 2])
        }
        return out
    }

    static func distance(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 255 }
        var sum = 0
        for i in a.indices { sum += abs(Int(a[i]) - Int(b[i])) }
        return Double(sum) / Double(a.count)
    }

    // MARK: Texto

    /// Sin tildes, sin mayúsculas y sin lo que va entre paréntesis ("Remastered", "feat.", etc.).
    static func normalize(_ text: String) -> String {
        var t = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let a = t.range(of: open), let b = t.range(of: close, range: a.upperBound..<t.endIndex) {
                t.removeSubrange(a.lowerBound..<b.upperBound)
            }
        }
        for marker in [" - ", " feat", " ft.", " with "] {
            if let r = t.range(of: marker) { t = String(t[..<r.lowerBound]) }
        }
        let kept = t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(kept)).split(separator: " ").joined(separator: " ")
    }

    static func clean(_ text: String) -> String {
        var t = text
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let a = t.range(of: open), let b = t.range(of: close, range: a.upperBound..<t.endIndex) {
                t.removeSubrange(a.lowerBound..<b.upperBound)
            }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
