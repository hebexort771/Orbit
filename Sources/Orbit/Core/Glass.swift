import AppKit
import SwiftUI

/// Desenfoque real de lo que hay detrás de la ventana (el escritorio o la pantalla bloqueada).
struct BehindWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Un fondo de vidrio con cualquier forma.
/// - `liquid`: Liquid Glass de macOS 26 (Tahoe). En versiones anteriores, o con `liquid` apagado,
///   un vidrio esmerilado oscuro como los widgets de macOS.
struct GlassSurface<S: Shape>: View {
    let shape: S
    var liquid = true
    var tint: Color = .black.opacity(0.3)
    @Environment(\.orbitStatic) private var isStatic

    var body: some View {
        if isStatic {
            // Las capturas de prueba no pueden dibujar vidrio real.
            shape.fill(Color(white: 0.08).opacity(0.78))
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
        } else if liquid {
            liquidGlass
        } else {
            frosted
        }
    }

    @ViewBuilder
    private var liquidGlass: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(tint), in: shape)
        } else {
            frosted
        }
        #else
        frosted
        #endif
    }

    private var frosted: some View {
        BehindWindowBlur()
            .clipShape(shape)
            .overlay(shape.fill(tint))
            .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
