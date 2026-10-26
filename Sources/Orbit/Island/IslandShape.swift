import SwiftUI

/// La silueta de la isla: pegada arriba con "orejas" cóncavas como el notch real,
/// o una píldora flotante. Todas sus curvas se pueden animar.
struct IslandShape: Shape {
    var ear: CGFloat
    var bottom: CGFloat
    var topCorner: CGFloat
    /// Deformación de agua del borde de abajo (no se anima con SwiftUI: la mueve su propia física).
    var liquid: LiquidDeform? = nil

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(ear, AnimatablePair(bottom, topCorner)) }
        set {
            ear = newValue.first
            bottom = newValue.second.first
            topCorner = newValue.second.second
        }
    }

    private struct Frame {
        var left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat
        var ear: CGFloat, base: CGFloat, corner: CGFloat
    }

    private func frame(in rect: CGRect) -> Frame {
        let e = max(0, min(ear, rect.width / 4, rect.height / 2))
        let left = rect.minX + e
        let right = rect.maxX - e
        let bodyW = max(0, right - left)
        let height = max(0, rect.height)
        let corner = max(0, min(topCorner, bodyW / 2, height / 2))
        let base = max(0, min(bottom, bodyW / 2, max(0, height - max(e, corner))))
        return Frame(left: left, right: right, top: rect.minY, bottom: rect.maxY, ear: e, base: base, corner: corner)
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard rect.width > 0.5, rect.height > 0.5 else { return p }
        let f = frame(in: rect)

        if f.ear < 0.5 && f.corner > 0.5 {
            // Píldora flotante
            p.move(to: CGPoint(x: f.left + f.corner, y: f.top))
            p.addLine(to: CGPoint(x: f.right - f.corner, y: f.top))
            p.addArc(tangent1End: CGPoint(x: f.right, y: f.top), tangent2End: CGPoint(x: f.right, y: f.bottom), radius: f.corner)
            p.addArc(tangent1End: CGPoint(x: f.right, y: f.bottom), tangent2End: CGPoint(x: f.left, y: f.bottom), radius: f.base)
            addLiquidBottom(&p, from: f.right - f.base, to: f.left + f.base, y: f.bottom, mid: rect.midX)
            p.addArc(tangent1End: CGPoint(x: f.left, y: f.bottom), tangent2End: CGPoint(x: f.left, y: f.top), radius: f.base)
            p.addArc(tangent1End: CGPoint(x: f.left, y: f.top), tangent2End: CGPoint(x: f.right, y: f.top), radius: f.corner)
            p.closeSubpath()
            return p
        }

        // Pegada al borde superior, con orejas cóncavas
        p.move(to: CGPoint(x: f.left - f.ear, y: f.top))
        if f.ear > 0.5 {
            p.addArc(tangent1End: CGPoint(x: f.left, y: f.top), tangent2End: CGPoint(x: f.left, y: f.bottom), radius: f.ear)
        } else {
            p.addLine(to: CGPoint(x: f.left, y: f.top))
        }
        p.addArc(tangent1End: CGPoint(x: f.left, y: f.bottom), tangent2End: CGPoint(x: f.right, y: f.bottom), radius: f.base)
        addLiquidBottom(&p, from: f.left + f.base, to: f.right - f.base, y: f.bottom, mid: rect.midX)
        p.addArc(tangent1End: CGPoint(x: f.right, y: f.bottom), tangent2End: CGPoint(x: f.right, y: f.top), radius: f.base)
        if f.ear > 0.5 {
            p.addArc(tangent1End: CGPoint(x: f.right, y: f.top), tangent2End: CGPoint(x: f.right + f.ear, y: f.top), radius: f.ear)
        } else {
            p.addLine(to: CGPoint(x: f.right, y: f.top))
        }
        p.addLine(to: CGPoint(x: f.right + f.ear, y: f.top))
        p.closeSubpath()
        return p
    }

    /// Mitad izquierda del contorno visible: desde arriba hasta el centro de abajo.
    /// La estela de luz recorre este camino (y su reflejo a la derecha).
    func leftHalf(in rect: CGRect) -> Path {
        var p = Path()
        guard rect.width > 0.5, rect.height > 0.5 else { return p }
        let f = frame(in: rect)
        let mid = rect.midX
        if f.ear < 0.5 && f.corner > 0.5 {
            p.move(to: CGPoint(x: mid, y: f.top))
            p.addLine(to: CGPoint(x: f.left + f.corner, y: f.top))
            p.addArc(tangent1End: CGPoint(x: f.left, y: f.top), tangent2End: CGPoint(x: f.left, y: f.bottom), radius: f.corner)
        } else {
            p.move(to: CGPoint(x: f.left - f.ear, y: f.top))
            if f.ear > 0.5 {
                p.addArc(tangent1End: CGPoint(x: f.left, y: f.top), tangent2End: CGPoint(x: f.left, y: f.bottom), radius: f.ear)
            } else {
                p.addLine(to: CGPoint(x: f.left, y: f.top))
            }
        }
        p.addArc(tangent1End: CGPoint(x: f.left, y: f.bottom), tangent2End: CGPoint(x: f.right, y: f.bottom), radius: f.base)
        p.addLine(to: CGPoint(x: mid, y: f.bottom))
        return p
    }
}

/// Un tramo de la estela que viaja por el contorno.
struct CometTrail: Shape {
    var island: IslandShape
    var phase: CGFloat
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        let to = min(1, max(0, phase))
        let from = max(0, min(1, phase - length))
        guard to - from > 0.001 else { return Path() }
        return island.leftHalf(in: rect).trimmedPath(from: from, to: to)
    }
}
