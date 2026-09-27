import SwiftUI

/// The year: four numbers, the heatmap, then every film watched, month by month.
struct YearView: View {
    @Environment(AppModel.self) private var model
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var selectedDay: Int?
    @State private var width: CGFloat = 400
    @State private var showShare = false

    private var years: [Int] { YearStats.years(from: model.played + model.episodes) }

    var body: some View {
        let stats = YearStats(year: year, played: model.played, episodes: model.episodes)
        CinemaStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar(stats)
                    statRow(stats).padding(.top, 24)
                    HeatmapView(
                        stats: stats,
                        cell: HeatmapView.cellSize(width: width - 48),
                        selected: selectedDay,
                        folded: false,
                        inset: 24,
                        onSelect: { key in selectedDay = selectedDay == key ? nil : key }
                    )
                    .id(year)
                    .padding(.top, 32)
                    .sensoryFeedback(.selection, trigger: selectedDay)

                    if let day = selectedDay, let items = stats.byDay[day] {
                        dayList(items)
                            .padding(.top, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    VStack(alignment: .leading, spacing: 36) {
                        ForEach(stats.months, id: \.month) { entry in
                            MonthSection(entry: entry)
                        }
                    }
                    .padding(.top, 48)
                }
                .padding(.bottom, 40)
                .animation(.smooth(duration: 0.35), value: selectedDay)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.refresh() }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background(Color.black)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showShare) { YearShareStudio(stats: stats) }
        }
        .onChange(of: year) { selectedDay = nil }
    }

    private func topBar(_ stats: YearStats) -> some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Year", selection: $year) {
                    ForEach(years.reversed(), id: \.self) { Text(String($0)).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(String(year)).font(.system(size: 16, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.fg)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 4)
                .frame(height: 22)
            }
            .buttonStyle(.glass)
            Spacer()
            GlassIcon(systemName: "square.and.arrow.up") { showShare = true }
                .disabled(stats.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func statRow(_ s: YearStats) -> some View {
        HStack(alignment: .top, spacing: 0) {
            stat(s.count, "films")
            stat(s.episodeCount, "episodes")
            stat(s.hours, "hours")
            stat(s.activeDays, "days")
        }
        .padding(.horizontal, 24)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 30, weight: .light))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .foregroundStyle(Theme.fg)
            Text(label).caption(11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayList(_ items: [Movie]) -> some View {
        let films = items.filter { !$0.isEpisode }
        let series = YearStats.group(items.filter(\.isEpisode))
        return GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(films) { m in
                    MovieLink(movie: m, source: "day-\(m.id)", cornerRadius: 18) {
                        dayRow(poster: m, title: m.name, detail: m.playedDate?.dotted ?? "", chevron: true)
                    }
                }
                ForEach(series) { entry in
                    dayRow(poster: entry.poster, title: entry.poster.name,
                           detail: entry.episodes.reversed().compactMap(\.episodeCode).joined(separator: ", "),
                           chevron: false)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func dayRow(poster: Movie, title: String, detail: String, chevron: Bool) -> some View {
        HStack(spacing: 14) {
            Poster(movie: poster, cornerRadius: 3).frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                Text(detail).caption(11).monospacedDigit().lineLimit(2)
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
            }
        }
        .padding(10)
        .glassEffect(chevron ? .regular.interactive() : .regular, in: .rect(cornerRadius: 18))
        .glassEffectTransition(.materialize)
    }
}

private struct MonthSection: View {
    let entry: YearStats.MonthEntry
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

    private var tally: String {
        let eps = entry.series.reduce(0) { $0 + $1.episodes.count }
        return [entry.films.isEmpty ? nil : "\(entry.films.count) \(entry.films.count == 1 ? "film" : "films")", eps == 0 ? nil : "\(eps) ep"]
            .compactMap { $0 }.joined(separator: "  ·  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(MonthName.full[entry.month - 1]).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.fg)
                Spacer()
                Text(tally).caption(12).monospacedDigit()
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entry.films) { m in
                    MovieLink(movie: m, source: "month-\(m.id)") {
                        VStack(alignment: .leading, spacing: 6) {
                            Poster(movie: m, cornerRadius: 3)
                            if let d = m.playedDate {
                                Text("\(MonthName.en[entry.month - 1]) \(Calendar.current.component(.day, from: d))")
                                    .caption(10.5).monospacedDigit()
                            }
                        }
                    }
                }
                ForEach(entry.series) { series in
                    VStack(alignment: .leading, spacing: 6) {
                        Poster(movie: series.poster, cornerRadius: 3)
                        Text("\(series.episodes.count) ep").caption(10.5).monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }
}
