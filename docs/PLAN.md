# Intraoperative Breast Symmetry Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An offline-first SwiftUI iPhone research prototype that captures frontal and oblique breast photographs per operative stage, lets a user place landmarks, and reports normalized geometric differences with uncertainty and reliability flags.

**Architecture:** A Foundation-only SwiftPM library `SymmetryCore` holds all geometry, metrics, quality gates and registration and is tested with XCTest on Linux. A SwiftUI app target (Xcode only) owns camera, motion, persistence and screens, and calls `SymmetryCore` for every number it displays.

**Tech Stack:** Swift 5 language mode on a Swift 6 toolchain, SwiftUI, AVFoundation, CoreMotion, Core Graphics, XCTest, XcodeGen. No third-party packages.

**Spec:** `docs/DESIGN.md` (argues from the PDF spec `Intraoperative_Breast_Symmetry_iOS_Prototype_Plan.pdf`).

## Global Constraints

- iOS 17.0 minimum; Swift 5 language mode; no third-party dependencies.
- No network calls, no analytics, no identifiers beyond the study ID (letters, digits, dashes, max 16).
- No millimetre, volume, percentage-symmetry, or better/worse outputs. Every displayed metric shows ± uncertainty and reliability flags.
- "Left" and "right" always mean the patient's side; UI copy says "patient left" / "patient right".
- Sessions written with `.completeFileProtection` and excluded from backup; explicit delete.
- Research-use notice on the session screen and every screen that shows a number.

## Review Focus

1. Landmark set missing one point: metrics must report "not measured" for the affected metric and never crash or return 0. (Task 4)
2. Degenerate midline (notch and bottom at the same pixel): reference length 0 must yield a flagged, non-finite-free result. (Task 3)
3. Image rotated or mirrored by the camera (EXIF orientation): the app must normalize orientation before landmarks are placed, or every y comparison is wrong. (Task 9)
4. Comparison across different view angles or across sessions must be refused, not computed. (Task 6)
5. A quality-failed capture kept by override must keep its flag through every comparison and export. (Task 5, Task 12)

---

### Task 1: Package skeleton and core value types

**Files:**
- Create: `Package.swift`
- Create: `Sources/SymmetryCore/Geometry/Point2D.swift`
- Create: `Sources/SymmetryCore/Model/ViewAngle.swift`
- Create: `Sources/SymmetryCore/Model/LandmarkType.swift`
- Create: `Sources/SymmetryCore/Model/LandmarkSet.swift`
- Test: `Tests/SymmetryCoreTests/LandmarkSetTests.swift`

**Interfaces:**
- Produces: `struct Point2D: Codable, Hashable, Sendable { var x: Double; var y: Double }` with `+ - * distance(to:) rotated(by:) mirroredX(about:)`.
- Produces: `enum ViewAngle: String, Codable, CaseIterable { case frontal, leftOblique, rightOblique }` with `displayName`, `guidanceText`.
- Produces: `enum LandmarkType: String, Codable, CaseIterable { case sternalNotch, midlineBottom, leftNipple, rightNipple, leftIMF, rightIMF }` with `displayName`, `isRequiredForFrontalMetrics`.
- Produces: `struct LandmarkSet: Codable, Equatable { var points: [LandmarkType: Point2D]; var leftContour: [Point2D]; var rightContour: [Point2D]; var imageSize: Point2D }` with `isComplete`, `missing: [LandmarkType]`.

- [ ] Step 1: Write failing tests: `isComplete` false for empty set, true with six points; `missing` lists absent types in `CaseIterable` order; `Point2D.rotated(by: .pi/2)` maps (1,0) to (0,1) within 1e-9.
- [ ] Step 2: Run `swift test --filter LandmarkSetTests`; expect compile failure (types undefined).
- [ ] Step 3: Implement the types.
- [ ] Step 4: Run tests; expect PASS.
- [ ] Step 5: Commit `feat(core): package skeleton and landmark value types`.

### Task 2: Midline frame normalization

**Files:**
- Create: `Sources/SymmetryCore/Geometry/MidlineFrame.swift`
- Test: `Tests/SymmetryCoreTests/MidlineFrameTests.swift`

**Interfaces:**
- Consumes: `LandmarkSet`, `Point2D`.
- Produces: `struct MidlineFrame { let origin: Point2D; let referenceLength: Double; let rotation: Double; func normalize(_ p: Point2D) -> Point2D }` and `static func from(_ set: LandmarkSet) -> MidlineFrame?` (nil when either midline point is missing or referenceLength < 1 pixel). In normalized coordinates the sternal notch is (0,0), the midline bottom is (0,1), x positive toward the image's right.

- [ ] Step 1: Tests: rotated input (midline tilted 30°) normalizes the bottom point to (0,1) within 1e-6; nil for missing notch; nil for coincident points; a point to the image-right of the midline has positive x.
- [ ] Step 2: Run; expect failure.
- [ ] Step 3: Implement with translation, rotation by `-atan2`, scale by 1/L.
- [ ] Step 4: Run; expect PASS.
- [ ] Step 5: Commit `feat(core): midline frame normalization`.

### Task 3: Frontal metrics with uncertainty

**Files:**
- Create: `Sources/SymmetryCore/Metrics/Measurement.swift`
- Create: `Sources/SymmetryCore/Metrics/FrontalMetrics.swift`
- Test: `Tests/SymmetryCoreTests/FrontalMetricsTests.swift`

**Interfaces:**
- Produces: `struct Measurement: Codable, Equatable { let value: Double; let uncertainty: Double; let unit: Unit; enum Unit: String, Codable { case ratioOfReference, pixels, dice } }`.
- Produces: `struct FrontalMetrics: Codable { let verticalNippleDifference: Measurement?; let leftNippleToMidline: Measurement?; let rightNippleToMidline: Measurement?; let nippleToMidlineDifference: Measurement?; let imfHeightDifference: Measurement?; let contourOverlap: Measurement?; let referenceLengthPixels: Double; let flags: [ReliabilityFlag] }`.
- Produces: `enum ReliabilityFlag: String, Codable { case missingLandmarks, degenerateMidline, contourTooSparse, lowImageQuality, excessiveTilt, registrationResidualHigh, qualityOverridden }`.
- Produces: `enum FrontalMetricsCalculator { static func compute(_ set: LandmarkSet, landmarkSigmaRatio: Double = 0.015) -> FrontalMetrics }`.

- [ ] Step 1: Tests: perfectly symmetric synthetic set yields all differences 0 ± σ√2; left nipple 0.1·L lower yields verticalNippleDifference 0.1; same set rotated by 20° gives identical values within 1e-6; missing left IMF yields `imfHeightDifference == nil` and flag `.missingLandmarks` while nipple metrics are still present; degenerate midline yields all nil and `.degenerateMidline`; uncertainty of a difference equals `sigma * sqrt(2)`.
- [ ] Step 2: Run; expect failure.
- [ ] Step 3: Implement via `MidlineFrame`.
- [ ] Step 4: Run; expect PASS.
- [ ] Step 5: Commit `feat(core): frontal metrics with first-order uncertainty`.

### Task 4: Contour overlap (mirrored Dice on raster)

**Files:**
- Create: `Sources/SymmetryCore/Geometry/PolygonRaster.swift`
- Modify: `Sources/SymmetryCore/Metrics/FrontalMetrics.swift`
- Test: `Tests/SymmetryCoreTests/PolygonRasterTests.swift`

**Interfaces:**
- Produces: `enum PolygonRaster { static func dice(_ a: [Point2D], _ b: [Point2D], gridSize: Int = 256, bounds: (min: Point2D, max: Point2D)) -> Double }` using even-odd scanline fill.
- Produces: `FrontalMetrics.contourOverlap` set when both contours have ≥ 8 points, else nil with `.contourTooSparse` flag.

- [ ] Step 1: Tests: identical squares → 1.0; disjoint squares → 0.0; half-overlapping squares → ≈ 0.5 within 0.02; mirrored symmetric contours in a full `LandmarkSet` → overlap ≈ 1.0; a 5-point contour → nil plus flag.
- [ ] Step 2: Run; expect failure.  Step 3: Implement.  Step 4: PASS.  Step 5: Commit `feat(core): contour overlap`.

### Task 5: Image quality gates

**Files:**
- Create: `Sources/SymmetryCore/Quality/LuminanceImage.swift`
- Create: `Sources/SymmetryCore/Quality/QualityGate.swift`
- Test: `Tests/SymmetryCoreTests/QualityGateTests.swift`

**Interfaces:**
- Produces: `struct LuminanceImage { let width: Int; let height: Int; let pixels: [UInt8] }`.
- Produces: `struct QualityThresholds: Codable { var minBlurScore: Double = 60; var maxClippedFraction: Double = 0.05; var maxTiltDegrees: Double = 8 }`.
- Produces: `struct QualityReport: Codable { let blurScore: Double; let clippedHighlightFraction: Double; let clippedShadowFraction: Double; let tiltDegrees: Double?; let failures: [Failure]; var passed: Bool; enum Failure: String, Codable { case blurry, overexposed, underexposed, tilted } }`.
- Produces: `enum QualityGate { static func evaluate(_ image: LuminanceImage, tiltDegrees: Double?, thresholds: QualityThresholds) -> QualityReport }`.

- [ ] Step 1: Tests: a sharp checkerboard has a higher blurScore than the same board box-blurred; a uniform 250 image is overexposed; a uniform 3 image underexposed; tilt 12° fails `.tilted`; tilt nil does not fail; a 1x1 image does not crash.
- [ ] Step 2–5 as above. Commit `feat(core): image quality gates`.

### Task 6: Similarity registration and comparison

**Files:**
- Create: `Sources/SymmetryCore/Registration/SimilarityTransform.swift`
- Create: `Sources/SymmetryCore/Metrics/Comparison.swift`
- Test: `Tests/SymmetryCoreTests/SimilarityTransformTests.swift`, `Tests/SymmetryCoreTests/ComparisonTests.swift`

**Interfaces:**
- Produces: `struct SimilarityTransform { let scale: Double; let rotation: Double; let translation: Point2D; func apply(_ p: Point2D) -> Point2D; static func fit(from: [Point2D], to: [Point2D]) -> SimilarityTransform? }` (Umeyama; nil for < 2 points or degenerate).
- Produces: `struct RegistrationResult { let transform: SimilarityTransform; let rmsResidualRatio: Double; let isReliable: Bool }` and `enum Registration { static func register(_ current: LandmarkSet, to baseline: LandmarkSet, maxResidualRatio: Double = 0.05) -> RegistrationResult? }`.
- Produces: `struct MetricDelta: Codable { let name: String; let baseline: Measurement?; let current: Measurement?; let delta: Measurement? }` and `struct ComparisonResult: Codable { let angle: ViewAngle; let deltas: [MetricDelta]; let registration: RegistrationSummary?; let flags: [ReliabilityFlag] }`.
- Produces: `enum Comparator { static func compare(baseline: FrontalMetrics, current: FrontalMetrics, registration: RegistrationResult?) -> ComparisonResult }` and `enum ComparisonError: Error { case angleMismatch }`.

- [ ] Step 1: Tests: fit recovers a known scale 1.3, rotation 0.2 rad, translation (10, -5) within 1e-6 and residual ≈ 0; noisy correspondences give residual > 0 and `isReliable` false above threshold; delta of two measurements has uncertainty `sqrt(u1² + u2²)`; nil metric on either side gives nil delta; flags from both sides are unioned; a `.registrationResidualHigh` flag appears when unreliable.
- [ ] Step 2–5. Commit `feat(core): registration and comparison`.

### Task 7: Measurement definitions and export report

**Files:**
- Create: `Sources/SymmetryCore/Export/MeasurementDefinitions.swift`
- Create: `Sources/SymmetryCore/Export/ResearchReport.swift`
- Test: `Tests/SymmetryCoreTests/ResearchReportTests.swift`

**Interfaces:**
- Produces: `enum MeasurementDefinitions { static let markdown: String }` listing each metric, its formula, its sign convention, and the limitations paragraph.
- Produces: `struct ResearchReport: Codable { let schemaVersion: Int; let studyID: String; let generatedAt: Date; let captureSets: [CaptureSetSummary]; let comparisons: [ComparisonResult]; let notice: String }` with `func jsonData() throws -> Data`.

- [ ] Step 1: Tests: report round-trips through JSON; `notice` contains "not clinically validated"; definitions mention every `FrontalMetrics` field name.
- [ ] Step 2–5. Commit `feat(core): report and definitions`.

### Task 8: App models, theme and persistence

**Files:**
- Create: `App/SymmetryPrototype/App/SymmetryPrototypeApp.swift`, `App/SymmetryPrototype/App/Theme.swift`, `App/SymmetryPrototype/App/AppSettings.swift`
- Create: `App/SymmetryPrototype/Models/StudySession.swift`, `CaptureSet.swift`, `Capture.swift`, `OperativeStage.swift`
- Create: `App/SymmetryPrototype/Persistence/SessionStore.swift`
- Create: `project.yml`, `App/SymmetryPrototype/Info.plist`

**Interfaces:**
- Produces: `@MainActor final class SessionStore: ObservableObject { @Published var sessions: [StudySession]; func create(studyID:) throws; func save(_:) throws; func delete(_:) throws; func deleteAll() throws; func imageURL(for: Capture, in: StudySession) -> URL; func writeImage(_ data: Data, for: Capture, in: StudySession) throws }`.

- [ ] Step 1: Write the code (Xcode-only target; verified by the README acceptance checklist, not by Linux tests). Document `NSCameraUsageDescription`, `UIFileProtection` default `NSFileProtectionComplete`, `ITSAppUsesNonExemptEncryption = NO`.
- [ ] Step 2: Commit `feat(app): models, theme, protected session store`.

### Task 9: Camera service and capture screen

**Files:**
- Create: `App/SymmetryPrototype/Camera/CameraService.swift`, `CameraPreviewView.swift`, `GuideOverlayView.swift`, `MotionLevelService.swift`
- Create: `App/SymmetryPrototype/Imaging/ImageBridge.swift` (orientation normalization, JPEG encode, luminance downsample to `LuminanceImage`)
- Create: `App/SymmetryPrototype/Views/CaptureView.swift`

- [ ] Step 1: Rear wide camera, locked zoom 1.0, photo output, AVCaptureSession on a serial queue; CoreMotion roll/pitch at 10 Hz for the level cue; guides: vertical midline, horizontal level bubble, oblique hint text per `ViewAngle`, optional ghost overlay of the prior capture at 35% opacity.
- [ ] Step 2: Capture flow: three-step checklist; after each photo, run `QualityGate` off the main thread and show "Retake" or "Keep anyway"; a new capture set is allowed only when all three angles are present.
- [ ] Step 3: Commit `feat(app): AVFoundation capture with guides and quality gate`.

### Task 10: Review and landmark editor

**Files:**
- Create: `App/SymmetryPrototype/Views/ReviewView.swift`, `LandmarkEditorView.swift`, `LandmarkCanvas.swift`

- [ ] Step 1: Review shows each angle's image, its quality report, and a menu to correct the angle label (swap left/right oblique).
- [ ] Step 2: Landmark editor: tap to place the next missing landmark in `LandmarkType` order, drag to adjust, magnifier loupe during drag, contour mode draws polylines, "Clear" per landmark. Landmarks stored in image pixel coordinates.
- [ ] Step 3: Commit `feat(app): review and landmark editor`.

### Task 11: Comparison and timeline

**Files:**
- Create: `App/SymmetryPrototype/Views/ComparisonView.swift`, `TimelineView.swift`, `MetricRow.swift`

- [ ] Step 1: Timeline lists capture sets in order with stage labels; pick any two sets (baseline, current) with matching angles.
- [ ] Step 2: Comparison: per angle, baseline and current images side by side, frontal landmark overlay drawn in the registered frame, metric rows "name  value ± u  →  value ± u  (Δ ± u)" with flags; oblique angles show images and the descriptive note only.
- [ ] Step 3: Commit `feat(app): comparison and timeline`.

### Task 12: Export and settings

**Files:**
- Create: `App/SymmetryPrototype/Views/ExportView.swift`, `SettingsView.swift`

- [ ] Step 1: Export gated by a stored acknowledgment toggle; builds `ResearchReport`, writes `report.json` and `measurement-definitions.md` to a temp folder, optional annotated JPEGs, hands URLs to `ShareLink`.
- [ ] Step 2: Settings: landmark sigma ratio, quality thresholds, registration threshold, delete all sessions (confirm), about and limitations.
- [ ] Step 3: Commit `feat(app): export and settings`.

### Task 13: README and verification

- [ ] Step 1: README: what it is, setup on a Mac (Xcode 16+, XcodeGen or manual), run tests (`swift test`), acceptance checklist, limitations, safety and privacy notes.
- [ ] Step 2: Run `swift build` and `swift test` on the package; record the output in the README's verification section.
- [ ] Step 3: Commit `docs: README with setup, acceptance checklist and limitations`.
