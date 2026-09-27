import SwiftUI

struct YearShareStudio: View {
    let stats: YearStats
    @Environment(AppModel.self) private var model
    @State private var posters: [String: UIImage] = [:]
    @State private var ready = false

    private var picks: [Movie] { Array(stats.movies.suffix(12).reversed()) }

    var body: some View {
        ShareStage(titles: ["Black", "White"], ready: ready, exportName: "\(stats.year)") { i in
            YearTemplate(stats: stats, picks: picks, posters: posters, light: i == 1)
        }
        .task {
            await withTaskGroup(of: (String, UIImage?).self) { group in
                for m in picks {
                    group.addTask { (m.id, await model.image(m, .primary, maxWidth: 480)) }
                }
                for await (id, img) in group { if let img { posters[id] = img } }
            }
            ready = true
        }
    }
}

struct YearTemplate: View {
    let stats: YearStats
    let picks: [Movie]
    let posters: [String: UIImage]
    let light: Bool

    private var bg: Color { light ? Color(white: 0.96) : .black }
    private var ink: Color { light ? Color(white: 0.08) : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(stats.year))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.top, 34)

            HStack(alignment: .top, spacing: 0) {
                stat(stats.count, "films")
                stat(stats.hours, "hours")
                stat(stats.activeDays, "days")
            }
            .padding(.top, 22)

            HeatmapView(
                stats: stats,
                cell: HeatmapView.cellSize(width: 312, gap: 2),
                gap: 2,
                accent: ink,
                ink: ink,
                animated: false
            )
            .padding(.top, 28)

            Spacer(minLength: 16)
            mosaic
            HStack {
                Spacer()
                Text("MARQUEE").font(.system(size: 7.5, weight: .medium)).tracking(2.2).foregroundStyle(ink.opacity(0.35))
            }
            .padding(.top, 18)
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 24)
        .frame(width: 360, height: 640)
        .background(bg)
    }

    private func stat(_ v: Int, _ k: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(v)").font(.system(size: 30, weight: .light)).monospacedDigit().foregroundStyle(ink)
            Text(k).font(.system(size: 9)).foregroundStyle(ink.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mosaic: some View {
        let cols = 4
        let gap: CGFloat = 6
        let w = ((312 - gap * CGFloat(cols - 1)) / CGFloat(cols)).rounded(.down)
        let rows = min(2, (picks.count + cols - 1) / cols)
        let shown = Array(picks.prefix(rows * cols))
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(w), spacing: gap), count: cols), alignment: .leading, spacing: gap) {
            ForEach(shown) { m in
                Group {
                    if let img = posters[m.id] {
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ink.opacity(0.06)
                    }
                }
                .frame(width: w, height: w * 1.5)
                .clipped()
            }
        }
    }
}
