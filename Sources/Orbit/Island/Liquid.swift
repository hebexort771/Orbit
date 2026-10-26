import SwiftUI

// MARK: - Deformación del borde

/// Cómo está deformado el borde de abajo de la isla en este instante: una protuberancia que se estira
/// hacia el cursor, una gota colgando de ella y ondas que recorren el borde como en el agua.
struct LiquidDeform {
    struct Drop {
        var x: CGFloat
        var y: CGFloat
        var r: CGFloat
    }

    struct Wave {
        var x: CGFloat
        var amp: CGFloat
        var phase: CGFloat
        var front: CGFloat
    }

    /// Todo se mide desde el centro de la isla (x) y desde su borde de arriba (y).
    var cx: CGFloat = 0
    var amp: CGFloat = 0
    var width: CGFloat = 28
    var drop: Drop?
    var waves: [Wave] = []

    var isFlat: Bool { abs(amp) < 0.05 && drop == nil && waves.isEmpty }

    /// Cuánto baja el borde en `x`. Vale cero en las puntas del tramo recto para unirse sin saltos a las esquinas.
    func offset(_ x: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        let edge = min(x - lo, hi - x)
        let w = max(0, min(1, edge / 12))
        let window = w * w * (3 - 2 * w)
        guard window > 0 else { return 0 }
        var y: CGFloat = 0
        let u = (x - cx) / max(1, width)
        if abs(u) < 1 {
            let q = 1 - u * u
            y += amp * q * q * q
        }
        for wave in waves {
            let d = abs(x - wave.x)
            y += wave.amp * sin(d * 0.12 - wave.phase) * exp(-max(0, d - wave.front) / 18) * exp(-d / 260)
        }
        return y * window
    }
}

extension IslandShape {
    /// Recorre el tramo recto de abajo punto por punto, aplicando la deformación líquida.
    func addLiquidBottom(_ p: inout Path, from x0: CGFloat, to x1: CGFloat, y: CGFloat, mid: CGFloat) {
        guard let liquid, !liquid.isFlat, abs(x1 - x0) > 4 else { return }
        let lo = min(x0, x1) - mid
        let hi = max(x0, x1) - mid
        let step: CGFloat = 1.5
        let count = Int(abs(x1 - x0) / step)
        let dir: CGFloat = x1 > x0 ? 1 : -1
        guard count > 1 else { return }
        for i in 1..<count {
            let x = x0 + dir * CGFloat(i) * step
            p.addLine(to: CGPoint(x: x, y: y + liquid.offset(x - mid, lo: lo, hi: hi)))
        }
        p.addLine(to: CGPoint(x: x1, y: y))
    }
}

// MARK: - La gota

/// La gota y el "cuello" de agua que la une a la isla (unión tipo metaball, con curvas suaves).
/// Se dibujan por separado para que al superponerse nunca quede un hueco.
struct LiquidDrop: Shape {
    enum Part { case ball, neck }
    let deform: LiquidDeform
    let bottom: CGFloat
    let part: Part

    func path(in rect: CGRect) -> Path {
        guard let drop = deform.drop, drop.r > 0.5 else { return Path() }
        let mid = rect.midX
        let c2 = CGPoint(x: mid + drop.x, y: drop.y)
        switch part {
        case .ball:
            return Path(ellipseIn: CGRect(x: c2.x - drop.r, y: c2.y - drop.r, width: drop.r * 2, height: drop.r * 2))
        case .neck:
            let tipY = bottom + max(0, deform.amp)
            let r1 = max(3, min(deform.width * 0.42, 11))
            let c1 = CGPoint(x: mid + deform.cx, y: tipY - r1)
            return Self.metaball(r1: r1, r2: drop.r, c1: c1, c2: c2) ?? Path()
        }
    }

    /// Une dos círculos con un puente de curvas, como dos gotas de agua que se juntan.
    static func metaball(r1: CGFloat, r2: CGFloat, c1: CGPoint, c2: CGPoint, v: CGFloat = 0.55, handle: CGFloat = 2.4) -> Path? {
        let dx = c2.x - c1.x, dy = c2.y - c1.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard r1 > 0, r2 > 0, d > abs(r1 - r2), d < r1 + r2 * 2.5 + 70 else { return nil }
        var u1: CGFloat = 0, u2: CGFloat = 0
        if d < r1 + r2 {
            u1 = acos(max(-1, min(1, (r1 * r1 + d * d - r2 * r2) / (2 * r1 * d))))
            u2 = acos(max(-1, min(1, (r2 * r2 + d * d - r1 * r1) / (2 * r2 * d))))
        }
        let between = atan2(c2.y - c1.y, c2.x - c1.x)
        let spread = acos(max(-1, min(1, (r1 - r2) / d)))
        let a1 = between + u1 + (spread - u1) * v
        let a2 = between - u1 - (spread - u1) * v
        let a3 = between + .pi - u2 - (.pi - u2 - spread) * v
        let a4 = between - .pi + u2 + (.pi - u2 - spread) * v
        func at(_ c: CGPoint, _ a: CGFloat, _ r: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        let p1 = at(c1, a1, r1), p2 = at(c1, a2, r1), p3 = at(c2, a3, r2), p4 = at(c2, a4, r2)
        let gap = ((p1.x - p3.x) * (p1.x - p3.x) + (p1.y - p3.y) * (p1.y - p3.y)).squareRoot()
        let base = min(v * handle, gap / (r1 + r2))
        let scale = base * min(1, d * 2 / (r1 + r2))
        let h1 = at(p1, a1 - .pi / 2, r1 * scale)
        let h2 = at(p2, a2 + .pi / 2, r1 * scale)
        let h3 = at(p3, a3 + .pi / 2, r2 * scale)
        let h4 = at(p4, a4 - .pi / 2, r2 * scale)
        var path = Path()
        path.move(to: p1)
        path.addCurve(to: p3, control1: h1, control2: h3)
        path.addLine(to: p4)
        path.addCurve(to: p2, control1: h4, control2: h2)
        path.addLine(to: c1)
        path.closeSubpath()
        return path
    }
}

// MARK: - Simulación

/// La física del agua: resortes con un poco de rebote para la protuberancia, la gota y las ondas.
/// Solo trabaja mientras hay algo moviéndose; en reposo no gasta nada.
@MainActor
final class LiquidField: ObservableObject {
    struct Geometry {
        /// Alto actual de la isla y mitad del tramo recto de abajo.
        let height: CGFloat
        let halfFlat: CGFloat
        /// Solo la isla cerrada se estira hacia el cursor; abierta solo ondula.
        let collapsed: Bool
    }

    private struct Spring {
        var value: CGFloat = 0
        var velocity: CGFloat = 0
        mutating func step(_ target: CGFloat, k: CGFloat, c: CGFloat, dt: CGFloat) {
            let a = k * (target - value) - c * velocity
            velocity += a * dt
            value += velocity * dt
        }
    }

    private struct Ripple {
        var x: CGFloat
        var strength: CGFloat
        var age: CGFloat
    }

    @Published private(set) var active = false
    private(set) var frame = LiquidDeform()
    private var pointer: CGPoint?
    private var inside = false
    private var last: Date?
    private var amp = Spring(), cx = Spring(), width = Spring(value: 28)
    private var dropX = Spring(), dropY = Spring(), dropR = Spring()
    private var ripples: [Ripple] = []
    private var hadDrop = false
    private var resting = false

    /// El cursor, medido desde el centro de arriba de la isla (nil = lejos).
    func point(_ location: CGPoint?, inside: Bool) {
        pointer = location
        self.inside = inside
        if location != nil && !active { wake() }
    }

    /// Una onda que recorre el borde de abajo, como al tocar el agua.
    func splash(at x: CGFloat = 0, strength: CGFloat = 3) {
        ripples.append(Ripple(x: x, strength: strength, age: 0))
        if ripples.count > 4 { ripples.removeFirst() }
        if !active { wake() }
    }

    private func wake() {
        active = true
        resting = false
        last = nil
    }

    func step(at date: Date, geometry g: Geometry) -> LiquidDeform {
        if let last, date <= last { return frame }
        let dt = CGFloat(min(1.0 / 30.0, max(1.0 / 240.0, last.map { date.timeIntervalSince($0) } ?? 1.0 / 60.0)))
        last = date
        advance(dt: dt, geometry: g)
        return frame
    }

    /// Para las capturas de prueba: deja correr la física sin reloj real.
    func simulate(pointer location: CGPoint?, inside: Bool = false, geometry: Geometry, seconds: Double) {
        pointer = location
        self.inside = inside
        var t = 0.0
        while t < seconds {
            advance(dt: 1.0 / 120.0, geometry: geometry)
            t += 1.0 / 120.0
        }
    }

    private func advance(dt: CGFloat, geometry g: Geometry) {
        var ampTarget: CGFloat = 0
        var cxTarget = cx.value
        var widthTarget: CGFloat = 26
        var dropTarget: CGFloat = 0
        var dropXTarget = cx.value
        var dropYTarget = g.height + max(0, amp.value) - 2

        if g.collapsed, !inside, let p = pointer, g.halfFlat > 24 {
            let below = p.y - g.height
            let side = max(0, abs(p.x) - g.halfFlat - 6)
            let down = max(0, below)
            let distance = (side * side + down * down).squareRoot()
            let raw = below > -8 ? max(0, min(1, 1 - distance / 130)) : 0
            let t = raw * raw * (3 - 2 * raw)
            ampTarget = 12 * pow(t, 1.35)
            widthTarget = 22 + 16 * t
            let limit = max(0, g.halfFlat - widthTarget * 0.9)
            cxTarget = max(-limit, min(limit, p.x))
            if t > 0.32 && below > 16 {
                let k = (t - 0.32) / 0.68
                dropTarget = 2.5 + 6.5 * k
                dropXTarget = cxTarget + (p.x - cxTarget) * 0.5
                dropYTarget = g.height + ampTarget + dropTarget * 0.9 + min(below * 0.34, 40) * k
            }
        }

        amp.step(ampTarget, k: 190, c: 13, dt: dt)
        cx.step(cxTarget, k: 240, c: 24, dt: dt)
        width.step(widthTarget, k: 200, c: 20, dt: dt)
        dropR.step(dropTarget, k: 170, c: 15, dt: dt)
        dropX.step(dropXTarget, k: 150, c: 13, dt: dt)
        dropY.step(dropYTarget, k: 150, c: 12, dt: dt)
        if dropR.value < 0 { dropR.value = 0; dropR.velocity = 0 }

        // La gota vuelve a entrar al notch: pequeña onda, como cuando una gota cae al agua.
        if dropR.value > 4 { hadDrop = true }
        if hadDrop && dropTarget == 0 && dropR.value < 1.2 {
            hadDrop = false
            ripples.append(Ripple(x: cx.value, strength: 2.2, age: 0))
        }

        for i in ripples.indices { ripples[i].age += dt }
        ripples.removeAll { $0.age > 1.8 }

        frame = LiquidDeform(
            cx: cx.value,
            amp: max(-3, amp.value),
            width: max(10, width.value),
            drop: dropR.value > 0.6 ? LiquidDeform.Drop(x: dropX.value, y: dropY.value, r: dropR.value) : nil,
            waves: ripples.map { r in
                LiquidDeform.Wave(x: r.x, amp: r.strength * exp(-r.age / 0.55), phase: r.age * 9, front: 30 + 160 * r.age)
            }
        )

        let calm = ampTarget == 0 && dropTarget == 0 && ripples.isEmpty
            && abs(amp.value) < 0.05 && abs(amp.velocity) < 0.05 && dropR.value < 0.05
        if calm && !resting {
            resting = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.resting else { return }
                    self.active = false
                    self.frame = LiquidDeform()
                }
            }
        } else if !calm {
            resting = false
        }
    }
}

// MARK: - Dibujo

/// El cuerpo negro de la isla con su borde de agua, la gota y sus brillos.
struct LiquidIslandFill: View {
    let shape: IslandShape
    let layout: IslandLayout
    let collapsed: Bool
    let shadow: Bool
    @ObservedObject var field: LiquidField
    @ObservedObject private var settings = Settings.shared
    @Environment(\.orbitStatic) private var isStatic

    var body: some View {
        let running = field.active && settings.liquidNotch && !isStatic
        TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !running)) { timeline in
            let deform = deformation(at: timeline.date, running: running)
            ZStack(alignment: .top) {
                IslandShape(ear: shape.ear, bottom: shape.bottom, topCorner: shape.topCorner, liquid: deform)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(shadow ? 0.55 : 0), radius: 18, y: 10)
                if deform.drop != nil {
                    ZStack {
                        LiquidDrop(deform: deform, bottom: layout.height, part: .neck).fill(Color.black)
                        LiquidDrop(deform: deform, bottom: layout.height, part: .ball).fill(Color.black)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                }
                shine(deform)
            }
        }
        .allowsHitTesting(false)
    }

    private func deformation(at date: Date, running: Bool) -> LiquidDeform {
        if isStatic { return settings.liquidNotch ? field.frame : LiquidDeform() }
        guard running else { return LiquidDeform() }
        let geometry = LiquidField.Geometry(height: layout.height, halfFlat: layout.width / 2 - layout.bottom,
                                            collapsed: collapsed)
        return field.step(at: date, geometry: geometry)
    }

    /// Brillo de agua: un reflejo fino en la curva que se estira y un punto de luz en la gota.
    @ViewBuilder
    private func shine(_ deform: LiquidDeform) -> some View {
        let strength = max(0, min(1, deform.amp / 12))
        if strength > 0.1 || deform.drop != nil {
            GeometryReader { geo in
                let mid = geo.size.width / 2
                ZStack(alignment: .topLeading) {
                    Path { p in
                        let from = deform.cx - deform.width * 0.55
                        let to = deform.cx + deform.width * 0.55
                        let lo = -layout.width / 2 + layout.bottom
                        let hi = layout.width / 2 - layout.bottom
                        var x = from
                        var first = true
                        while x <= to {
                            let point = CGPoint(x: mid + x, y: layout.height + deform.offset(x, lo: lo, hi: hi) - 1.2)
                            if first { p.move(to: point); first = false } else { p.addLine(to: point) }
                            x += 2
                        }
                    }
                    .stroke(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.2), .white.opacity(0)],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                    .opacity(strength)
                    .blur(radius: 0.4)

                    if let drop = deform.drop {
                        let r = drop.r
                        Ellipse()
                            .fill(RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0)], center: .center,
                                                 startRadius: 0, endRadius: r * 0.4))
                            .frame(width: r * 0.8, height: r * 0.55)
                            .position(x: mid + drop.x - r * 0.32, y: drop.y - r * 0.4)
                            .blendMode(.plusLighter)
                        Circle()
                            .trim(from: 0.05, to: 0.45)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                            .frame(width: r * 2 - 1.5, height: r * 2 - 1.5)
                            .position(x: mid + drop.x, y: drop.y)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
