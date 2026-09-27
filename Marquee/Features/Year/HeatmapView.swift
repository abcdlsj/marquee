import SwiftUI

/// A year of evenings as a 7 × 53 grid. Folded: two half-year bands (whole year at a glance).
/// Unfolded: one row sized to show half a year, scrolling left into earlier months.
struct HeatmapView: View {
    let stats: YearStats
    var cell: CGFloat
    var gap: CGFloat = 2.5
    var accent: Color = .white
    /// Foreground for empty cells, labels and the selection ring.
    var ink: Color = .white
    var selected: Int? = nil
    var animated = true
    var folded = true
    /// Side margin for the unfolded row; the scrolling window is clipped to it.
    var inset: CGFloat = 0
    var onSelect: ((Int) -> Void)? = nil

    @State private var lit = false
    @State private var anchorWeek: Int?

    /// Cell edge that makes a half-year band (27 weeks) exactly `width` wide.
    static func cellSize(width: CGFloat, gap: CGFloat = 2.5) -> CGFloat {
        ((width - 26 * gap) / 27 * 10).rounded(.down) / 10
    }
    private let today = Date.now.dayKey

    var body: some View {
        let weeks = stats.weeks
        Group {
            if folded {
                let half = (weeks.count + 1) / 2
                VStack(alignment: .leading, spacing: cell * 1.1) {
                    ForEach([0, half], id: \.self) { start in
                        band(Array(weeks[start..<min(weeks.count, start + half)]), offset: start)
                    }
                }
            } else {
                ScrollView(.horizontal) {
                    band(weeks, offset: 0)
                }
                .scrollIndicators(.hidden)
                .scrollPosition(id: $anchorWeek, anchor: .trailing)
                .onAppear { anchorWeek = currentWeek(in: weeks) }
                .padding(.horizontal, inset)
            }
        }
        .onAppear { lit = true }
    }

    private func band(_ weeks: [[Date?]], offset: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            monthLabels(weeks)
            HStack(alignment: .top, spacing: gap) {
                ForEach(weeks.indices, id: \.self) { w in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { d in
                            cellView(weeks[w][d])
                        }
                    }
                    .opacity(lit || !animated ? 1 : 0)
                    .scaleEffect(lit || !animated ? 1 : 0.5, anchor: .center)
                    .animation(.spring(duration: 0.5, bounce: 0.35).delay(Double(offset + w) * 0.014), value: lit)
                    .id(offset + w)
                }
            }
            .scrollTargetLayout()
        }
    }

    /// The week containing today, or the last week for a past year.
    private func currentWeek(in weeks: [[Date?]]) -> Int {
        weeks.firstIndex { $0.contains { $0?.dayKey == today } } ?? weeks.count - 1
    }

    @ViewBuilder
    private func cellView(_ date: Date?) -> some View {
        if let date {
            let key = date.dayKey
            let n = stats.byDay[key]?.count ?? 0
            let isSel = selected == key
            RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                .fill(color(n, future: key > today))
                .frame(width: cell, height: cell)
                .overlay {
                    if isSel {
                        RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                            .strokeBorder(Theme.cool, lineWidth: 1.2)
                    }
                }
                .contentShape(.rect)
                .onTapGesture { if n > 0 { onSelect?(key) } }
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private func color(_ n: Int, future: Bool) -> Color {
        switch n {
        case 0: ink.opacity(future ? 0.04 : 0.09)
        case 1: accent.opacity(0.82)
        case 2: accent.opacity(0.92)
        default: accent
        }
    }

    private func monthLabels(_ weeks: [[Date?]]) -> some View {
        let cal = Calendar.current
        var starts: [(col: Int, month: Int)] = []
        for (i, w) in weeks.enumerated() {
            if let d = w.compactMap({ $0 }).first(where: { cal.component(.day, from: $0) == 1 }) {
                if i < weeks.count - 2 { starts.append((i, cal.component(.month, from: d))) }
            } else if i == 0, let d = w.compactMap({ $0 }).first,
                      !(weeks.count > 2 && weeks[1...2].joined().contains { $0.map { cal.component(.day, from: $0) == 1 } ?? false }) {
                starts.append((0, cal.component(.month, from: d)))
            }
        }
        return ZStack(alignment: .topLeading) {
            ForEach(starts, id: \.col) { s in
                Text(MonthName.en[s.month - 1])
                    .font(.system(size: max(7, cell * 0.9)))
                    .foregroundStyle(ink.opacity(0.35))
                    .fixedSize()
                    .offset(x: CGFloat(s.col) * (cell + gap))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(9, cell * 1.2))
    }
}
