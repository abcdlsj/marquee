import SwiftUI

/// The collection as a gallery: one poster at a time, as large as the room allows,
/// lit only by a blurred echo of itself. A wall mode shows two abreast.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("home.wall") private var wall = false
    @State private var focusedID: String?
    @State private var showSettings = false
    @State private var size: CGSize = .zero

    private var favorites: [Movie] { model.favorites }
    private var focused: Movie? { favorites.first { $0.id == focusedID } ?? favorites.first }

    var body: some View {
        CinemaStack {
            VStack(spacing: 0) {
                topBar
                if favorites.isEmpty {
                    Spacer()
                    Text("暂无收藏").caption(13)
                    Spacer()
                } else if wall {
                    PosterWall(movies: favorites)
                } else {
                    gallery
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .background { PosterAura(movie: wall ? nil : focused) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("收藏").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.fg)
            Text("\(favorites.count)").font(.system(size: 17, weight: .regular)).monospacedDigit().foregroundStyle(Theme.tertiary)
            Spacer()
            Button {
                withAnimation(.smooth(duration: 0.4)) { wall.toggle() }
            } label: {
                Image(systemName: wall ? "rectangle.portrait" : "square.grid.2x2")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
            }
            Button { showSettings = true } label: {
                Image(systemName: "ellipsis").frame(width: 36, height: 36)
            }
        }
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(Theme.secondary)
        .buttonStyle(.plain)
        .padding(.leading, 24)
        .padding(.trailing, 14)
        .padding(.top, 4)
    }

    // MARK: Gallery

    /// As large as fits between the top bar and the caption, capped by the side margins.
    private var posterWidth: CGFloat {
        guard size.height > 0 else { return 300 }
        return min(size.width - 48, (size.height - 44 - 150) / 1.5).rounded()
    }

    private var gallery: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(favorites) { movie in
                        GalleryPiece(movie: movie, width: posterWidth, isFocused: movie.id == focused?.id)
                            .frame(width: size.width)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(1 - abs(phase.value) * 0.1)
                                    .rotation3DEffect(.degrees(phase.value * -10), axis: (0, 1, 0), perspective: 0.4)
                                    .opacity(1 - abs(phase.value) * 0.9)
                            }
                            .id(movie.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $focusedID)
            .scrollIndicators(.hidden)
            .frame(height: posterWidth * 1.5 + 40)
            .sensoryFeedback(.selection, trigger: focusedID)

            caption
                .frame(height: 72, alignment: .top)
                .padding(.top, 14)
            Spacer(minLength: 0)
        }
    }

    private var caption: some View {
        VStack(spacing: 6) {
            if let m = focused {
                Text(m.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                Text([m.year.map(String.init), m.runtimeMinutes.map { "\($0) 分钟" }].compactMap { $0 }.joined(separator: "  ·  "))
                    .caption(12, Theme.secondary)
                Text(String(format: "%d / %d", (favorites.firstIndex(of: m) ?? 0) + 1, favorites.count))
                    .caption(10.5)
                    .monospacedDigit()
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 40)
        .contentTransition(.opacity)
        .animation(.smooth(duration: 0.3), value: focused?.id)
    }
}

/// One framed piece. The focused one answers device tilt with a slight turn and a moving glint.
private struct GalleryPiece: View {
    let movie: Movie
    let width: CGFloat
    let isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = Motion.shared

    private var tilt: CGSize { isFocused && !reduceMotion ? motion.tilt : .zero }

    var body: some View {
        MovieLink(movie: movie, source: "gallery-\(movie.id)") {
            RemoteImage(movie: movie)
                .frame(width: width, height: width * 1.5)
                .sheen(tilt: tilt, strength: 0.35)
                .clipShape(.rect(cornerRadius: 4))
        }
        .rotation3DEffect(.degrees(tilt.height * 4), axis: (1, 0, 0), perspective: 0.4)
        .rotation3DEffect(.degrees(tilt.width * -5), axis: (0, 1, 0), perspective: 0.4)
        .shadow(color: .black.opacity(0.7), radius: 30, x: -tilt.width * 10, y: 24 - tilt.height * 6)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }
}

private struct PosterWall: View {
    let movies: [Movie]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(movies) { movie in
                    MovieLink(movie: movie, source: "wall-\(movie.id)") {
                        Poster(movie: movie)
                    }
                    .scrollTransition(.animated(.smooth(duration: 0.5))) { content, phase in
                        content.opacity(phase.isIdentity ? 1 : 0.3).scaleEffect(phase.isIdentity ? 1 : 0.95)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }
}
