import SwiftUI

/// Acomoda palabras sueltas como un párrafo: salta de línea cuando no caben.
struct WordFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var center: Bool

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width + 0.5 {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((index, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let list = rows(subviews, width: width)
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for (i, row) in list.enumerated() {
            let rowWidth = row.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            widest = max(widest, rowWidth)
            height += (row.map(\.size.height).max() ?? 0) + (i > 0 ? lineSpacing : 0)
        }
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let rowWidth = row.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            let rowHeight = row.map(\.size.height).max() ?? 0
            var x = center ? bounds.minX + (bounds.width - rowWidth) / 2 : bounds.minX
            for item in row {
                subviews[item.index].place(at: CGPoint(x: x, y: y + rowHeight - item.size.height),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }
}

/// Una palabra que se llena de luz de izquierda a derecha mientras se canta,
/// sube un poquito y brilla más si la nota es larga.
struct KaraokeWord: View {
    let text: String
    let size: CGFloat
    let progress: Double
    let duration: Double
    let glow: Color
    var dim: Double = 0.3

    var body: some View {
        let p = max(0, min(1, progress))
        let singing = p > 0 && p < 1
        let swell = singing ? sin(.pi * p) : 0
        let long = duration > 0.7
        let label = Text(text).font(.system(size: size, weight: .bold))
        // Borde suave del barrido de luz (más suave en notas largas)
        let soft = long ? 0.45 : 0.3
        label
            .foregroundStyle(.white.opacity(dim))
            .overlay(alignment: .leading) {
                label
                    .foregroundStyle(.white)
                    .mask(
                        LinearGradient(stops: [.init(color: .black, location: max(0, p * (1 + soft) - soft)),
                                               .init(color: .clear, location: min(1, p * (1 + soft)))],
                                       startPoint: .leading, endPoint: .trailing)
                    )
            }
            .shadow(color: glow.opacity((long ? 0.8 : 0.4) * swell), radius: size * (long ? 0.42 : 0.24) * swell)
            .scaleEffect(1 + (long ? 0.045 : 0.018) * swell, anchor: .bottom)
            .offset(y: -size * 0.055 * easeOut(p))
    }

    private func easeOut(_ x: Double) -> CGFloat {
        CGFloat(1 - pow(1 - x, 3))
    }
}

/// La línea que suena, palabra por palabra al ritmo del cantante (60 cuadros por segundo).
struct KaraokeLive: View {
    let words: [WordTiming]
    let size: CGFloat
    let center: Bool
    let glow: Color
    var dim: Double = 0.3
    @EnvironmentObject private var media: NowPlayingService
    @Environment(\.orbitStatic) private var isStatic

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isStatic || !media.isPlaying)) { timeline in
            let time = media.lyricsTime(at: timeline.date)
            WordFlow(spacing: size * 0.26, lineSpacing: size * 0.2, center: center) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    KaraokeWord(text: word.text, size: size,
                                progress: (time - word.start) / word.duration,
                                duration: word.duration, glow: glow, dim: dim)
                }
            }
        }
    }
}
