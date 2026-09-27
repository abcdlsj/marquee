import CryptoKit
import UIKit

/// Fetches, decodes and caches remote images in memory and on disk (Caches/images).
/// Image URLs carry a content tag, so a cached file never goes stale; the auth token is
/// stripped from the cache key so re-login doesn't orphan the cache.
actor ImagePipeline {
    static let shared = ImagePipeline()

    nonisolated(unsafe) private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage, Error>] = [:]
    private let session: URLSession
    private let directory = URL.cachesDirectory.appending(path: "images", directoryHint: .isDirectory)
    private static let diskLimit: Int64 = 1_500_000_000

    init() {
        memory.totalCostLimit = 320 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dir = directory
        Task.detached(priority: .background) { Self.trim(dir) }
    }

    /// Memory or disk only; never touches the network.
    func cachedImage(_ url: URL) async -> UIImage? {
        let key = Self.key(url)
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let file = directory.appending(path: key)
        guard let img = await Task.detached(priority: .userInitiated, operation: { Self.decode(file) }).value else { return nil }
        remember(img, key)
        return img
    }

    func image(_ url: URL) async throws -> UIImage {
        if let hit = await cachedImage(url) { return hit }
        let key = Self.key(url)
        if let running = inflight[key] { return try await running.value }
        let session = session
        let file = directory.appending(path: key)
        let task = Task.detached(priority: .userInitiated) { () throws -> UIImage in
            let (data, resp) = try await session.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { throw URLError(.badServerResponse) }
            guard let img = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            try? data.write(to: file, options: .atomic)
            return await img.byPreparingForDisplay() ?? img
        }
        inflight[key] = task
        defer { inflight[key] = nil }
        let img = try await task.value
        remember(img, key)
        return img
    }

    private func remember(_ img: UIImage, _ key: String) {
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        memory.setObject(img, forKey: key as NSString, cost: cost)
    }

    private static func key(_ url: URL) -> String {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let kept = c?.queryItems?.filter { $0.name != "api_key" }
        c?.queryItems = kept
        let s = c?.string ?? url.absoluteString
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func decode(_ file: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: file), let img = UIImage(data: data) else { return nil }
        return img.preparingForDisplay() ?? img
    }

    /// Keeps the disk cache under its limit by dropping the least recently modified files.
    private nonisolated static func trim(_ dir: URL) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        let entries = files.compactMap { f -> (URL, Int64, Date)? in
            guard let v = try? f.resourceValues(forKeys: Set(keys)) else { return nil }
            return (f, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > diskLimit else { return }
        for (f, size, _) in entries.sorted(by: { $0.2 < $1.2 }) {
            try? FileManager.default.removeItem(at: f)
            total -= size
            if total <= diskLimit * 8 / 10 { break }
        }
    }
}
