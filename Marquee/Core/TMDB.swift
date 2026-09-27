import Foundation

/// Original-resolution posters from TMDB (often 2000×3000), looked up by the TMDB id Emby already stores.
actor TMDB {
    static let shared = TMDB()

    private var key: String?
    /// tmdbID → chosen file path; "" means TMDB has no poster for it.
    private var paths: [String: String]
    private var inflight: [String: Task<String?, Never>] = [:]
    /// After a network failure (e.g. TMDB unreachable), skip lookups for a while instead of stalling every image.
    private var backoffUntil: Date?
    private let session: URLSession
    private let cacheFile = URL.cachesDirectory.appending(path: "tmdb-posters.json")

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        session = URLSession(configuration: config)
        paths = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: cacheFile))) ?? [:]
    }

    func setKey(_ key: String?) {
        let k = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = (k?.isEmpty ?? true) ? nil : k
        backoffUntil = nil
    }

    var isEnabled: Bool { key != nil }

    /// Image URL for a poster at roughly `maxWidth` pixels; nil width asks for the original.
    func posterURL(tmdbID: String, maxWidth: Int?) async -> URL? {
        guard let path = await posterPath(tmdbID) else { return nil }
        let size = switch maxWidth {
        case .some(let w) where w <= 92: "w92"
        case .some(let w) where w <= 342: "w342"
        case .some(let w) where w <= 500: "w500"
        case .some(let w) where w <= 780: "w780"
        default: "original"
        }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    /// Checks a key against /configuration. Returns nil on success, otherwise a message.
    func validate(_ key: String) async -> String? {
        guard var req = request("configuration", key: key) else { return "Invalid key" }
        req.timeoutInterval = 8
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return code == 200 ? nil : code == 401 ? "Key rejected by TMDB" : "HTTP \(code)"
        } catch {
            return "TMDB unreachable"
        }
    }

    // MARK: Lookup

    private func posterPath(_ id: String) async -> String? {
        if let cached = paths[id] { return cached.isEmpty ? nil : cached }
        guard key != nil else { return nil }
        if let until = backoffUntil, until > .now { return nil }
        if let running = inflight[id] { return await running.value }
        let task = Task { await fetch(id) }
        inflight[id] = task
        defer { inflight[id] = nil }
        return await task.value
    }

    private func fetch(_ id: String) async -> String? {
        guard let req = request("movie/\(id)/images", query: ["include_image_language": "zh,en,null"]) else { return nil }
        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let posters = try JSONDecoder().decode(Images.self, from: data).posters
            let best = posters.min { rank($0) < rank($1) }?.file_path ?? ""
            paths[id] = best
            persist()
            return best.isEmpty ? nil : best
        } catch {
            backoffUntil = .now.addingTimeInterval(300)
            return nil
        }
    }

    /// Big first (≥1500px wide), then Chinese, English, textless; then popularity, then size.
    private func rank(_ p: Images.Poster) -> (Int, Int, Int, Int) {
        let lang = switch p.iso_639_1 {
        case "zh": 0
        case "en": 1
        case nil: 2
        default: 3
        }
        return (p.width >= 1500 ? 0 : 1, lang, -p.vote_count, -p.width)
    }

    private func persist() {
        try? JSONEncoder().encode(paths).write(to: cacheFile, options: .atomic)
    }

    /// v4 read-access tokens (JWT, "eyJ…") go in the header; v3 keys go in the query.
    private func request(_ path: String, query: [String: String] = [:], key: String? = nil) -> URLRequest? {
        guard let key = key ?? self.key,
              var c = URLComponents(string: "https://api.themoviedb.org/3/\(path)") else { return nil }
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        let bearer = key.hasPrefix("eyJ")
        if !bearer { items.append(URLQueryItem(name: "api_key", value: key)) }
        c.queryItems = items.isEmpty ? nil : items
        guard let url = c.url else { return nil }
        var req = URLRequest(url: url)
        if bearer { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private nonisolated struct Images: Decodable {
        nonisolated struct Poster: Decodable {
            let file_path: String
            let width: Int
            let iso_639_1: String?
            let vote_count: Int
        }
        let posters: [Poster]
    }
}
