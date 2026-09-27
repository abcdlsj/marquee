import Foundation
import Security

nonisolated struct ServerConfig: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var url: String
    var username: String
    var password: String
    var userID: String?
    var token: String?

    var host: String { URL(string: url)?.host() ?? url }
}

/// Server list (credentials included) lives in the Keychain as one JSON blob.
enum ServerStore {
    private static let service = "com.abcdlsj.marquee"
    private static let account = "servers"
    private static let activeKey = "marquee.activeServer"

    static func load() -> [ServerConfig] {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return [] }
        return (try? JSONDecoder().decode([ServerConfig].self, from: data)) ?? []
    }

    static func save(_ servers: [ServerConfig]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(q as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(q.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    static var activeID: UUID? {
        get { UserDefaults.standard.string(forKey: activeKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: activeKey) }
    }

    /// Build-time seed injected by scripts/install-ios.sh from ~/.ember/servers.json.
    static var seed: ServerConfig? {
        let info = Bundle.main.infoDictionary ?? [:]
        func v(_ k: String) -> String { (info[k] as? String ?? "").trimmingCharacters(in: .whitespaces) }
        guard !v("MarqueeSeedURL").isEmpty, !v("MarqueeSeedUser").isEmpty else { return nil }
        return ServerConfig(
            name: v("MarqueeSeedName").isEmpty ? "Emby" : v("MarqueeSeedName"),
            url: v("MarqueeSeedURL"),
            username: v("MarqueeSeedUser"),
            password: v("MarqueeSeedPassword")
        )
    }
}
