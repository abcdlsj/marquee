import Foundation
import Observation

@Observable
final class AppModel {
    enum Phase: Equatable { case idle, connecting, ready, failed(String) }

    private(set) var servers: [ServerConfig] = []
    private(set) var activeID: UUID?
    private(set) var client: EmbyClient?
    private(set) var phase: Phase = .idle

    /// Unwatched first, then watched; each keeps the server's order.
    private(set) var favorites: [Movie] = []
    /// Played episodes, series info filled in.
    private(set) var episodes: [Movie] = []
    private(set) var played: [Movie] = []
    private(set) var latest: [Movie] = []
    /// Detail-level copies (People, Taglines, …) keyed by id.
    private(set) var details: [String: Movie] = [:]

    var active: ServerConfig? { servers.first { $0.id == activeID } }

    /// TMDB key (v3 key or v4 read token). Empty disables TMDB posters.
    var tmdbKey: String = ServerStore.tmdbKey {
        didSet {
            ServerStore.tmdbKey = tmdbKey
            let k = tmdbKey
            Task { await TMDB.shared.setKey(k) }
        }
    }

    init() {
        servers = ServerStore.load()
        if servers.isEmpty, let seed = ServerStore.seed {
            servers = [seed]
            ServerStore.save(servers)
        }
        let k = tmdbKey
        Task { await TMDB.shared.setKey(k) }
        activeID = ServerStore.activeID.flatMap { id in servers.contains { $0.id == id } ? id : nil } ?? servers.first?.id
    }

    // MARK: Connection

    func connect() async {
        guard var server = active else { phase = .idle; return }
        guard let base = EmbyClient.normalize(server.url) else { phase = .failed(EmbyError.badURL.localizedDescription); return }
        phase = .connecting
        if let token = server.token, let uid = server.userID {
            let c = EmbyClient(baseURL: base, userID: uid, token: token)
            if (try? await c.favorites()) != nil {
                client = c
                phase = .ready
                await refresh()
                return
            }
        }
        do {
            let auth = try await EmbyClient.login(server: server.url, username: server.username, password: server.password)
            server.userID = auth.userID
            server.token = auth.token
            upsert(server)
            client = EmbyClient(baseURL: base, userID: auth.userID, token: auth.token)
            phase = .ready
            await refresh()
        } catch {
            client = nil
            phase = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        guard let client else { return }
        async let f = client.favorites()
        async let p = client.played()
        async let l = client.latest()
        async let e = client.playedEpisodes()
        if let v = try? await f { favorites = Self.unwatchedFirst(v) }
        if let v = try? await p { played = v }
        if let v = try? await l { latest = v }
        if let v = try? await e { episodes = await enrich(v, using: client) }
    }

    private static func unwatchedFirst(_ list: [Movie]) -> [Movie] {
        list.filter { !$0.isPlayed } + list.filter(\.isPlayed)
    }

    /// List responses from some servers drop SeriesId/SeriesName/season, so each episode is looked
    /// up once and the result cached on disk (an episode's series never changes).
    private func enrich(_ list: [Movie], using client: EmbyClient) async -> [Movie] {
        var cache = EpisodeCache.load()
        let missing = list.filter { $0.seriesId == nil && cache[$0.id] == nil }.map(\.id)
        if !missing.isEmpty {
            await withTaskGroup(of: (String, Movie?).self) { group in
                var next = missing.makeIterator()
                for _ in 0..<6 { if let id = next.next() { group.addTask { (id, try? await client.movie(id)) } } }
                for await (id, full) in group {
                    if let full {
                        cache[id] = EpisodeCache.Entry(seriesId: full.seriesId, seriesName: full.seriesName,
                                                       seriesTag: full.seriesPrimaryImageTag,
                                                       season: full.parentIndexNumber, number: full.indexNumber)
                    }
                    if let id = next.next() { group.addTask { (id, try? await client.movie(id)) } }
                }
            }
            EpisodeCache.save(cache)
        }
        return list.map { ep in
            guard ep.seriesId == nil, let c = cache[ep.id] else { return ep }
            var e = ep
            e.seriesId = c.seriesId
            e.seriesName = c.seriesName
            e.seriesPrimaryImageTag = c.seriesTag
            e.parentIndexNumber = c.season
            e.indexNumber = c.number ?? ep.indexNumber
            return e
        }
    }

    // MARK: Servers

    func upsert(_ server: ServerConfig) {
        if let i = servers.firstIndex(where: { $0.id == server.id }) { servers[i] = server } else { servers.append(server) }
        ServerStore.save(servers)
    }

    func remove(_ server: ServerConfig) {
        servers.removeAll { $0.id == server.id }
        ServerStore.save(servers)
        if activeID == server.id { activate(servers.first) }
    }

    func activate(_ server: ServerConfig?) {
        activeID = server?.id
        ServerStore.activeID = activeID
        client = nil
        favorites = []; played = []; latest = []; episodes = []; details = [:]
        Task { await connect() }
    }

    // MARK: Movies

    func current(_ movie: Movie) -> Movie {
        details[movie.id] ?? favorites.first { $0.id == movie.id } ?? played.first { $0.id == movie.id } ?? movie
    }

    func loadDetail(_ movie: Movie) async {
        guard details[movie.id] == nil, let client, let full = try? await client.movie(movie.id) else { return }
        details[movie.id] = full
    }

    func toggleFavorite(_ movie: Movie) async {
        guard let client else { return }
        let target = !current(movie).isFavorite
        apply(movie) { $0.isFavorite = target }
        if let ud = try? await client.setFavorite(movie.id, target) { apply(movie) { $0 = ud } }
        else { apply(movie) { $0.isFavorite = !target } }
    }

    func setPlayed(_ movie: Movie, at date: Date?) async {
        guard let client else { return }
        let before = current(movie).userData
        apply(movie) {
            $0.played = date != nil
            $0.lastPlayedDate = date.map { $0.formatted(.iso8601) }
        }
        if let ud = try? await client.setPlayed(movie.id, at: date) {
            apply(movie) { $0 = ud }
        } else if let before {
            apply(movie) { $0 = before }
        }
    }

    /// Updates every cached copy of a movie and keeps the favorites/played lists in sync.
    private func apply(_ movie: Movie, _ change: (inout UserData) -> Void) {
        var m = current(movie)
        var ud = m.userData ?? UserData(played: false, isFavorite: false)
        change(&ud)
        m.userData = ud
        if details[m.id] != nil { details[m.id] = m }

        let listCopy = { (m: Movie) -> Movie in
            var c = self.favorites.first { $0.id == m.id } ?? self.played.first { $0.id == m.id } ?? m
            c.userData = ud
            return c
        }
        let base = listCopy(m)
        if let i = favorites.firstIndex(where: { $0.id == m.id }) {
            if ud.isFavorite { favorites[i] = base } else { favorites.remove(at: i) }
        } else if ud.isFavorite {
            favorites.insert(base, at: 0)
        }
        favorites = Self.unwatchedFirst(favorites)
        played.removeAll { $0.id == m.id }
        if ud.played {
            played.append(base)
            played.sort { ($0.playedDate ?? .distantPast) > ($1.playedDate ?? .distantPast) }
        }
        if let i = latest.firstIndex(where: { $0.id == m.id }) { latest[i].userData = ud }
    }
}

/// episode id → series info, persisted in Caches.
nonisolated enum EpisodeCache {
    struct Entry: Codable, Sendable {
        var seriesId: String?
        var seriesName: String?
        var seriesTag: String?
        var season: Int?
        var number: Int?
    }

    private static var file: URL { .cachesDirectory.appending(path: "episode-series.json") }

    static func load() -> [String: Entry] {
        (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: file))) ?? [:]
    }

    static func save(_ cache: [String: Entry]) {
        try? JSONEncoder().encode(cache).write(to: file, options: .atomic)
    }
}
