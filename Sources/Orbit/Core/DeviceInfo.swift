import AppKit
import IOKit

/// Qué Mac es: modelo, pantalla y notch. Orbit se acopla a estas medidas.
enum DeviceInfo {
    struct Model {
        let name: String
        let inches: Double
        let notch: Bool
    }

    /// Identificador de hardware, por ejemplo "Mac14,2".
    static let identifier: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }()

    /// Nombre comercial que guarda el propio Mac (Apple Silicon), por ejemplo "MacBook Air (13-inch, M2, 2022)".
    static let productName: String? = {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue(),
              let data = value as? Data else { return nil }
        let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }()

    /// MacBook con notch conocidos.
    static let known: [String: Model] = {
        var table: [String: Model] = [:]
        func add(_ ids: [String], _ name: String, _ inches: Double) {
            for id in ids { table[id] = Model(name: name, inches: inches, notch: true) }
        }
        add(["MacBookPro18,3", "MacBookPro18,4"], "MacBook Pro 14\" (2021)", 14.2)
        add(["MacBookPro18,1", "MacBookPro18,2"], "MacBook Pro 16\" (2021)", 16.2)
        add(["Mac14,2"], "MacBook Air 13\" (M2, 2022)", 13.6)
        add(["Mac14,15"], "MacBook Air 15\" (M2, 2023)", 15.3)
        add(["Mac14,5", "Mac14,9"], "MacBook Pro 14\" (2023)", 14.2)
        add(["Mac14,6", "Mac14,10"], "MacBook Pro 16\" (2023)", 16.2)
        add(["Mac15,3", "Mac15,6", "Mac15,8", "Mac15,10"], "MacBook Pro 14\" (M3, 2023)", 14.2)
        add(["Mac15,7", "Mac15,9", "Mac15,11"], "MacBook Pro 16\" (M3, 2023)", 16.2)
        add(["Mac15,12"], "MacBook Air 13\" (M3, 2024)", 13.6)
        add(["Mac15,13"], "MacBook Air 15\" (M3, 2024)", 15.3)
        add(["Mac16,1", "Mac16,6", "Mac16,8"], "MacBook Pro 14\" (M4, 2024)", 14.2)
        add(["Mac16,5", "Mac16,7"], "MacBook Pro 16\" (M4, 2024)", 16.2)
        add(["Mac16,12"], "MacBook Air 13\" (M4, 2025)", 13.6)
        add(["Mac16,13"], "MacBook Air 15\" (M4, 2025)", 15.3)
        return table
    }()

    static var model: Model? { known[identifier] }

    static var name: String {
        if let productName { return productName }
        if let model { return model.name }
        return identifier
    }

    /// Tamaño físico de la pantalla integrada en pulgadas (diagonal).
    static func inches(of screen: NSScreen) -> Double? {
        guard let id = screen.displayID else { return nil }
        let mm = CGDisplayScreenSize(id)
        guard mm.width > 0, mm.height > 0 else { return model?.inches }
        let w = Double(mm.width), h = Double(mm.height)
        let diagonal: Double = (w * w + h * h).squareRoot() / 25.4
        return (diagonal * 10).rounded() / 10
    }

    /// Resolución real en píxeles de una pantalla.
    static func pixels(of screen: NSScreen) -> CGSize {
        CGSize(width: screen.frame.width * screen.backingScaleFactor,
               height: screen.frame.height * screen.backingScaleFactor)
    }
}
