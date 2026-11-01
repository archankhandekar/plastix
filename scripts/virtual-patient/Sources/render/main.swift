import CoreGraphics
import Foundation
import SceneKit
import SymmetryCore

// Virtual-patient renderer.
//
//   swift run --package-path scripts/virtual-patient render \
//       --out App/SymmetryPrototype/Resources/VirtualPatient [--debug build/virtual-patient-debug] [--stage N]
//
// Renders four stages of a matte, faceless, draped clay mannequin (frontal, both obliques
// and a blurred frontal), writes JPEGs and ground-truth.json, and checks every render with
// the app's own quality gate. Deterministic: fixed seed, hash-based noise, no system random.

struct Options {
    var out: String?
    var debug = "build/virtual-patient-debug"
    var stage: Int?

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        var i = 1
        func value() -> String {
            guard i + 1 < args.count else { fail("\(args[i]) needs a value") }
            i += 1
            return args[i]
        }
        while i < args.count {
            switch args[i] {
            case "--out": o.out = value()
            case "--debug": o.debug = value()
            case "--stage":
                guard let n = Int(value()), (1...Stages.all.count).contains(n) else { fail("--stage takes 1 to \(Stages.all.count)") }
                o.stage = n
            case "-h", "--help":
                print("usage: render --out DIR [--debug DIR] [--stage N]")
                exit(0)
            default: fail("unknown argument \(args[i])")
            }
            i += 1
        }
        guard o.out != nil else { fail("--out DIR is required") }
        return o
    }
}

func write(_ data: Data, to dir: URL, _ name: String) {
    do { try data.write(to: dir.appendingPathComponent(name), options: .atomic) } catch { fail("Cannot write \(name): \(error)") }
}

func fmt(_ v: Double, _ digits: Int = 4) -> String { String(format: "%+.\(digits)f", v) }

let options = Options.parse(CommandLine.arguments)
let outDir = URL(fileURLWithPath: options.out!, isDirectory: true)
let debugDir = URL(fileURLWithPath: options.debug, isDirectory: true)
for dir in [outDir, debugDir] {
    do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { fail("Cannot create \(dir.path): \(error)") }
}

let started = Date()
print("render: building the texture layout and grain field (seed \(Stages.seed))")
let layout = Texture.Layout()
let grain = Texture.grainField(layout)
let weave = Texture.drapeTile()

var records: [StageRecord] = []
var metricsByStage: [Int: FrontalMetrics] = [:]
var problems: [String] = []
var convention: HitConvention?
let stages = Stages.all.filter { options.stage == nil || $0.index == options.stage }

for stage in stages {
    let model = TorsoModel(left: stage.left, right: stage.right)
    // Every landmark must sit where the front gate is 1, so the mound apex and the fold
    // bottom are exactly at their parameters.
    for (s, p) in [(1.0, stage.left), (-1.0, stage.right)] {
        for y in [p.nippleY, p.foldY] {
            let gate = TorsoModel.frontGate(theta: TorsoModel.theta(forBaseX: s * p.nippleX, y: y), y: y)
            guard gate == 1 else { fail("Stage \(stage.index): front gate is \(gate) at a landmark (x \(s * p.nippleX), y \(y))") }
        }
    }
    let skin = Texture.skinImage(model: model, penMarks: stage.penMarks, layout: layout, grain: grain)
    let scene = SceneBuilder.scene(model: model, skin: skin, weave: weave)
    let renderer = SceneBuilder.makeRenderer(scene: scene)

    var views: [ViewKind: ViewRecord] = [:]
    var quality: [String: QualityCheck.Result] = [:]
    var frontalTruth: ViewTruth?

    for view in ViewKind.allCases {
        let camera = SceneBuilder.cameraNode(view: view, stage: stage)
        scene.rootNode.addChildNode(camera)
        let raw = SceneBuilder.snapshot(renderer, camera: camera)
        let truth = GroundTruth.truth(model: model, renderer: renderer, view: view, convention: &convention)
        camera.removeFromParentNode()

        if view == .frontal {
            let notch = truth.pixels[.sternalNotch]!
            guard abs(notch.x - Double(SceneBuilder.imageWidth) / 2) < 60 else {
                fail("Stage \(stage.index): frontal notch projects to x = \(notch.x), not near the centre column")
            }
            frontalTruth = truth
        }
        for (type, p) in truth.pixels where truth.visible[type] == true {
            guard (0...Double(SceneBuilder.imageWidth)).contains(p.x), (0...Double(SceneBuilder.imageHeight)).contains(p.y) else {
                fail("Stage \(stage.index) \(view.rawValue): \(type.rawValue) projects outside the image at \(p)")
            }
        }

        let marked = Watermark.burn(raw)
        let name = "vp-s\(stage.index)-\(view.rawValue).jpg"
        let jpeg = QualityCheck.encodeJPEG(marked)
        write(jpeg, to: outDir, name)
        let q = QualityCheck.measure(jpeg: jpeg)
        quality[view.rawValue] = q
        if let p = QualityCheck.problem(q, blurred: false, name: name) { problems.append(p) }
        write(QualityCheck.encodePNG(GroundTruth.debugOverlay(marked, truth: truth)), to: debugDir,
              "vp-s\(stage.index)-\(view.rawValue).png")

        var blurredName: String?
        if view == .frontal {
            let soft = Watermark.blurred(marked)
            let bname = "vp-s\(stage.index)-frontal-blurred.jpg"
            let bjpeg = QualityCheck.encodeJPEG(soft)
            write(bjpeg, to: outDir, bname)
            let bq = QualityCheck.measure(jpeg: bjpeg)
            quality["frontalBlurred"] = bq
            if let p = QualityCheck.problem(bq, blurred: true, name: bname) { problems.append(p) }
            write(QualityCheck.encodePNG(soft), to: debugDir, "vp-s\(stage.index)-frontal-blurred.png")
            blurredName = bname
        }
        views[view] = truth.record(image: name, blurredImage: blurredName)
        print(String(format: "render: stage %d %@: blur %.1f, highlight %.4f, shadow %.4f, visible %@", stage.index,
                     view.rawValue, q.blurScore, q.highlight, q.shadow,
                     LandmarkType.allCases.filter { truth.visible[$0] == true }.map(\.rawValue).joined(separator: " ")))
    }

    let metrics = FrontalMetricsCalculator.compute(frontalTruth!.landmarkSet, landmarkSigmaRatio: GroundTruth.sigmaRatio)
    metricsByStage[stage.index] = metrics
    let entry: (String) -> QualityEntry = { QualityEntry(quality[$0]!) }
    records.append(StageRecord(
        index: stage.index,
        stage: stage.key,
        positioning: PositioningRecord(tableAngle: "0°", armPosition: "at sides", lighting: "overhead lights", note: "Virtual patient"),
        camera: CameraRecord(rollDegrees: stage.rollDegrees, radiusMetres: stage.radiusMetres, yFovDegrees: Stages.yFovDegrees),
        params: ParamsRecord(left: stage.left, right: stage.right, penMarks: stage.penMarks),
        views: ViewsRecord(frontal: views[.frontal]!, leftOblique: views[.leftOblique]!, rightOblique: views[.rightOblique]!),
        selfCheck: GroundTruth.selfCheck(metrics),
        quality: QualityRecord(frontal: entry("frontal"), leftOblique: entry("leftOblique"), rightOblique: entry("rightOblique"),
                               frontalBlurred: entry("frontalBlurred"))))
}

// MARK: - Table of designed and actual values

print("")
print("stage  metric                       designed    actual     +/-")
for stage in stages {
    guard let m = metricsByStage[stage.index] else { continue }
    let rows: [(String, Double, MetricValue?)] = [
        ("vertical nipple difference", stage.targets.vertical, m.verticalNippleDifference),
        ("nipple to midline difference", stage.targets.nippleToMidline, m.nippleToMidlineDifference),
        ("fold height difference", stage.targets.fold, m.imfHeightDifference),
        ("contour overlap", stage.targets.overlap, m.contourOverlap),
    ]
    for (name, designed, actual) in rows {
        let a = actual.map { fmt($0.value) } ?? "missing"
        let u = actual.map { String(format: "%.4f", $0.uncertainty) } ?? ""
        print("s\(stage.index)     \(name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(fmt(designed, 3))     \(a)    \(u)")
    }
    print(String(format: "s%d     reference length L             %.1f px", stage.index, m.referenceLengthPixels))
}
print(String(format: "\nlights: key %.0f at pitch %.0f, fill %.0f, ambient %.0f; grain %.3f, cell %.4f m; weave %.2f",
             SceneBuilder.keyIntensity, SceneBuilder.keyPitchDegrees, SceneBuilder.fillIntensity, SceneBuilder.ambientIntensity,
             Texture.grainAmplitude, Texture.grainCell, Texture.weaveAmplitude))

// MARK: - Stage sign pattern

if options.stage == nil {
    let u = GroundTruth.sigmaRatio * 2.0.squareRoot()
    func v(_ i: Int, _ k: KeyPath<FrontalMetrics, MetricValue?>) -> MetricValue {
        guard let x = metricsByStage[i]?[keyPath: k] else { fail("stage \(i) is missing a metric") }
        return x
    }
    let vert = \FrontalMetrics.verticalNippleDifference
    let mid = \FrontalMetrics.nippleToMidlineDifference
    let fold = \FrontalMetrics.imfHeightDifference
    let ovl = \FrontalMetrics.contourOverlap
    func check(_ ok: Bool, _ what: String) { if !ok { problems.append("sign pattern: " + what) } }
    check(v(1, vert).value > u, "s1 vertical > u")
    check(v(1, mid).value > u, "s1 nipple-to-midline > u")
    check(v(1, fold).value > u, "s1 fold > u")
    check(v(2, vert).value < -u, "s2 vertical < -u")
    check(abs(v(2, mid).value) <= u, "s2 |nipple-to-midline| <= u")
    check(abs(v(2, fold).value) <= u, "s2 |fold| <= u")
    check(abs(v(3, vert).value) <= u, "s3 |vertical| <= u")
    check(v(3, mid).value < -u, "s3 nipple-to-midline < -u")
    check(v(3, fold).value > u, "s3 fold > u")
    for (k, name) in [(vert, "vertical"), (mid, "nipple-to-midline"), (fold, "fold")] {
        let a = v(3, k), b = v(4, k)
        let tol = (a.uncertainty * a.uncertainty + b.uncertainty * b.uncertainty).squareRoot()
        check(abs(a.value - b.value) <= tol, "s4 \(name) within \(tol) of s3")
    }
    check(abs(v(3, ovl).value - v(4, ovl).value) <= 0.03, "s4 overlap within 0.03 of s3")

    if problems.isEmpty {
        let file = GroundTruthFile(stages: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(file)
            write(data, to: outDir, "ground-truth.json")
        } catch { fail("Cannot encode ground-truth.json: \(error)") }
    }
} else {
    print("render: --stage given, so ground-truth.json is not written")
}

if !problems.isEmpty {
    for p in problems { FileHandle.standardError.write(("render: FAIL " + p + "\n").data(using: .utf8)!) }
    exit(1)
}
print(String(format: "render: all quality and sign checks pass (%.1f s). Images in %@, debug in %@",
             Date().timeIntervalSince(started), outDir.path, debugDir.path))
