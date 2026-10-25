import SwiftUI
import AppKit

/// Curvas de animación de la isla. "Órbita" es la firma de Orbit:
/// el ancho llega antes que el alto, así la forma se estira como un líquido.
struct Motion {
    var width: Animation
    var height: Animation
    var content: Animation
    var contentIn: Animation
    var contentOut: Animation
    var hover: Animation
    var stagger: Double
    var liquid: Bool

    static func current(_ settings: Settings = .shared) -> Motion {
        let speed = max(0.5, min(1.8, settings.animationSpeed))
        func r(_ value: Double) -> Double { value / speed }
        switch settings.animationStyle {
        case .orbit:
            return Motion(width: .spring(response: r(0.42), dampingFraction: 0.72),
                          height: .spring(response: r(0.52), dampingFraction: 0.78),
                          content: .spring(response: r(0.4), dampingFraction: 0.86),
                          contentIn: .spring(response: r(0.42), dampingFraction: 0.82).delay(r(0.07)),
                          contentOut: .easeOut(duration: r(0.14)),
                          hover: .spring(response: 0.3, dampingFraction: 0.55),
                          stagger: r(0.045),
                          liquid: true)
        case .smooth:
            return Motion(width: .spring(response: r(0.5), dampingFraction: 1.0),
                          height: .spring(response: r(0.5), dampingFraction: 1.0),
                          content: .easeInOut(duration: r(0.3)),
                          contentIn: .easeOut(duration: r(0.32)).delay(r(0.08)),
                          contentOut: .easeIn(duration: r(0.14)),
                          hover: .spring(response: 0.35, dampingFraction: 0.9),
                          stagger: r(0.035),
                          liquid: false)
        case .snappy:
            return Motion(width: .spring(response: r(0.26), dampingFraction: 0.86),
                          height: .spring(response: r(0.28), dampingFraction: 0.9),
                          content: .spring(response: r(0.24), dampingFraction: 0.9),
                          contentIn: .spring(response: r(0.24), dampingFraction: 0.9).delay(r(0.03)),
                          contentOut: .easeOut(duration: r(0.08)),
                          hover: .spring(response: 0.22, dampingFraction: 0.7),
                          stagger: r(0.02),
                          liquid: false)
        }
    }
}

// MARK: - Entrada con desenfoque

struct BlurFade: ViewModifier {
    var progress: Double   // 0 = oculto, 1 = visible
    var lift: CGFloat = -6

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 10)
            .scaleEffect(0.88 + 0.12 * progress, anchor: .top)
            .offset(y: (1 - progress) * lift)
    }
}

extension AnyTransition {
    static func orbitContent(_ motion: Motion) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurFade(progress: 0), identity: BlurFade(progress: 1))
                .animation(motion.contentIn),
            removal: .modifier(active: BlurFade(progress: 0, lift: 0), identity: BlurFade(progress: 1, lift: 0))
                .animation(motion.contentOut)
        )
    }
}

/// Cada elemento aparece un poco después que el anterior (efecto cascada).
struct Staggered: ViewModifier {
    let index: Int
    @Environment(\.orbitStatic) private var isStatic
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .modifier(BlurFade(progress: (shown || isStatic) ? 1 : 0, lift: -8))
            .onAppear {
                guard !isStatic else { return }
                let motion = Motion.current()
                withAnimation(motion.contentIn.delay(Double(index) * motion.stagger)) {
                    shown = true
                }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View { modifier(Staggered(index: index)) }
}

// MARK: - Entorno

private struct OrbitStaticKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Verdadero al dibujar capturas: todo aparece sin animación.
    var orbitStatic: Bool {
        get { self[OrbitStaticKey.self] }
        set { self[OrbitStaticKey.self] = newValue }
    }
}

// MARK: - Háptica

enum Haptics {
    static func tap() {
        guard Settings.shared.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func level() {
        guard Settings.shared.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
