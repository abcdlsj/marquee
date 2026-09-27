import Foundation
import Observation

@Observable
final class AppModel {
    enum Phase: Equatable { case idle, connecting, ready, failed(String) }

    private(set) var servers: [ServerConfig] = []
    private(set) var activeID: UUID?
    private(set) var client: EmbyClient?
    private(set) var phase: Phase = .idle

    private(set) var favorites: [Movie] = []
    private(set) var played: [Movie] = []
    private(set) var latest: [Movie] = []
    /// Detail-level copies (People, Taglines, …) keyed by id.
    private(set) var details: [String: Movie] = [:]

    var active: ServerConfig? { servers.first { $0.id == activeID } }

    init() {
        servers = ServerStore.load()
        if servers.isEmpty, let seed = ServerStore.seed {
            servers = [seed]
            ServerStore.save(servers)
        }
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
        if let v = try? await f { favorites = v }
        if let v = try? await p { played = v }
        if let v = try? await l { latest = v }
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
        favorites = []; played = []; latest = []; details = [:]
        Task { await connect() }
    }

    // MARK: Movies

    func current(_ movie: Movie) -> Movie {
        details[movie.id] ?? favorites.first { $0.id == movie.id } ?? played.first { $0.id == movie.id } ?? movie
    }

    func loadDetail(_ movie: Movie) async {
        guard let client, let full = try? await client.movie(movie.id) else { return }
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
        played.removeAll { $0.id == m.id }
        if ud.played {
            played.append(base)
            played.sort { ($0.playedDate ?? .distantPast) > ($1.playedDate ?? .distantPast) }
        }
        if let i = latest.firstIndex(where: { $0.id == m.id }) { latest[i].userData = ud }
    }
}
