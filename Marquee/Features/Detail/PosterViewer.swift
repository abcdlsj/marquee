import SwiftUI

/// The one-sheet at original resolution on black. Pinch or double-tap to inspect; drag down to close.
struct PosterViewer: View {
    let movie: Movie

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = Motion.shared
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero
    @State private var pixelSize: CGSize?

    private var zoomed: Bool { zoom > 1.01 }
    private var tilt: CGSize { reduceMotion || zoomed ? .zero : motion.tilt }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RemoteImage(movie: movie, kind: .primary, contentMode: .fit, original: true) { img in
                pixelSize = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .sheen(tilt: tilt, strength: 0.3)
            .rotation3DEffect(.degrees(tilt.height * 4), axis: (1, 0, 0), perspective: 0.4)
            .rotation3DEffect(.degrees(tilt.width * -5), axis: (0, 1, 0), perspective: 0.4)
            .scaleEffect(zoom)
            .offset(pan)
            .gesture(magnify.simultaneously(with: drag))
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.45, bounce: 0.15)) {
                    if zoomed { reset() } else { zoom = 2.5; committedZoom = 2.5 }
                }
            }
            .onTapGesture { if !zoomed { dismiss() } }
        }
        .overlay(alignment: .bottom) {
            if let p = pixelSize, !zoomed {
                Text("\(Int(p.width)) × \(Int(p.height))").caption(10.5).monospacedDigit().padding(.bottom, 12)
            }
        }
        .statusBarHidden()
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { zoom = max(1, committedZoom * $0.magnification) }
            .onEnded { _ in
                committedZoom = zoom
                if zoom < 1.05 { withAnimation(.spring) { reset() } }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { v in
                pan = CGSize(width: committedPan.width + v.translation.width, height: committedPan.height + v.translation.height)
            }
            .onEnded { v in
                if !zoomed {
                    if v.translation.height > 120 { dismiss() } else { withAnimation(.spring) { reset() } }
                } else {
                    committedPan = pan
                }
            }
    }

    private func reset() {
        zoom = 1; committedZoom = 1; pan = .zero; committedPan = .zero
    }
}
