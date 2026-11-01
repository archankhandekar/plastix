import SwiftUI
import UIKit

private struct StaticMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// When true, every Plumb motion draws its final state at once and the viewfinder
    /// stops drifting. Set by the DEBUG launch argument `-UIStatic 1` for screenshots.
    var staticMotion: Bool {
        get { self[StaticMotionKey.self] }
        set { self[StaticMotionKey.self] = newValue }
    }
}

/// The three Plumb moves. Each returns nil when motion is static (draw the end state at
/// once) and a 150ms crossfade-length curve when Reduce Motion is on.
enum Motion {
    /// Reduce Motion replaces every move with a short crossfade.
    private static let reduced = Animation.easeInOut(duration: 0.15)

    /// The photo turns from its captured angle until the midline is vertical.
    static func plumb(reduceMotion: Bool, staticMotion: Bool) -> Animation? {
        if staticMotion { return nil }
        if reduceMotion { return reduced }
        return .easeOut(duration: 0.5)
    }

    /// Guides grow outward from the axis to each point.
    static func draw(reduceMotion: Bool, staticMotion: Bool) -> Animation? {
        if staticMotion { return nil }
        if reduceMotion { return reduced }
        return .easeOut(duration: 0.3)
    }

    /// Delay between successive guides in a draw.
    static let drawStagger: Double = 0.06

    /// The patient-right outline flips about the axis onto the left side.
    static func mirror(reduceMotion: Bool, staticMotion: Bool) -> Animation? {
        if staticMotion { return nil }
        if reduceMotion { return reduced }
        return .easeInOut(duration: 0.45)
    }
}

/// The two Plumb haptics.
enum Haptics {
    /// Light impact when a point is placed.
    static func pointPlaced() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Success notification on the shutter.
    static func shutter() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
