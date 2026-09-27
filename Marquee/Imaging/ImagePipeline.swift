import UIKit

/// Fetches, decodes and caches remote images. URLs carry Emby's image tag, so cached bytes never go stale.
actor ImagePipeline {
    static let shared = ImagePipeline()

    nonisolated(unsafe) private let memory = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage, Error>] = [:]
    private let session: URLSession

    init() {
        memory.totalCostLimit = 320 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 2 * 1024 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)
    }

    nonisolated func cached(_ url: URL) -> UIImage? {
        // NSCache is thread-safe; reading it synchronously lets views skip the placeholder on re-appear.
        memory.object(forKey: url as NSURL)
    }

    func image(_ url: URL) async throws -> UIImage {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let running = inflight[url] { return try await running.value }
        let session = session
        let task = Task.detached(priority: .userInitiated) { () throws -> UIImage in
            let (data, resp) = try await session.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { throw URLError(.badServerResponse) }
            guard let img = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            return await img.byPreparingForDisplay() ?? img
        }
        inflight[url] = task
        defer { inflight[url] = nil }
        let img = try await task.value
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        memory.setObject(img, forKey: url as NSURL, cost: cost)
        return img
    }
}
