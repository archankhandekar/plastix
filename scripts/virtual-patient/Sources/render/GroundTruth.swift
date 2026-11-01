import CoreGraphics
import Foundation
import SceneKit
import SymmetryCore
import simd

// MARK: - JSON schema (version 1)
//
// Pixel coordinates have a top-left origin with y down, in the JPEG's pixels. Points are
// [x, y] number arrays. The keys are a contract with the app's DemoPatient decoder.

struct GroundTruthFile: Encodable {
    var version = 1
    var generator = "scripts/virtual-patient render"
    var seed: UInt64 = Stages.seed
    var imageSize = [SceneBuilder.imageWidth, SceneBuilder.imageHeight]
    var midlineBottom = "umbilicus"
    var sigmaRatio = GroundTruth.sigmaRatio
    var stages: [StageRecord]
}

struct PositioningRecord: Encodable {
    let tableAngle: String
    let armPosition: String
    let lighting: String
    let note: String
}

struct CameraRecord: Encodable {
    let rollDegrees: Double
    let radiusMetres: Double
    let yFovDegrees: Double
}

struct ParamsRecord: Encodable {
    let left: MoundParams
    let right: MoundParams
    let penMarks: Bool
}

struct ViewRecord: Encodable {
    let image: String
    let blurredImage: String?
    let landmarks: [String: [Double]]
    let visible: [String: Bool]
    let leftContour: [[Double]]
    let rightContour: [[Double]]
}

struct ViewsRecord: Encodable {
    let frontal: ViewRecord
    let leftOblique: ViewRecord
    let rightOblique: ViewRecord
}

struct QualityEntry: Encodable {
    let blurScore: Double
    let highlight: Double
    let shadow: Double

    init(_ r: QualityCheck.Result) { blurScore = r.blurScore; highlight = r.highlight; shadow = r.shadow }
}

struct QualityRecord: Encodable {
    let frontal: QualityEntry
    let leftOblique: QualityEntry
    let rightOblique: QualityEntry
    let frontalBlurred: QualityEntry
}

struct StageRecord: Encodable {
    let index: Int
    let stage: String
    let positioning: PositioningRecord
    let camera: CameraRecord
    let params: ParamsRecord
    let views: ViewsRecord
    let selfCheck: [String: [Double]]
    let quality: QualityRecord
}

// MARK: - Truth for one view

/// Ground truth of one render: projected pixels of every landmark and, on the frontal,
/// both outlines. This is pixel truth of a render, not anatomy.
struct ViewTruth {
    var world: [LandmarkType: SIMD3<Double>] = [:]
    var pixels: [LandmarkType: Point2D] = [:]
    var visible: [LandmarkType: Bool] = [:]
    var leftContour: [Point2D] = []
    var rightContour: [Point2D] = []
    /// Projected crease samples, for the debug overlay only.
    var creases: [[Point2D]] = []

    func record(image: String, blurredImage: String?) -> ViewRecord {
        var lm: [String: [Double]] = [:]
        var vis: [String: Bool] = [:]
        for t in LandmarkType.allCases {
            vis[t.rawValue] = visible[t] ?? false
            if visible[t] == true, let p = pixels[t] { lm[t.rawValue] = [p.x, p.y] }
        }
        return ViewRecord(image: image, blurredImage: blurredImage, landmarks: lm, visible: vis,
                          leftContour: leftContour.map { [$0.x, $0.y] }, rightContour: rightContour.map { [$0.x, $0.y] })
    }

    /// The landmark set the app would compute from (visible points only).
    var landmarkSet: LandmarkSet {
        var pts: [LandmarkType: Point2D] = [:]
        for (t, p) in pixels where visible[t] == true { pts[t] = p }
        return LandmarkSet(points: pts, leftContour: leftContour, rightContour: rightContour,
                           imageSize: Point2D(x: Double(SceneBuilder.imageWidth), y: Double(SceneBuilder.imageHeight)))
    }
}

/// Which y convention renderer.hitTest expects, decided at runtime on the frontal view.
enum HitConvention: String {
    /// The projected y as returned by projectPoint (bottom-left origin).
    case projected
    /// Image y (top-left origin), 1600 - projected y.
    case image
}

enum GroundTruth {
    static let sigmaRatio = 0.015
    static let hitTolerance = 0.005
    static let creaseCount = 200
    static let contourCount = 48

    static func project(_ renderer: SCNRenderer, _ p: SIMD3<Double>) -> (image: Point2D, projectedY: Double) {
        let v = renderer.projectPoint(SCNVector3(p.x, p.y, p.z))
        let y = Double(v.y)
        return (Point2D(x: Double(v.x), y: Double(SceneBuilder.imageHeight) - y), y)
    }

    /// Distance from the target to the first hit along the pixel's ray, metres.
    ///
    /// The notch and the umbilicus sit exactly on a mesh column, so a ray through their
    /// projection runs along a shared triangle edge and can slip between the two
    /// triangles. The test therefore also casts four rays 0.05 px away and keeps the
    /// nearest first hit; an occluded landmark is far from all five.
    static func hitDistance(_ renderer: SCNRenderer, x: Double, projectedY: Double, convention: HitConvention,
                            target: SIMD3<Double>) -> Double {
        let y = convention == .projected ? projectedY : Double(SceneBuilder.imageHeight) - projectedY
        let e = 0.05
        var best = Double.infinity
        for (dx, dy) in [(0.0, 0.0), (e, 0), (-e, 0), (0, e), (0, -e)] {
            let hits = renderer.hitTest(CGPoint(x: x + dx, y: y + dy), options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue,
                SCNHitTestOption.ignoreHiddenNodes: true,
            ])
            guard let first = hits.first else { continue }
            let w = first.worldCoordinates
            best = min(best, simd_distance(SIMD3(Double(w.x), Double(w.y), Double(w.z)), target))
        }
        return best
    }

    /// Projects every landmark of `model` for the current point of view of `renderer`.
    /// The renderer must have just taken this view's snapshot.
    static func truth(model: TorsoModel, renderer: SCNRenderer, view: ViewKind,
                      convention: inout HitConvention?) -> ViewTruth {
        var t = ViewTruth()
        t.world[.sternalNotch] = model.sternalNotch
        t.world[.midlineBottom] = model.umbilicus
        t.world[.leftNipple] = model.nipple(side: 1)
        t.world[.rightNipple] = model.nipple(side: -1)

        // Fold lowest point: the crease sample with the largest image y in this view.
        for (type, side) in [(LandmarkType.leftIMF, 1.0), (.rightIMF, -1.0)] {
            let samples = model.creaseSamples(side: side, count: creaseCount)
            let projected = samples.map { project(renderer, $0).image }
            var best = 0
            for k in 1..<projected.count where projected[k].y > projected[best].y { best = k }
            t.world[type] = samples[best]
            t.creases.append(projected)
        }

        var projectedY: [LandmarkType: Double] = [:]
        for type in LandmarkType.allCases {
            let p = project(renderer, t.world[type]!)
            t.pixels[type] = p.image
            projectedY[type] = p.projectedY
        }

        func distances(_ c: HitConvention) -> [LandmarkType: Double] {
            var d: [LandmarkType: Double] = [:]
            for type in LandmarkType.allCases {
                d[type] = hitDistance(renderer, x: t.pixels[type]!.x, projectedY: projectedY[type]!, convention: c,
                                      target: t.world[type]!)
            }
            return d
        }

        if view == .frontal {
            if convention == nil {
                for c in [HitConvention.projected, .image] where distances(c).values.allSatisfy({ $0 <= hitTolerance }) {
                    convention = c
                    break
                }
                guard convention != nil else {
                    let a = distances(.projected), b = distances(.image)
                    fail("No hit-test y convention puts every frontal landmark within \(hitTolerance) m. projected: \(a) image: \(b)")
                }
            }
            let d = distances(convention!)
            for type in LandmarkType.allCases {
                guard d[type]! <= hitTolerance else { fail("Frontal landmark \(type.rawValue) is not visible (hit \(d[type]!) m away)") }
                t.visible[type] = true
            }
            t.leftContour = clockwise(model.boundarySamples(side: 1, count: contourCount).map { project(renderer, $0).image })
            t.rightContour = clockwise(model.boundarySamples(side: -1, count: contourCount).map { project(renderer, $0).image })
        } else {
            guard let c = convention else { fail("The frontal view must be processed before the obliques") }
            let d = distances(c)
            for type in LandmarkType.allCases { t.visible[type] = d[type]! <= hitTolerance }
        }
        return t
    }

    /// Orders a closed outline clockwise as seen on screen (image y down), which is a
    /// positive shoelace sum in image coordinates.
    static func clockwise(_ pts: [Point2D]) -> [Point2D] {
        var sum = 0.0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum >= 0 ? pts : Array(pts.reversed())
    }

    static func selfCheck(_ m: FrontalMetrics) -> [String: [Double]] {
        func pair(_ v: MetricValue?, _ name: String) -> [Double] {
            guard let v else { fail("selfCheck: \(name) was not computed") }
            return [v.value, v.uncertainty]
        }
        return [
            "verticalNippleDifference": pair(m.verticalNippleDifference, "verticalNippleDifference"),
            "leftNippleToMidline": pair(m.leftNippleToMidline, "leftNippleToMidline"),
            "rightNippleToMidline": pair(m.rightNippleToMidline, "rightNippleToMidline"),
            "nippleToMidlineDifference": pair(m.nippleToMidlineDifference, "nippleToMidlineDifference"),
            "imfHeightDifference": pair(m.imfHeightDifference, "imfHeightDifference"),
            "contourOverlap": pair(m.contourOverlap, "contourOverlap"),
        ]
    }

    // MARK: - Debug overlay

    /// The render with its ground-truth dots, outlines and crease samples. Debug only,
    /// never bundled.
    static func debugOverlay(_ image: CGImage, truth: ViewTruth) -> CGImage {
        let w = image.width, h = image.height
        let ctx = Watermark.context(width: w, height: h)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        func cg(_ p: Point2D) -> CGPoint { CGPoint(x: p.x, y: Double(h) - p.y) }

        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
        for crease in truth.creases {
            ctx.addLines(between: crease.map(cg))
            ctx.strokePath()
        }
        ctx.setLineWidth(3)
        for (contour, color) in [(truth.leftContour, CGColor(srgbRed: 1, green: 0.55, blue: 0.1, alpha: 1)),
                                 (truth.rightContour, CGColor(srgbRed: 0.35, green: 0.75, blue: 1, alpha: 1))] where contour.count > 1 {
            ctx.setStrokeColor(color)
            ctx.addLines(between: contour.map(cg))
            ctx.closePath()
            ctx.strokePath()
            ctx.setFillColor(color)
            for p in contour { ctx.fillEllipse(in: CGRect(x: cg(p).x - 3, y: cg(p).y - 3, width: 6, height: 6)) }
        }
        for type in LandmarkType.allCases {
            guard let p = truth.pixels[type] else { continue }
            let c = cg(p)
            let visible = truth.visible[type] == true
            let color: CGColor
            switch type {
            case .sternalNotch, .midlineBottom: color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            case .leftNipple, .leftIMF: color = CGColor(srgbRed: 1, green: 0.55, blue: 0.1, alpha: 1)
            case .rightNipple, .rightIMF: color = CGColor(srgbRed: 0.35, green: 0.75, blue: 1, alpha: 1)
            }
            let r: CGFloat = 9
            ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.setLineWidth(2)
            if visible {
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            } else {
                ctx.setStrokeColor(color)
                ctx.setLineWidth(3)
                ctx.move(to: CGPoint(x: c.x - r, y: c.y - r)); ctx.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
                ctx.move(to: CGPoint(x: c.x - r, y: c.y + r)); ctx.addLine(to: CGPoint(x: c.x + r, y: c.y - r))
                ctx.strokePath()
            }
        }
        if let n = truth.pixels[.sternalNotch], let b = truth.pixels[.midlineBottom] {
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6))
            ctx.setLineWidth(1.5)
            ctx.move(to: cg(n)); ctx.addLine(to: cg(b)); ctx.strokePath()
        }
        guard let out = ctx.makeImage() else { fail("Cannot draw the debug overlay") }
        return out
    }
}
