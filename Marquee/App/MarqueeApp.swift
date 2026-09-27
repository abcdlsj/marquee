import SwiftUI

@main
struct MarqueeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.fg)
                .task { await model.connect() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .collection

    enum AppTab: Hashable { case collection, year, search }

    var body: some View {
        switch model.phase {
        case .ready:
            TabView(selection: $tab) {
                Tab("Collection", systemImage: "rectangle.portrait.on.rectangle.portrait", value: .collection) {
                    HomeView()
                }
                Tab("Year", systemImage: "square.grid.3x3", value: .year) {
                    YearView()
                }
                Tab(value: .search, role: .search) {
                    SearchView()
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        case .idle where model.servers.isEmpty:
            WelcomeView()
        default:
            SplashView(phase: model.phase)
        }
    }
}

/// Route into a movie detail; `source` pairs the zoom transition with the tapped artwork.
struct MovieRoute: Hashable {
    let movie: Movie
    let source: String
}

extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID?
}

/// A NavigationStack whose pushes zoom out of the tapped poster.
struct CinemaStack<Content: View>: View {
    @ViewBuilder var content: Content
    @Namespace private var ns

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: MovieRoute.self) { route in
                    MovieDetailView(movie: route.movie)
                        .navigationTransition(.zoom(sourceID: route.source, in: ns))
                }
        }
        .environment(\.zoomNamespace, ns)
    }
}

/// Wraps artwork in a navigation link that serves as the zoom source.
struct MovieLink<Label: View>: View {
    let movie: Movie
    let source: String
    var cornerRadius: CGFloat = 4
    @ViewBuilder var label: Label

    @Environment(\.zoomNamespace) private var ns
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink(value: MovieRoute(movie: movie, source: source)) {
            if let ns {
                label.matchedTransitionSource(id: source, in: ns) { $0.clipShape(.rect(cornerRadius: cornerRadius)) }
            } else {
                label
            }
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            let m = model.current(movie)
            Button(m.isFavorite ? "Unfavorite" : "Favorite", systemImage: m.isFavorite ? "heart.slash" : "heart") {
                Task { await model.toggleFavorite(m) }
            }
            Button(m.isPlayed ? "Mark Unwatched" : "Watched Today", systemImage: m.isPlayed ? "eye.slash" : "checkmark") {
                Task { await model.setPlayed(m, at: m.isPlayed ? nil : .now) }
            }
        } preview: {
            RemoteImage(movie: movie)
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(width: 320)
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: configuration.isPressed)
    }
}

/// A poster at rest: near-square corners, hairline edge, no ornament.
struct Poster: View {
    let movie: Movie
    var cornerRadius: CGFloat = 4

    var body: some View {
        RemoteImage(movie: movie)
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
    }
}
