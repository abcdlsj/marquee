import SwiftUI

/// Emby artwork that fills its frame. Measures itself, requests exactly the pixel width it
/// needs (snapped to a few buckets so caches hit). Cached artwork appears at once; otherwise a
/// blurred 48px preview shows first and the full-resolution image fades in.
struct RemoteImage: View {
    let movie: Movie
    var kind: ImageKind = .primary
    var contentMode: ContentMode = .fill
    /// Ask for the untouched original upload regardless of on-screen size.
    var original = false
    /// Background use (blurred): a small fixed size is plenty.
    var lowRes = false
    var onLoad: ((UIImage) -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var scale
    @State private var width: CGFloat = 0
    @State private var preview: UIImage?
    @State private var full: UIImage?
    @State private var loadedFor: String?

    private static let buckets = [160, 320, 480, 720, 1080, 1440, 2160]

    private var pixelWidth: Int? {
        guard !original else { return nil }
        if lowRes { return 320 }
        let need = Int(width * scale)
        return Self.buckets.first { $0 >= need } ?? Self.buckets.last!
    }

    private struct LoadKey: Equatable {
        let movie: String
        let kind: ImageKind
        let pixelWidth: Int?
        let tmdb: String
    }

    private var loadKey: LoadKey? {
        guard width > 0 else { return nil }
        return LoadKey(movie: movie.id, kind: kind, pixelWidth: pixelWidth, tmdb: model.tmdbKey)
    }

    var body: some View {
        Color.clear
            .overlay {
                ZStack {
                    if full == nil {
                        if let preview {
                            Image(uiImage: preview).resizable().aspectRatio(contentMode: contentMode)
                                .blur(radius: 14, opaque: true)
                        } else if kind != .logo {
                            Rectangle().fill(.white.opacity(0.04))
                        }
                    }
                    if let full {
                        Image(uiImage: full).resizable().interpolation(.high).aspectRatio(contentMode: contentMode)
                            .transition(.opacity.animation(.easeOut(duration: 0.45)))
                    }
                }
            }
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: loadKey) { await load() }
    }

    private func load() async {
        guard loadKey != nil else { return }
        if loadedFor != movie.id + kind.rawValue {
            // Same view reused for a different movie: drop the stale artwork. A mere size bucket change keeps it.
            full = nil
            preview = nil
            loadedFor = movie.id + kind.rawValue
        }
        if full == nil, let hit = await model.cachedImage(movie, kind, maxWidth: pixelWidth) {
            // Cached: show it outright, no blur-up.
            full = hit
            onLoad?(hit)
            return
        }
        if kind != .logo, preview == nil, full == nil {
            preview = await model.image(movie, kind, maxWidth: 48)
        }
        guard let img = await model.image(movie, kind, maxWidth: pixelWidth), !Task.isCancelled else { return }
        if full == nil {
            withAnimation(.easeOut(duration: 0.45)) { full = img }
        } else {
            full = img
        }
        onLoad?(img)
    }
}

extension AppModel {
    /// Candidate URLs, best first: the TMDB poster (when a key is set and the movie has a TMDB id), then Emby.
    private func artworkURLs(_ movie: Movie, _ kind: ImageKind, maxWidth: Int?, lookup: Bool) async -> [URL] {
        var urls: [URL] = []
        if kind == .primary, !tmdbKey.isEmpty, let id = movie.tmdbID,
           let url = await TMDB.shared.posterURL(tmdbID: id, maxWidth: maxWidth, lookup: lookup) {
            urls.append(url)
        }
        let quality = maxWidth == nil ? 100 : (maxWidth! <= 48 ? 60 : 92)
        if let url = client?.imageURL(movie, kind, maxWidth: maxWidth, quality: quality) { urls.append(url) }
        return urls
    }

    /// Loads artwork, falling back from TMDB to Emby on any failure.
    func image(_ movie: Movie, _ kind: ImageKind, maxWidth: Int?) async -> UIImage? {
        for url in await artworkURLs(movie, kind, maxWidth: maxWidth, lookup: true) {
            if let img = try? await ImagePipeline.shared.image(url) { return img }
        }
        return nil
    }

    /// Artwork already in the memory or disk cache; never hits the network.
    func cachedImage(_ movie: Movie, _ kind: ImageKind, maxWidth: Int?) async -> UIImage? {
        for url in await artworkURLs(movie, kind, maxWidth: maxWidth, lookup: false) {
            if let img = await ImagePipeline.shared.cachedImage(url) { return img }
        }
        return nil
    }
}
