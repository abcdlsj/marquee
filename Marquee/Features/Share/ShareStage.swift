import SwiftUI

/// Canvas is designed at 360 × 640 pt and exported at 3× (1080 × 1920 px).
enum ShareCanvas {
    static let size = CGSize(width: 360, height: 640)
    static let exportScale: CGFloat = 3
}

/// Full-screen studio: swipe between templates, then share or save the rendered 1080×1920 image.
struct ShareStage<Canvas: View>: View {
    let titles: [String]
    let ready: Bool
    let exportName: String
    @ViewBuilder let canvas: (Int) -> Canvas

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var rendered: UIImage?
    @State private var savedPulse = 0
    @State private var saved = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 36, height: 36)
                }
                Spacer()
                Button { save() } label: {
                    Image(systemName: saved ? "checkmark" : "arrow.down.to.line")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                }
                .disabled(rendered == nil)
                if let rendered {
                    let image = Image(uiImage: rendered)
                    ShareLink(item: image, preview: SharePreview(exportName, image: image)) {
                        Image(systemName: "square.and.arrow.up").frame(width: 36, height: 36)
                    }
                }
            }
            .font(.system(size: 16))
            .foregroundStyle(Theme.fg)
            .buttonStyle(.plain)
            .padding(.horizontal, 14)

            stage

            HStack(spacing: 22) {
                ForEach(titles.indices, id: \.self) { i in
                    Button { withAnimation(.smooth) { page = i } } label: {
                        Text(titles[i])
                            .font(.system(size: 13, weight: page == i ? .semibold : .regular))
                            .foregroundStyle(page == i ? Theme.fg : Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .task(id: RenderKey(page: page, ready: ready)) { render() }
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.success, trigger: savedPulse)
    }

    private struct RenderKey: Equatable { let page: Int; let ready: Bool }

    private var stage: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / ShareCanvas.size.width, geo.size.height / ShareCanvas.size.height) * 0.9
            let stageMidX = geo.frame(in: .global).midX
            let stageWidth = geo.size.width
            TabView(selection: $page) {
                ForEach(titles.indices, id: \.self) { i in
                    Group {
                        if ready {
                            canvas(i)
                                .frame(width: ShareCanvas.size.width, height: ShareCanvas.size.height)
                                .scaleEffect(s)
                                .frame(width: ShareCanvas.size.width * s, height: ShareCanvas.size.height * s)
                        } else {
                            Rectangle().fill(.white.opacity(0.04))
                                .frame(width: ShareCanvas.size.width * s, height: ShareCanvas.size.height * s)
                                .overlay { ProgressView() }
                        }
                    }
                    .overlay { Rectangle().strokeBorder(Theme.hairline, lineWidth: 0.5) }
                    .visualEffect { content, proxy in
                        let v = (proxy.frame(in: .global).midX - stageMidX) / stageWidth
                        return content
                            .scaleEffect(1 - abs(v) * 0.1)
                            .opacity(1 - abs(v) * 0.7)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func render() {
        guard ready else { return }
        saved = false
        let r = ImageRenderer(content:
            canvas(page)
                .frame(width: ShareCanvas.size.width, height: ShareCanvas.size.height)
                .environment(\.colorScheme, .dark)
        )
        r.scale = ShareCanvas.exportScale
        r.isOpaque = true
        rendered = r.uiImage
    }

    private func save() {
        guard let rendered else { return }
        UIImageWriteToSavedPhotosAlbum(rendered, nil, nil, nil)
        savedPulse += 1
        withAnimation { saved = true }
    }
}
