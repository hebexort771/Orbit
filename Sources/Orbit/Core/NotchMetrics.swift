import AppKit

/// Medidas del notch (real o virtual) de una pantalla.
struct NotchMetrics: Equatable {
    var screenFrame: CGRect
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool
    var floating: Bool

    /// Separación desde el borde superior (solo la isla flotante).
    var topInset: CGFloat { floating ? 6 : 0 }

    static func measure(_ screen: NSScreen, style: VirtualStyle) -> NotchMetrics {
        let frame = screen.frame
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchMetrics(screenFrame: frame,
                                notchWidth: max(150, width.rounded()),
                                notchHeight: top.rounded(),
                                hasNotch: true,
                                floating: false)
        }
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        let barHeight = menuBar > 12 ? min(menuBar, 32) : 24
        switch style {
        case .notch:
            return NotchMetrics(screenFrame: frame, notchWidth: 190, notchHeight: barHeight.rounded(),
                                hasNotch: false, floating: false)
        case .floating:
            return NotchMetrics(screenFrame: frame, notchWidth: 168, notchHeight: 32,
                                hasNotch: false, floating: true)
        }
    }

    /// Un MacBook con notch, para vistas previas y capturas.
    static let preview = NotchMetrics(screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                      notchWidth: 186, notchHeight: 32, hasNotch: true, floating: false)

    static func previewFloating() -> NotchMetrics {
        NotchMetrics(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                     notchWidth: 168, notchHeight: 32, hasNotch: false, floating: true)
    }

    /// Tamaño de la ventana transparente que contiene la isla.
    var canvasSize: CGSize {
        let width = max(notchWidth + 2 * 166, 524) + 160
        let height = notchHeight + topInset + 190 + 70
        return CGSize(width: width.rounded(), height: height.rounded())
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var isBuiltin: Bool {
        guard let id = displayID else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    var hasNotch: Bool { safeAreaInsets.top > 0 }
}
