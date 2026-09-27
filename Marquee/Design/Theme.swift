import SwiftUI

/// Gallery lighting: black walls, white type in four intensities, one cool accent for state.
enum Theme {
    static let fg = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)
    static let hairline = Color.white.opacity(0.12)
    /// Steel blue-grey; only for "on" states (favorited, watched, selected).
    static let cool = Color(red: 0.68, green: 0.76, blue: 0.86)
}

extension View {
    /// Small wall-label text.
    func caption(_ size: CGFloat = 11, _ color: Color = Theme.tertiary) -> some View {
        font(.system(size: size, weight: .regular)).tracking(size * 0.06).foregroundStyle(color)
    }
}

extension Date {
    var dayKey: Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// 2026.06.28
    var dotted: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d.%02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
