import CoreMotion
import SwiftUI

/// Device tilt, normalized to roughly -1…1 on each axis, with a slowly drifting
/// neutral so any comfortable holding angle reads as "flat".
@Observable
final class Motion {
    static let shared = Motion()

    private(set) var tilt: CGSize = .zero

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var neutral: (roll: Double, pitch: Double)?

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let a = m?.attitude else { return }
            var n = self.neutral ?? (a.roll, a.pitch)
            n.roll += (a.roll - n.roll) * 0.01
            n.pitch += (a.pitch - n.pitch) * 0.01
            self.neutral = n
            let x = max(-1, min(1, (a.roll - n.roll) / 0.45))
            let y = max(-1, min(1, (a.pitch - n.pitch) / 0.45))
            self.tilt = CGSize(
                width: self.tilt.width + (x - self.tilt.width) * 0.18,
                height: self.tilt.height + (y - self.tilt.height) * 0.18
            )
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        manager.stopDeviceMotionUpdates()
        neutral = nil
        tilt = .zero
    }
}
