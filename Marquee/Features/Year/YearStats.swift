import Foundation

struct YearStats {
    let year: Int
    /// Films, oldest first.
    let movies: [Movie]
    /// Episodes, oldest first. Series are counted by episode.
    let episodes: [Movie]
    /// Films and episodes by day.
    let byDay: [Int: [Movie]]

    struct SeriesEntry: Identifiable {
        let poster: Movie
        /// Newest first.
        let episodes: [Movie]
        var id: String { poster.id }
    }

    struct MonthEntry {
        let month: Int
        /// Newest first.
        let films: [Movie]
        let series: [SeriesEntry]
    }

    init(year: Int, played: [Movie], episodes: [Movie]) {
        self.year = year
        let cal = Calendar.current
        func inYear(_ list: [Movie]) -> [Movie] {
            list.filter { $0.playedDate.map { cal.component(.year, from: $0) } == year }
                .sorted { $0.playedDate! < $1.playedDate! }
        }
        movies = inYear(played)
        self.episodes = inYear(episodes)
        byDay = Dictionary(grouping: movies + self.episodes) { $0.playedDate!.dayKey }
    }

    var count: Int { movies.count }
    var episodeCount: Int { episodes.count }
    var hours: Int {
        let minutes = (movies + episodes).compactMap(\.runtimeMinutes).reduce(0, +)
        return Int((Double(minutes) / 60).rounded())
    }
    var activeDays: Int { byDay.count }
    var isEmpty: Bool { movies.isEmpty && episodes.isEmpty }

    /// Months that have anything, newest first.
    var months: [MonthEntry] {
        let cal = Calendar.current
        let films = Dictionary(grouping: movies) { cal.component(.month, from: $0.playedDate!) }
        let eps = Dictionary(grouping: episodes) { cal.component(.month, from: $0.playedDate!) }
        return Set(films.keys).union(eps.keys).sorted(by: >).map { m in
            MonthEntry(month: m, films: (films[m] ?? []).reversed(), series: Self.group(eps[m] ?? []))
        }
    }

    /// Episodes folded by series, most recently watched series first.
    static func group(_ episodes: [Movie]) -> [SeriesEntry] {
        let newest = episodes.sorted { $0.playedDate! > $1.playedDate! }
        var order: [String] = []
        var groups: [String: [Movie]] = [:]
        for e in newest {
            if groups[e.seriesKey] == nil { order.append(e.seriesKey) }
            groups[e.seriesKey, default: []].append(e)
        }
        return order.map { SeriesEntry(poster: groups[$0]![0].seriesPoster, episodes: groups[$0]!) }
    }

    /// Distinct posters (films, and series for episodes), most recent first.
    func recentPosters(_ limit: Int) -> [Movie] {
        var seen = Set<String>()
        var out: [Movie] = []
        for item in (movies + episodes).sorted(by: { $0.playedDate! > $1.playedDate! }) {
            let p = item.isEpisode ? item.seriesPoster : item
            if seen.insert(p.id).inserted { out.append(p) }
            if out.count == limit { break }
        }
        return out
    }

    static func years(from items: [Movie]) -> [Int] {
        let cal = Calendar.current
        var ys = Set(items.compactMap { $0.playedDate.map { cal.component(.year, from: $0) } })
        ys.insert(cal.component(.year, from: .now))
        return ys.sorted()
    }

    /// Monday-first week columns covering the whole year; nil pads days outside it.
    var weeks: [[Date?]] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        let lead = (cal.component(.weekday, from: start) + 5) % 7
        var cols: [[Date?]] = []
        var col: [Date?] = Array(repeating: nil, count: lead)
        var d = start
        while d < end {
            col.append(d)
            if col.count == 7 { cols.append(col); col = [] }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        if !col.isEmpty { cols.append(col + Array(repeating: nil, count: 7 - col.count)) }
        return cols
    }
}

enum MonthName {
    static let en = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let full = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
}
