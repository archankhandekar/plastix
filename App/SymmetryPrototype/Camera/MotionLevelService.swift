import CoreMotion
import Foundation

/// Publishes phone roll and pitch from the gravity vector for the level cue and the
/// tilt quality gate. These describe the phone's orientation in the room, not the
/// camera's pose relative to the patient.
final class MotionLevelService: ObservableObject {
    /// Rotation about the camera axis, degrees. 0 when the image's vertical is plumb.
    @Published private(set) var rollDegrees: Double?
    /// Camera axis elevation, degrees: 0 pointing at the horizon, −90 pointing straight down.
    @Published private(set) var pitchDegrees: Double?

    private let manager = CMMotionManager()

    /// When gravity lies nearly along the camera axis (phone pointing straight down or
    /// up), roll is undefined; below this in-plane magnitude it is reported as nil.
    static let minimumInPlaneGravity = 0.25

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            let inPlane = (g.x * g.x + g.y * g.y).squareRoot()
            pitchDegrees = atan2(-g.z, inPlane) * 180 / .pi * -1
            if inPlane >= MotionLevelService.minimumInPlaneGravity {
                rollDegrees = atan2(g.x, -g.y) * 180 / .pi
            } else {
                rollDegrees = nil
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        rollDegrees = nil
        pitchDegrees = nil
    }
}
