import Foundation

/// Shape of one breast mound on the mannequin, in metres. `nippleX` is the distance of
/// the apex from the midline (the side sign is applied by the model), `nippleY` the apex
/// height, `foldY` the lowest point of the fold, `rx` the half-width and `P` the
/// projection of the apex along the surface normal. The upper half-height is fixed at
/// `TorsoModel.ryUpper`.
struct MoundParams: Codable, Equatable {
    let nippleX: Double
    let nippleY: Double
    let foldY: Double
    let rx: Double
    let P: Double
}

/// Design targets for one stage, as a share of L. Logged next to the measured values;
/// they are what the parameters were chosen for, not a claim about any patient.
struct DesignTargets {
    let vertical: Double
    let nippleToMidline: Double
    let fold: Double
    let overlap: Double
}

/// One operative stage of the virtual patient.
struct StageSpec {
    let index: Int
    /// OperativeStage raw key.
    let key: String
    let left: MoundParams
    let right: MoundParams
    let penMarks: Bool
    let rollDegrees: Double
    let radiusMetres: Double
    let targets: DesignTargets
}

enum Stages {
    static let seed: UInt64 = 20261031
    static let yFovDegrees = 40.0
    static let defaultRadius = 1.22

    /// The patient-right mound is the same in every stage; only the patient left varies.
    static let right = MoundParams(nippleX: 0.090, nippleY: -0.175, foldY: -0.245, rx: 0.078, P: 0.045)

    static let s1Left = MoundParams(nippleX: 0.101, nippleY: -0.200, foldY: -0.263, rx: 0.085, P: 0.055)
    static let s2Left = MoundParams(nippleX: 0.090, nippleY: -0.1624, foldY: -0.2486, rx: 0.072, P: 0.038)
    static let s3Left = MoundParams(nippleX: 0.079, nippleY: -0.1714, foldY: -0.259, rx: 0.080, P: 0.050)

    static let all: [StageSpec] = [
        StageSpec(index: 1, key: "preoperativeMarking", left: s1Left, right: right, penMarks: true,
                  rollDegrees: 0, radiusMetres: defaultRadius,
                  targets: DesignTargets(vertical: 0.07, nippleToMidline: 0.03, fold: 0.05, overlap: 0.75)),
        StageSpec(index: 2, key: "afterResection", left: s2Left, right: right, penMarks: false,
                  rollDegrees: 0, radiusMetres: defaultRadius,
                  targets: DesignTargets(vertical: -0.035, nippleToMidline: 0.0, fold: 0.01, overlap: 0.86)),
        StageSpec(index: 3, key: "afterFatGrafting", left: s3Left, right: right, penMarks: false,
                  rollDegrees: 0, radiusMetres: defaultRadius,
                  targets: DesignTargets(vertical: -0.01, nippleToMidline: -0.03, fold: 0.04, overlap: 0.80)),
        // Stage 4 keeps the stage 3 anatomy; only the camera changes (rolled and closer).
        StageSpec(index: 4, key: "afterClosure", left: s3Left, right: right, penMarks: false,
                  rollDegrees: 4, radiusMetres: 1.098,
                  targets: DesignTargets(vertical: -0.01, nippleToMidline: -0.03, fold: 0.04, overlap: 0.80)),
    ]
}
