import Foundation

nonisolated struct Movie: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    var originalTitle: String?
    var year: Int?
    var overview: String?
    var taglines: [String]?
    var genres: [String]?
    var communityRating: Double?
    var criticRating: Double?
    var officialRating: String?
    var runTimeTicks: Int64?
    var imageTags: [String: String]?
    var backdropImageTags: [String]?
    var people: [Person]?
    var userData: UserData?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", originalTitle = "OriginalTitle", year = "ProductionYear"
        case overview = "Overview", taglines = "Taglines", genres = "Genres"
        case communityRating = "CommunityRating", criticRating = "CriticRating"
        case officialRating = "OfficialRating", runTimeTicks = "RunTimeTicks"
        case imageTags = "ImageTags", backdropImageTags = "BackdropImageTags"
        case people = "People", userData = "UserData"
    }

    var isFavorite: Bool { userData?.isFavorite ?? false }
    var isPlayed: Bool { userData?.played ?? false }
    var playedDate: Date? { userData?.lastPlayedDate.flatMap(EmbyDate.parse) }

    var runtimeMinutes: Int? {
        guard let t = runTimeTicks, t > 0 else { return nil }
        return Int(t / 600_000_000)
    }

    var runtimeText: String? {
        guard let m = runtimeMinutes else { return nil }
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    var tagline: String? { taglines?.first.flatMap { $0.isEmpty ? nil : $0 } }
    var directors: [String] { people?.filter { $0.type == "Director" }.map(\.name) ?? [] }
    var cast: [String] { people?.filter { $0.type == "Actor" }.map(\.name) ?? [] }
    var hasLogo: Bool { imageTags?["Logo"] != nil }
    var hasBackdrop: Bool { !(backdropImageTags ?? []).isEmpty }

    static func == (a: Movie, b: Movie) -> Bool { a.id == b.id && a.userData == b.userData }
    func hash(into h: inout Hasher) { h.combine(id) }
}

nonisolated struct Person: Hashable, Codable, Sendable {
    let name: String
    let type: String?
    enum CodingKeys: String, CodingKey { case name = "Name", type = "Type" }
}

nonisolated struct UserData: Hashable, Codable, Sendable {
    var played: Bool
    var isFavorite: Bool
    var lastPlayedDate: String?
    var playCount: Int?

    enum CodingKeys: String, CodingKey {
        case played = "Played", isFavorite = "IsFavorite"
        case lastPlayedDate = "LastPlayedDate", playCount = "PlayCount"
    }
}

nonisolated struct ItemsResponse: Decodable, Sendable {
    let items: [Movie]
    let totalRecordCount: Int?
    enum CodingKeys: String, CodingKey { case items = "Items", totalRecordCount = "TotalRecordCount" }
}

nonisolated enum EmbyDate {
    /// Emby emits 7 fractional digits ("2026-06-28T16:52:49.0000000Z"), which ISO8601DateFormatter rejects.
    static func parse(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return try? Date(trimmed, strategy: .iso8601)
    }

    static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHHmmss"
        return f.string(from: date)
    }
}
