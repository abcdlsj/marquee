import SwiftUI

/// Emby artwork that fills its frame. Measures itself, requests exactly the pixel width it
/// needs (snapped to a few buckets so caches hit), shows a blurred 48px preview first,
/// then fades the full-resolution image in.
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

    private var fullURL: URL? {
        guard width > 0 else { return nil }
        return model.client?.imageURL(movie, kind, maxWidth: pixelWidth, quality: original ? 100 : 92)
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
            .task(id: fullURL) { await load() }
    }

    private func load() async {
        guard let url = fullURL else { return }
        if loadedFor != movie.id + kind.rawValue {
            // Same view reused for a different movie: drop the stale artwork. A mere size bucket change keeps it.
            full = nil
            preview = nil
            loadedFor = movie.id + kind.rawValue
        }
        if let hit = ImagePipeline.shared.cached(url) {
            full = hit
            onLoad?(hit)
            return
        }
        if kind != .logo, preview == nil, let small = model.client?.imageURL(movie, kind, maxWidth: 48, quality: 60) {
            preview = ImagePipeline.shared.cached(small)
            if preview == nil { preview = try? await ImagePipeline.shared.image(small) }
        }
        guard let img = try? await ImagePipeline.shared.image(url), !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.45)) { full = img }
        onLoad?(img)
    }
}

extension AppModel {
    func image(_ movie: Movie, _ kind: ImageKind, maxWidth: Int?) async -> UIImage? {
        guard let url = client?.imageURL(movie, kind, maxWidth: maxWidth, quality: maxWidth == nil ? 100 : 92) else { return nil }
        return try? await ImagePipeline.shared.image(url)
    }
}
