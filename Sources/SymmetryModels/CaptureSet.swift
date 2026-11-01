import Foundation
import SymmetryCore

/// The three views captured at one operative stage.
public struct CaptureSet: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var stage: OperativeStage
    public var positioning: Positioning
    public let createdAt: Date
    public var captures: [ViewAngle: Capture]

    public init(id: UUID = UUID(), stage: OperativeStage, positioning: Positioning, createdAt: Date = Date(),
                captures: [ViewAngle: Capture] = [:]) {
        self.id = id
        self.stage = stage
        self.positioning = positioning
        self.createdAt = createdAt
        self.captures = captures
    }

    public var isComplete: Bool { ViewAngle.allCases.allSatisfy { captures[$0] != nil } }
    public var missingAngles: [ViewAngle] { ViewAngle.allCases.filter { captures[$0] == nil } }
    public var orderedCaptures: [Capture] { ViewAngle.allCases.compactMap { captures[$0] } }
    public var frontal: Capture? { captures[.frontal] }

    /// Swaps the two oblique labels when the user finds they were captured in the wrong order.
    public mutating func swapObliqueLabels() {
        var left = captures[.leftOblique]
        var right = captures[.rightOblique]
        left?.angle = .rightOblique
        right?.angle = .leftOblique
        captures[.leftOblique] = right
        captures[.rightOblique] = left
    }

    public mutating func update(_ capture: Capture) {
        for (angle, existing) in captures where existing.id == capture.id {
            captures[angle] = nil
        }
        captures[capture.angle] = capture
    }

    public func summary(sigma: Double) -> CaptureSetSummary {
        CaptureSetSummary(id: id, stageLabel: stage.label, positioningNote: positioning.summary, capturedAt: createdAt,
                          captures: orderedCaptures.map { $0.summary(sigma: sigma) })
    }
}
