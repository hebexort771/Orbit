import Foundation
import IOKit.ps

/// Batería: avisa al conectar/desconectar el cargador, batería baja y carga completa.
@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var charging = false
    @Published private(set) var pluggedIn = false
    @Published private(set) var hasBattery = false

    var onEvent: ((BatteryEvent) -> Void)?

    private var source: CFRunLoopSource?
    private var warned: Set<Int> = []
    private var fullAnnounced = false
    private var ready = false

    init(demo: Bool = false) {
        if demo {
            level = 80
            charging = true
            pluggedIn = true
            hasBattery = true
        }
    }

    func start() {
        read()
        ready = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.read() }
        }, context)
        if let created {
            let runLoopSource = created.takeRetainedValue()
            source = runLoopSource
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [AnyObject] else { return }
        for source in list {
            guard let unmanaged = IOPSGetPowerSourceDescription(info, source),
                  let description = unmanaged.takeUnretainedValue() as? [String: Any],
                  (description["Type"] as? String) == "InternalBattery" else { continue }
            let current = (description["Current Capacity"] as? NSNumber)?.intValue ?? 0
            let maximum = (description["Max Capacity"] as? NSNumber)?.intValue ?? 100
            let newLevel = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
            let newCharging = (description["Is Charging"] as? NSNumber)?.boolValue ?? false
            let newPlugged = (description["Power Source State"] as? String) == "AC Power"
            update(level: min(100, max(0, newLevel)), charging: newCharging, plugged: newPlugged)
            return
        }
    }

    private func update(level newLevel: Int, charging newCharging: Bool, plugged newPlugged: Bool) {
        let wasPlugged = pluggedIn
        hasBattery = true
        level = newLevel
        charging = newCharging
        pluggedIn = newPlugged
        guard ready else { return }

        if newPlugged != wasPlugged {
            if newPlugged {
                warned.removeAll()
                onEvent?(newLevel >= 100 ? .full : .charging(newLevel))
            } else {
                fullAnnounced = false
                onEvent?(.unplugged(newLevel))
            }
            return
        }
        if !newPlugged {
            for threshold in [20, 10, 5] where newLevel <= threshold && !warned.contains(threshold) {
                warned.insert(threshold)
                onEvent?(.low(newLevel))
                break
            }
        } else if newLevel >= 100 && !fullAnnounced && Settings.shared.batteryFull {
            fullAnnounced = true
            onEvent?(.full)
        }
    }
}
