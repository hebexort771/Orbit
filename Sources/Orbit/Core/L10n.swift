import Foundation

/// Español o inglés según el ajuste del usuario (o el idioma del sistema).
enum Lang {
    static var isSpanish: Bool {
        switch Settings.shared.language {
        case .es: return true
        case .en: return false
        case .system:
            let first = Locale.preferredLanguages.first ?? "es"
            return first.hasPrefix("es")
        }
    }

    static var locale: Locale {
        switch Settings.shared.language {
        case .es: return Locale(identifier: "es_ES")
        case .en: return Locale(identifier: "en_US")
        case .system: return Locale.autoupdatingCurrent
        }
    }
}

func tr(_ es: String, _ en: String) -> String {
    Lang.isSpanish ? es : en
}

enum TimeText {
    /// 3:07 o 1:02:44
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
