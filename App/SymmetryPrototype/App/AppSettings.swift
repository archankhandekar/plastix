import Foundation
import SwiftUI
import SymmetryCore
import SymmetryModels

/// User-adjustable analysis settings, persisted in UserDefaults. None of these are patient data.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let sigma = "landmarkSigmaRatio"
        static let blur = "minBlurScore"
        static let clipped = "maxClippedFraction"
        static let tilt = "maxTiltDegrees"
        static let residual = "maxResidualRatio"
        static let exportAck = "exportPrivacyAcknowledged"
        static let ghost = "ghostOverlayEnabled"
        static let noticeSeen = "researchNoticeAccepted"
    }

    private let defaults: UserDefaults

    @Published var landmarkSigmaRatio: Double { didSet { defaults.set(landmarkSigmaRatio, forKey: Key.sigma) } }
    @Published var minBlurScore: Double { didSet { defaults.set(minBlurScore, forKey: Key.blur) } }
    @Published var maxClippedFraction: Double { didSet { defaults.set(maxClippedFraction, forKey: Key.clipped) } }
    @Published var maxTiltDegrees: Double { didSet { defaults.set(maxTiltDegrees, forKey: Key.tilt) } }
    @Published var maxResidualRatio: Double { didSet { defaults.set(maxResidualRatio, forKey: Key.residual) } }
    @Published var exportPrivacyAcknowledged: Bool { didSet { defaults.set(exportPrivacyAcknowledged, forKey: Key.exportAck) } }
    @Published var ghostOverlayEnabled: Bool { didSet { defaults.set(ghostOverlayEnabled, forKey: Key.ghost) } }
    @Published var researchNoticeAccepted: Bool { didSet { defaults.set(researchNoticeAccepted, forKey: Key.noticeSeen) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let t = QualityThresholds()
        landmarkSigmaRatio = defaults.object(forKey: Key.sigma) as? Double ?? FrontalMetricsCalculator.defaultLandmarkSigmaRatio
        minBlurScore = defaults.object(forKey: Key.blur) as? Double ?? t.minBlurScore
        maxClippedFraction = defaults.object(forKey: Key.clipped) as? Double ?? t.maxClippedFraction
        maxTiltDegrees = defaults.object(forKey: Key.tilt) as? Double ?? t.maxTiltDegrees
        maxResidualRatio = defaults.object(forKey: Key.residual) as? Double ?? Registration.defaultMaxResidualRatio
        exportPrivacyAcknowledged = defaults.bool(forKey: Key.exportAck)
        ghostOverlayEnabled = defaults.bool(forKey: Key.ghost)
        researchNoticeAccepted = defaults.bool(forKey: Key.noticeSeen)
    }

    var qualityThresholds: QualityThresholds {
        QualityThresholds(minBlurScore: minBlurScore, maxClippedFraction: maxClippedFraction, maxTiltDegrees: maxTiltDegrees)
    }

    var reportSettings: ReportSettings {
        ReportSettings(landmarkSigmaRatio: landmarkSigmaRatio, qualityThresholds: qualityThresholds, maxResidualRatio: maxResidualRatio)
    }

    func restoreDefaults() {
        let t = QualityThresholds()
        landmarkSigmaRatio = FrontalMetricsCalculator.defaultLandmarkSigmaRatio
        minBlurScore = t.minBlurScore
        maxClippedFraction = t.maxClippedFraction
        maxTiltDegrees = t.maxTiltDegrees
        maxResidualRatio = Registration.defaultMaxResidualRatio
    }
}
