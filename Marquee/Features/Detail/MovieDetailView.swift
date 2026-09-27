import SwiftUI

/// The poster, edge to edge, is the whole first screen. Everything else waits below the fold.
struct MovieDetailView: View {
    let movie: Movie

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = Motion.shared
    @State private var width: CGFloat = 400
    @State private var showPoster = false
    @State private var showShare = false
    @State private var pickDate = false
    @State private var confirmUnwatch = false
    @State private var watchedPulse = 0

    private var m: Movie { model.current(movie) }
    private var tilt: CGSize { reduceMotion ? .zero : motion.tilt }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                plate
                info
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
            }
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .background { PosterAura(movie: movie, intensity: 0.35) }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .ignoresSafeArea(edges: .top)
        .toolbar { toolbar }
        .task { await model.loadDetail(movie) }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .fullScreenCover(isPresented: $showPoster) { PosterViewer(movie: m) }
        .fullScreenCover(isPresented: $showShare) { ShareStudio(movie: m) }
        .sheet(isPresented: $pickDate) { WatchDateSheet(movie: m).presentationDetents([.medium]) }
        .confirmationDialog("看过于 \(m.playedDate?.dotted ?? "")", isPresented: $confirmUnwatch, titleVisibility: .visible) {
            Button("修改日期") { pickDate = true }
            Button("标记为未看", role: .destructive) { Task { await model.setPlayed(m, at: nil) } }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: m.isFavorite)
        .sensoryFeedback(.success, trigger: watchedPulse)
    }

    // MARK: Plate — the poster itself

    private var plate: some View {
        RemoteImage(movie: m)
            .frame(width: width, height: width * 1.5)
            .sheen(tilt: tilt, strength: 0.25)
            .offset(x: -tilt.width * 6, y: -tilt.height * 6)
            .scaleEffect(1.03)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
            }
            .contentShape(.rect)
            .onTapGesture { showPoster = true }
            // Stretch on overscroll; drift at half speed on scroll-up.
            .visualEffect { content, proxy in
                let y = proxy.frame(in: .scrollView).minY
                return content
                    .scaleEffect(y > 0 ? 1 + y / 600 : 1, anchor: .bottom)
                    .offset(y: y > 0 ? -y / 2 : -y * 0.4)
            }
    }

    // MARK: Info

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(m.name)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.fg)
            if let o = m.originalTitle, o != m.name {
                Text(o).caption(13, Theme.secondary).padding(.top, 4)
            }
            Text(meta).caption(12, Theme.secondary).padding(.top, 10)

            if let overview = m.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 14.5))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.fg.opacity(0.78))
                    .padding(.top, 24)
            }

            VStack(alignment: .leading, spacing: 8) {
                credit("导演", m.directors.prefix(2))
                credit("主演", m.cast.prefix(4))
            }
            .padding(.top, 24)
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let y = m.year { parts.append(String(y)) }
        if let r = m.runtimeMinutes { parts.append("\(r) 分钟") }
        if let g = m.genres?.first { parts.append(g) }
        if let c = m.communityRating { parts.append(String(format: "%.1f", c)) }
        if let d = m.playedDate { parts.append("看过于 \(d.dotted)") }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private func credit(_ label: String, _ names: ArraySlice<String>) -> some View {
        if !names.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(label).caption(11)
                Text(names.joined(separator: "  ")).caption(12, Theme.secondary)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("收藏", systemImage: m.isFavorite ? "heart.fill" : "heart") {
                Task { await model.toggleFavorite(m) }
            }
            .tint(m.isFavorite ? Theme.cool : Theme.fg)

            Button("看过", systemImage: m.isPlayed ? "checkmark.circle.fill" : "checkmark.circle") {
                if m.isPlayed { confirmUnwatch = true } else {
                    watchedPulse += 1
                    Task { await model.setPlayed(m, at: .now) }
                }
            }
            .tint(m.isPlayed ? Theme.cool : Theme.fg)
            .contextMenu {
                Button("选择日期", systemImage: "calendar") { pickDate = true }
            }

            Button("分享", systemImage: "square.and.arrow.up") { showShare = true }
        }
    }
}

struct WatchDateSheet: View {
    let movie: Movie
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            DatePicker("观看日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .navigationTitle("观看日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成", systemImage: "checkmark") {
                            Task { await model.setPlayed(movie, at: date) }
                            dismiss()
                        }
                    }
                }
        }
        .tint(Theme.cool)
        .onAppear { date = movie.playedDate ?? .now }
    }
}
