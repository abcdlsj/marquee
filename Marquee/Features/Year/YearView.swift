import SwiftUI

/// The year: four numbers, the heatmap, then every film watched, month by month.
struct YearView: View {
    @Environment(AppModel.self) private var model
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var selectedDay: Int?
    @State private var width: CGFloat = 400
    @State private var showShare = false

    private var years: [Int] { YearStats.years(from: model.played) }

    var body: some View {
        let stats = YearStats(year: year, played: model.played)
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

                    if let day = selectedDay, let movies = stats.byDay[day] {
                        dayList(movies)
                            .padding(.top, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    VStack(alignment: .leading, spacing: 36) {
                        ForEach(stats.months, id: \.month) { entry in
                            MonthSection(month: entry.month, movies: entry.movies)
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
                .disabled(stats.count == 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func statRow(_ s: YearStats) -> some View {
        HStack(alignment: .top, spacing: 0) {
            stat(s.count, "films")
            stat(s.hours, "hours")
            stat(s.activeDays, "days")
            stat(s.longestStreak, "streak")
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

    private func dayList(_ movies: [Movie]) -> some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(movies) { m in
                    MovieLink(movie: m, source: "day-\(m.id)", cornerRadius: 18) {
                        HStack(spacing: 14) {
                            Poster(movie: m, cornerRadius: 3).frame(width: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.fg)
                                Text(m.playedDate?.dotted ?? "").caption(11).monospacedDigit()
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        }
                        .padding(10)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                        .glassEffectTransition(.materialize)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct MonthSection: View {
    let month: Int
    let movies: [Movie]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(MonthName.full[month - 1]).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.fg)
                Spacer()
                Text("\(movies.count)").caption(12).monospacedDigit()
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(movies) { m in
                    MovieLink(movie: m, source: "month-\(m.id)") {
                        VStack(alignment: .leading, spacing: 6) {
                            Poster(movie: m, cornerRadius: 3)
                            if let d = m.playedDate {
                                Text("\(MonthName.en[month - 1]) \(Calendar.current.component(.day, from: d))").caption(10.5).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }
}
