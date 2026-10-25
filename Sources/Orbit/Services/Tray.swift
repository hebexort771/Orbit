import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct TrayItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
}

/// Bandeja de archivos: arrastra al notch para guardar, arrastra fuera para usar.
@MainActor
final class TrayStore: ObservableObject {
    @Published private(set) var items: [TrayItem] = []
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    private let isDemo: Bool

    init(demo: Bool = false) {
        isDemo = demo
        if demo {
            items = ["Presentación.key", "Atardecer.jpg", "Contrato.pdf", "Notas.txt"].map {
                TrayItem(url: URL(fileURLWithPath: "/tmp/OrbitDemo/" + $0))
            }
        } else {
            let saved = Settings.shared.trayPaths.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            items = saved.filter { FileManager.default.fileExists(atPath: $0.path) }.map { TrayItem(url: $0) }
            items.forEach { makeThumbnail($0.url) }
        }
    }

    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(TrayItem(url: url))
            makeThumbnail(url)
            added += 1
        }
        save()
        return added
    }

    func remove(_ item: TrayItem) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.url] = nil
        save()
    }

    func clear() {
        items.removeAll()
        thumbnails.removeAll()
        save()
    }

    func open(_ item: TrayItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: TrayItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        if service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        }
    }

    func icon(for item: TrayItem) -> NSImage {
        if let thumb = thumbnails[item.url] { return thumb }
        if FileManager.default.fileExists(atPath: item.url.path) {
            return NSWorkspace.shared.icon(forFile: item.url.path)
        }
        let type = UTType(filenameExtension: item.url.pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    private func save() {
        guard !isDemo else { return }
        Settings.shared.trayPaths = items.map(\.url.path).joined(separator: "\n")
    }

    private func makeThumbnail(_ url: URL) {
        guard !isDemo else { return }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 96, height: 96),
                                                   scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            Task { @MainActor in self?.thumbnails[url] = image }
        }
    }

    /// Lee las URLs de archivos de un "drop".
    static func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let box = URLBox()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { box.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = box.urls
            MainActor.assumeIsolated { completion(urls) }
        }
    }
}

private final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock(); storage.append(url); lock.unlock()
    }

    var urls: [URL] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
