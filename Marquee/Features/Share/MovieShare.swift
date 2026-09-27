import SwiftUI

struct ShareStudio: View {
    let movie: Movie
    @Environment(AppModel.self) private var model
    @State private var poster: UIImage?
    @State private var ready = false

    var body: some View {
        ShareStage(titles: ["Full", "White", "Black"], ready: ready, exportName: movie.name) { i in
            switch i {
            case 0: FullBleedTemplate(movie: movie, poster: poster)
            case 1: MatTemplate(movie: movie, poster: poster, light: true)
            default: MatTemplate(movie: movie, poster: poster, light: false)
            }
        }
        .task {
            // ImageRenderer can't wait on async images, so the print is fetched up front.
            poster = await model.image(movie, .primary, maxWidth: 1440)
            ready = true
        }
    }
}

private struct Print: View {
    let image: UIImage?
    var body: some View {
        if let image {
            Image(uiImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(.white.opacity(0.05))
        }
    }
}

private extension Movie {
    var shareMeta: String {
        [year.map(String.init), playedDate.map { "Watched \($0.dotted)" }].compactMap { $0 }.joined(separator: "  ·  ")
    }
}

/// The poster edge to edge; a quiet label beneath.
struct FullBleedTemplate: View {
    let movie: Movie
    let poster: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Print(image: poster)
                .frame(width: 360, height: 540)
                .clipped()
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(movie.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(movie.shareMeta).font(.system(size: 9.5)).tracking(0.6).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text("MARQUEE").font(.system(size: 8, weight: .medium)).tracking(2.4).foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
        .background(Color.black)
    }
}

/// A gallery mat — white or black — with the poster floated in generous margin.
struct MatTemplate: View {
    let movie: Movie
    let poster: UIImage?
    let light: Bool

    private var bg: Color { light ? Color(white: 0.96) : .black }
    private var ink: Color { light ? Color(white: 0.08) : .white }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Print(image: poster)
                .frame(width: 256, height: 384)
                .clipped()
                .overlay { Rectangle().strokeBorder(ink.opacity(0.1), lineWidth: 0.5) }
                .shadow(color: .black.opacity(light ? 0.18 : 0), radius: 14, y: 10)
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Text(movie.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                Text(movie.shareMeta).font(.system(size: 9)).tracking(0.6).foregroundStyle(ink.opacity(0.5))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 56)
        }
        .frame(width: 360, height: 640)
        .background(bg)
    }
}
