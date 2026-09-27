import Foundation

nonisolated enum EmbyError: LocalizedError {
    case badURL
    case http(Int, String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .badURL: "Invalid server address"
        case .http(let code, let body): "HTTP \(code)" + (body.isEmpty ? "" : "：\(body.prefix(120))")
        case .notSignedIn: "Not signed in"
        }
    }
}

nonisolated enum ImageKind: String, Sendable {
    case primary = "Primary", backdrop = "Backdrop", logo = "Logo", thumb = "Thumb"
}

/// Speaks the same protocol as Ember's Go client: `X-Emby-Authorization` header, `/emby/...` endpoints.
nonisolated final class EmbyClient: Sendable {
    static let clientName = "Marquee"
    static let version = "1.0"

    let baseURL: URL
    let userID: String
    let token: String
    private let session: URLSession

    init(baseURL: URL, userID: String, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.userID = userID
        self.token = token
        self.session = session
    }

    static let movieFields = "Overview,Genres,CommunityRating,CriticRating,OfficialRating,Taglines,ProductionYear,RunTimeTicks,OriginalTitle,ProviderIds"

    // MARK: Auth

    static func authHeader(token: String?) -> String {
        var h = #"MediaBrowser Client="\#(clientName)", Device="iPhone", DeviceId="\#(DeviceID.value)", Version="\#(version)""#
        if let token, !token.isEmpty { h += #", Token="\#(token)""# }
        return h
    }

    static func login(server: String, username: String, password: String) async throws -> (userID: String, token: String) {
        guard let base = normalize(server) else { throw EmbyError.badURL }
        var req = URLRequest(url: base.appending(path: "emby/Users/AuthenticateByName"))
        req.httpMethod = "POST"
        req.setValue(authHeader(token: nil), forHTTPHeaderField: "X-Emby-Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["Username": username, "Pw": password])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        struct Auth: Decodable {
            struct U: Decodable { let Id: String }
            let User: U
            let AccessToken: String
        }
        let auth = try JSONDecoder().decode(Auth.self, from: data)
        return (auth.User.Id, auth.AccessToken)
    }

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/emby") { s.removeLast(5) }
        if !s.contains("://") { s = "http://" + s }
        return URL(string: s)
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            throw EmbyError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }

    // MARK: Requests

    private func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var c = URLComponents(url: baseURL.appending(path: "emby/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return c.url!
    }

    private func send(_ method: String, _ path: String, _ query: [String: String] = [:]) async throws -> Data {
        var req = URLRequest(url: url(path, query))
        req.httpMethod = method
        req.setValue(Self.authHeader(token: token), forHTTPHeaderField: "X-Emby-Authorization")
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data)
        return data
    }

    private func movies(_ query: [String: String]) async throws -> [Movie] {
        var q = query
        q["Recursive"] = "true"
        q["IncludeItemTypes"] = "Movie"
        q["Fields"] = Self.movieFields
        q["EnableImageTypes"] = "Primary,Backdrop,Logo,Thumb"
        let data = try await send("GET", "Users/\(userID)/Items", q)
        return try JSONDecoder().decode(ItemsResponse.self, from: data).items
    }

    func ping() async -> Duration? {
        let start = ContinuousClock.now
        guard (try? await send("GET", "System/Info/Public")) != nil else { return nil }
        return ContinuousClock.now - start
    }

    /// Some reverse proxies in front of Emby reject `Limit` ≥ 100 (404), so large lists are paged.
    private static let pageSize = 50

    private func allMovies(_ query: [String: String], cap: Int = 2000) async throws -> [Movie] {
        var out: [Movie] = []
        while out.count < cap {
            var q = query
            q["StartIndex"] = "\(out.count)"
            q["Limit"] = "\(Self.pageSize)"
            let page = try await movies(q)
            out += page
            if page.count < Self.pageSize { break }
        }
        return out
    }

    func search(_ term: String) async throws -> [Movie] {
        try await movies(["SearchTerm": term, "Limit": "\(Self.pageSize)", "SortBy": "SortName"])
    }

    func latest(limit: Int = 48) async throws -> [Movie] {
        try await movies(["SortBy": "DateCreated", "SortOrder": "Descending", "Limit": "\(limit)"])
    }

    func favorites() async throws -> [Movie] {
        try await allMovies(["Filters": "IsFavorite", "SortBy": "DatePlayed,DateCreated", "SortOrder": "Descending"])
    }

    func played() async throws -> [Movie] {
        try await allMovies(["Filters": "IsPlayed", "SortBy": "DatePlayed", "SortOrder": "Descending"])
    }

    func movie(_ id: String) async throws -> Movie {
        let data = try await send("GET", "Users/\(userID)/Items/\(id)")
        return try JSONDecoder().decode(Movie.self, from: data)
    }

    func setFavorite(_ id: String, _ on: Bool) async throws -> UserData {
        let data = try await send(on ? "POST" : "DELETE", "Users/\(userID)/FavoriteItems/\(id)")
        return try JSONDecoder().decode(UserData.self, from: data)
    }

    func setPlayed(_ id: String, at date: Date?) async throws -> UserData {
        let data: Data
        if let date {
            data = try await send("POST", "Users/\(userID)/PlayedItems/\(id)", ["DatePlayed": EmbyDate.format(date)])
        } else {
            data = try await send("DELETE", "Users/\(userID)/PlayedItems/\(id)")
        }
        return try JSONDecoder().decode(UserData.self, from: data)
    }

    // MARK: Images

    /// `maxWidth` in pixels; nil requests the original upload.
    func imageURL(_ movie: Movie, _ kind: ImageKind, maxWidth: Int?, quality: Int = 92) -> URL? {
        let tag: String?
        let path: String
        switch kind {
        case .backdrop:
            tag = movie.backdropImageTags?.first
            path = "Items/\(movie.id)/Images/Backdrop/0"
        default:
            tag = movie.imageTags?[kind.rawValue]
            // The indexed form serves the original; the bare `/Images/Primary` is downscaled (to 450px tall) by some servers.
            path = kind == .logo ? "Items/\(movie.id)/Images/Logo" : "Items/\(movie.id)/Images/\(kind.rawValue)/0"
        }
        guard let tag else { return nil }
        var q = ["tag": tag, "quality": "\(quality)", "api_key": token]
        if let maxWidth { q["maxWidth"] = "\(maxWidth)" }
        return url(path, q)
    }
}

nonisolated enum DeviceID {
    static let value: String = {
        let key = "marquee.deviceID"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = "marquee-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(v, forKey: key)
        return v
    }()
}
