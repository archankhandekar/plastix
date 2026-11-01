import Foundation
import SymmetryCore
import SymmetryModels

/// The bundled virtual patient: rendered mannequin photos for four stages plus the pixel
/// ground truth of every render (`Resources/VirtualPatient/ground-truth.json`).
///
/// Ground truth is reachable only through `PracticeStore`'s asset keys and is never used for
/// study photos.
struct DemoPatient: Decodable {
    enum DecodeError: Error {
        case badPoint([Double])
    }

    /// One rendered view of one stage. Pixel coordinates are top-left origin, y down.
    struct View: Decodable {
        let image: String
        let blurredImage: String?
        let landmarks: [LandmarkType: Point2D]
        let visible: [LandmarkType: Bool]
        let leftContour: [Point2D]
        let rightContour: [Point2D]

        private enum CodingKeys: String, CodingKey {
            case image, blurredImage, landmarks, visible, leftContour, rightContour
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            image = try c.decode(String.self, forKey: .image)
            blurredImage = try c.decodeIfPresent(String.self, forKey: .blurredImage)
            let rawPoints = try c.decodeIfPresent([String: [Double]].self, forKey: .landmarks) ?? [:]
            var points: [LandmarkType: Point2D] = [:]
            for (key, value) in rawPoints {
                guard let type = LandmarkType(rawValue: key) else { continue }
                points[type] = try DemoPatient.point(value)
            }
            landmarks = points
            let rawVisible = try c.decodeIfPresent([String: Bool].self, forKey: .visible) ?? [:]
            var vis: [LandmarkType: Bool] = [:]
            for (key, value) in rawVisible {
                guard let type = LandmarkType(rawValue: key) else { continue }
                vis[type] = value
            }
            visible = vis
            leftContour = try (c.decodeIfPresent([[Double]].self, forKey: .leftContour) ?? []).map(DemoPatient.point)
            rightContour = try (c.decodeIfPresent([[Double]].self, forKey: .rightContour) ?? []).map(DemoPatient.point)
        }
    }

    /// One operative stage of the virtual patient.
    struct Stage: Decodable {
        let index: Int
        /// The JSON "stage" key, for example "preoperativeMarking".
        let stageKey: String
        let positioning: Positioning
        let views: [ViewAngle: View]
        /// Metrics the render script computed from the truth: name to [value, uncertainty].
        let selfCheck: [String: [Double]]

        var operativeStage: OperativeStage {
            switch stageKey {
            case "preoperativeMarking": return .preoperativeMarking
            case "afterResection": return .afterResection
            case "afterImplantOrExpander": return .afterImplantOrExpander
            case "afterFatGrafting": return .afterFatGrafting
            case "afterClosure": return .afterClosure
            default: return .custom(stageKey)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case index, stage, positioning, views, selfCheck
        }

        private enum PositioningKeys: String, CodingKey {
            case tableAngle, armPosition, lighting, note
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            index = try c.decode(Int.self, forKey: .index)
            stageKey = try c.decode(String.self, forKey: .stage)
            if c.contains(.positioning) {
                let p = try c.nestedContainer(keyedBy: PositioningKeys.self, forKey: .positioning)
                positioning = Positioning(tableAngle: try p.decodeIfPresent(String.self, forKey: .tableAngle) ?? "",
                                          armPosition: try p.decodeIfPresent(String.self, forKey: .armPosition) ?? "",
                                          lighting: try p.decodeIfPresent(String.self, forKey: .lighting) ?? "",
                                          note: try p.decodeIfPresent(String.self, forKey: .note) ?? "")
            } else {
                positioning = Positioning()
            }
            let rawViews = try c.decode([String: View].self, forKey: .views)
            var views: [ViewAngle: View] = [:]
            for (key, value) in rawViews {
                guard let angle = ViewAngle(rawValue: key) else { continue }
                views[angle] = value
            }
            self.views = views
            selfCheck = try c.decodeIfPresent([String: [Double]].self, forKey: .selfCheck) ?? [:]
        }
    }

    let version: Int
    let imageSize: Point2D
    let sigmaRatio: Double
    let stages: [Stage]

    /// The bundled folder reference that holds the renders and the JSON.
    static let subdirectory = "VirtualPatient"

    private enum CodingKeys: String, CodingKey {
        case version, imageSize, sigmaRatio, stages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        imageSize = try DemoPatient.point(try c.decode([Double].self, forKey: .imageSize))
        sigmaRatio = try c.decodeIfPresent(Double.self, forKey: .sigmaRatio) ?? FrontalMetricsCalculator.defaultLandmarkSigmaRatio
        stages = try c.decode([Stage].self, forKey: .stages).sorted { $0.index < $1.index }
    }

    static func decode(_ data: Data) throws -> DemoPatient {
        try JSONDecoder().decode(DemoPatient.self, from: data)
    }

    /// The bundled patient, or nil when the assets are missing or do not decode.
    static func loadBundled(_ bundle: Bundle = .main) -> DemoPatient? {
        guard let data = imageData(named: "ground-truth.json", bundle: bundle) else { return nil }
        return try? decode(data)
    }

    var stageCount: Int { stages.count }

    func stage(_ index: Int) -> Stage? {
        stages.first { $0.index == index }
    }

    func view(stage index: Int, angle: ViewAngle) -> View? {
        stage(index)?.views[angle]
    }

    /// The pixel ground truth of one render as a landmark set, with its outlines.
    func truth(stage index: Int, angle: ViewAngle) -> LandmarkSet? {
        guard let v = view(stage: index, angle: angle) else { return nil }
        return LandmarkSet(points: v.landmarks, leftContour: v.leftContour, rightContour: v.rightContour, imageSize: imageSize)
    }

    /// Bytes of a bundled file in the VirtualPatient folder, for example "vp-s1-frontal.jpg".
    static func imageData(named name: String, bundle: Bundle = .main) -> Data? {
        let ns = name as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? nil : ns.pathExtension
        let url = bundle.url(forResource: base, withExtension: ext, subdirectory: subdirectory)
            ?? bundle.url(forResource: base, withExtension: ext)
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }

    fileprivate static func point(_ a: [Double]) throws -> Point2D {
        guard a.count == 2 else { throw DecodeError.badPoint(a) }
        return Point2D(x: a[0], y: a[1])
    }
}

/// Which bundled render a practice capture came from. Stored only in the practice sidecar,
/// so ground truth can never attach to a study photo.
struct DemoAssetKey: Codable, Hashable {
    enum Variant: String, Codable {
        case sharp, blurred
    }

    let stageIndex: Int
    let angle: ViewAngle
    let variant: Variant
}
