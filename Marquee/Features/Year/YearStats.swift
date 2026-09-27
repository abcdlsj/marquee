import Foundation

struct YearStats {
    let year: Int
    /// Oldest first.
    let movies: [Movie]
    let byDay: [Int: [Movie]]

    init(year: Int, played: [Movie]) {
        self.year = year
        let cal = Calendar.current
        movies = played
            .filter { $0.playedDate.map { cal.component(.year, from: $0) } == year }
            .sorted { $0.playedDate! < $1.playedDate! }
        byDay = Dictionary(grouping: movies) { $0.playedDate!.dayKey }
    }

    var count: Int { movies.count }
    var hours: Int { Int((Double(movies.compactMap(\.runtimeMinutes).reduce(0, +)) / 60).rounded()) }
    var activeDays: Int { byDay.count }

    var longestStreak: Int {
        let cal = Calendar.current
        let days = Set(movies.compactMap { $0.playedDate.map { cal.startOfDay(for: $0) } }).sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        return best
    }

    /// (month 1…12, movies) for months that have any, newest first.
    var months: [(month: Int, movies: [Movie])] {
        let cal = Calendar.current
        let g = Dictionary(grouping: movies) { cal.component(.month, from: $0.playedDate!) }
        return g.keys.sorted(by: >).map { ($0, g[$0]!.reversed()) }
    }


    static func years(from played: [Movie]) -> [Int] {
        let cal = Calendar.current
        var ys = Set(played.compactMap { $0.playedDate.map { cal.component(.year, from: $0) } })
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
    static let en = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
}
