import Foundation
import IOBluetooth

struct BluetoothEvent {
    let name: String
    let symbol: String
    let battery: Int?
    let connected: Bool
}

/// Avisa cuando se conectan audífonos, AirPods, teclados, mandos…
@MainActor
final class BluetoothService: NSObject {
    var onEvent: ((BluetoothEvent) -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [IOBluetoothUserNotification] = []
    private var startedAt = Date()

    func start() {
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let note = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) {
            disconnectNotifications.append(note)
        }
        // Al iniciar, macOS avisa de los dispositivos que ya estaban conectados: los ignoramos.
        guard Date().timeIntervalSince(startedAt) > 5 else { return }
        let name = device.name ?? "Bluetooth"
        let symbol = Self.symbol(for: device)
        Task { @MainActor [weak self] in
            // La batería de los AirPods tarda un momento en estar disponible.
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            self?.onEvent?(BluetoothEvent(name: name, symbol: symbol, battery: Self.battery(of: device), connected: true))
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        disconnectNotifications.removeAll { $0 === notification }
        onEvent?(BluetoothEvent(name: device.name ?? "Bluetooth", symbol: Self.symbol(for: device), battery: nil, connected: false))
    }

    static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("keyboard") || name.contains("teclado") { return "keyboard.fill" }
        if name.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if name.contains("mouse") || name.contains("ratón") || name.contains("raton") { return "computermouse.fill" }
        if name.contains("controller") || name.contains("dualsense") || name.contains("xbox") || name.contains("mando") { return "gamecontroller.fill" }
        if name.contains("watch") { return "applewatch" }
        if name.contains("iphone") { return "iphone" }
        if name.contains("beats") || name.contains("buds") || name.contains("headphone") || name.contains("auricular") { return "headphones" }
        switch Int(device.deviceClassMajor) {
        case 0x04: return "headphones"
        case 0x02: return "iphone"
        case 0x05: return "keyboard.fill"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    static func battery(of device: IOBluetoothDevice) -> Int? {
        var parts: [Int] = []
        for key in ["batteryPercentSingle", "batteryPercentCombined", "batteryPercentLeft", "batteryPercentRight"] {
            guard device.responds(to: NSSelectorFromString(key)),
                  let number = device.value(forKey: key) as? NSNumber,
                  number.intValue > 0, number.intValue <= 100 else { continue }
            if key == "batteryPercentSingle" || key == "batteryPercentCombined" { return number.intValue }
            parts.append(number.intValue)
        }
        return parts.min()
    }
}
