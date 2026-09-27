import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [Movie] = []
    @State private var searched = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 2)
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        CinemaStack {
            ScrollView {
                if trimmed.isEmpty {
                    grid(model.latest, prefix: "latest")
                } else if results.isEmpty && searched == trimmed {
                    Text("无结果").caption(13).padding(.top, 120)
                } else {
                    grid(results, prefix: "search")
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .background(Color.black)
            .navigationTitle(trimmed.isEmpty ? "最新入库" : "搜索")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "片名")
            .task(id: trimmed) { await search() }
        }
    }

    private func grid(_ movies: [Movie], prefix: String) -> some View {
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(movies) { movie in
                MovieLink(movie: movie, source: "\(prefix)-\(movie.id)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Poster(movie: movie)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(movie.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                            if let y = movie.year { Text(String(y)).caption(11) }
                        }
                    }
                }
                .scrollTransition(.animated(.smooth)) { c, phase in
                    c.opacity(phase.isIdentity ? 1 : 0.3).scaleEffect(phase.isIdentity ? 1 : 0.96)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.smooth, value: movies.map(\.id))
    }

    private func search() async {
        let term = trimmed
        guard !term.isEmpty, let client = model.client else { results = []; return }
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }
        if let found = try? await client.search(term), !Task.isCancelled {
            results = found
            searched = term
        }
    }
}
