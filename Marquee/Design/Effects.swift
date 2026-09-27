import SwiftUI

extension View {
    func sheen(tilt: CGSize, strength: Double = 1) -> some View {
        colorEffect(ShaderLibrary.sheen(.boundingRect, .float2(tilt), .float(strength)))
    }
}

/// The room around the artwork: black, lit faintly by a blurred, desaturated copy of it.
struct PosterAura: View {
    let movie: Movie?
    var intensity: Double = 0.5

    var body: some View {
        ZStack {
            Color.black
            if let movie {
                RemoteImage(movie: movie, lowRes: true)
                    .scaleEffect(1.4)
                    .blur(radius: 70, opaque: true)
                    .saturation(0.35)
                    .opacity(intensity)
                    .id(movie.id)
                    .transition(.opacity.animation(.easeInOut(duration: 0.8)))
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
