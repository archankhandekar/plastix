# Intraoperative Breast Symmetry Prototype: Design

Source spec: `Intraoperative_Breast_Symmetry_iOS_Prototype_Plan.pdf` (v0.1, 23 Oct 2026).
This document is the written design the implementation plan argues from. It records every
decision the spec left open, the recommended answer that was taken, and what it costs if wrong.
The owner can overturn any ruling here; the plan and code follow this file.

## What this is

A native, offline-first iPhone research prototype. A surgical team member photographs both
breasts from three handheld angles (frontal, left oblique ~45°, right oblique ~45°) at each
operative stage, marks anatomical landmarks, and compares a capture set with an earlier one
from the same session. The app reports explicitly defined, normalized geometric differences
with uncertainty and reliability flags. It never recommends tissue addition, removal, implant
sizing, or any surgical action, and it never scores "symmetry" as a single number.

Primary job: make a repeatable capture in under a minute, in an operating room, by a user who
may be holding the phone awkwardly, then show a surgeon a paired comparison they can trust or
visibly distrust.

Audience: a research team under IRB oversight. Not patients, not App Store users.

## Grill round: decisions and rulings

Each question is worded so "yes" accepts the recommended answer. All were taken as "yes"
because the build ran unattended; they are the first things to revisit.

**Q1. Scope.** Build the first-scaffold acceptance criteria plus next-coding-agent tasks 1 to
6 (AVFoundation preview with guides, stage labels and protected persistence, manual landmarks,
per-view registration and quality gates, auditable normalized metrics with tests, serial
timeline and export). Task 7 (expert annotation and repeated-capture validation) is a study,
not code, and is out of scope.
Ruling: yes. Cost if wrong: effort spent past the scaffold the owner wanted first.

**Q2. Code layout.** Split the geometry into a Foundation-only Swift package, `SymmetryCore`,
that compiles and tests on Linux and macOS, and keep SwiftUI, AVFoundation, CoreMotion and
file I/O in the app target, which only Xcode can build. Ship an XcodeGen `project.yml` so the
Xcode project is generated rather than hand-maintained, with manual steps as a fallback.
Ruling: yes. Cost if wrong: one extra tool (XcodeGen) for the person setting up the Mac.

**Q3. Landmark set.** Six point landmarks per frontal image: sternal notch (midline top),
midline bottom (xiphoid or umbilicus, whichever is visible and used consistently), left
nipple, right nipple, left inframammary fold (IMF) lowest point, right IMF lowest point.
Optional left and right breast contour polylines. Left and right mean the patient's left and
right; in a frontal photo the patient's left appears on the image's right. The UI labels say
"patient left" and "patient right" everywhere.
Ruling: yes. Cost if wrong: a relabel of the enum and UI copy.

**Q4. Normalization and frame.** The reference length is the pixel distance from sternal
notch to midline bottom. Every distance is reported twice: raw pixels and a ratio to the
reference length. Before measuring, the landmark set is rotated so the midline is vertical.
No millimetres, no volumes, no percentages of "symmetry".
Ruling: yes. Cost if wrong: if the team prefers a different reference (for example
inter-nipple distance) it is a one-function change with tests.

**Q5. Uncertainty.** Each landmark is assumed to be placed with an isotropic standard
deviation sigma, default 1.5% of the reference length, editable in Settings. Metric
uncertainty is propagated first-order (a difference of two independent landmarks has sigma
times the square root of two, divided by the reference length). The comparison screen shows
each metric as value ± uncertainty, and a change between capture sets as delta ± combined
uncertainty. No "better" or "worse" wording.
Ruling: yes. Cost if wrong: a placeholder sigma until the repeated-placement study replaces it.

**Q6. Image quality gates.** Three checks per capture: blur (variance of a 3x3 Laplacian on
a downsampled luminance image), exposure (fraction of pixels clipped at either end), and
device tilt at the moment of capture (CoreMotion roll and pitch). Each has a threshold in
Settings. A failed gate shows a warning and offers retake; the user can keep the image, but
the flag is stored with the capture and surfaces in every comparison that uses it.
Ruling: yes. Cost if wrong: thresholds are guesses until tuned on real captures.

**Q7. Registration.** Per view angle, the current landmark set is registered to the baseline
set with a 2D similarity transform (Umeyama closed form) over the six point landmarks. The
root-mean-square residual, divided by the reference length, is the reliability score; above
0.05 the comparison is flagged unreliable and the overlay is still shown but greyed. No
pixel-based feature registration in this version; stated as a limitation.
Ruling: yes. Cost if wrong: landmark-only registration cannot detect pose change the
landmarks do not capture (for example arm elevation).

**Q8. Contour overlap.** Mirror the patient-right contour across the (now vertical) midline
and compute the Dice coefficient against the patient-left contour on a 256x256 raster of the
normalized frame. Requires at least eight points per contour; otherwise reported as "not
measured".
Ruling: yes. Cost if wrong: raster Dice is coarse; polygon clipping could replace it later.

**Q9. Oblique views.** Descriptive only: side-by-side with the baseline image, the same
quality gates, optional nipple and IMF landmarks for visual overlay, but no bilateral metrics
because the two sides are never in the same oblique image.
Ruling: yes. Cost if wrong: none; it matches the spec.

**Q10. Persistence.** Sessions are JSON files and JPEGs under Application Support, written
with `.completeFileProtection`, excluded from iCloud and iTunes backup, deletable per session
and all at once from Settings. This is the iOS data protection the spec names; there is no
second encryption layer.
Ruling: yes. Cost if wrong: if the IRB requires app-level encryption at rest beyond iOS data
protection, add CryptoKit sealing around the JSON and image writes.

**Q11. Export.** Export is gated behind an in-app acknowledgment that privacy and IRB review
are complete. It writes a de-identified report (JSON) and a measurement-definitions text file
to a temporary folder and hands them to the system share sheet. Images are excluded unless
the user turns them on for that export. Nothing leaves the device without the share sheet.
Ruling: yes. Cost if wrong: an institution may want a fixed file format; the JSON is versioned.

**Q12. Study ID.** Free text restricted to letters, digits and dashes, at most 16 characters,
with on-screen guidance to use a non-identifying code. No names, dates of birth, or MRNs are
collected anywhere.
Ruling: yes. Cost if wrong: none significant.

**Q13. Visual design.** See "Design direction" below. One accent colour, large targets,
dark capture surfaces, light review surfaces, system font.
Ruling: yes.

**Q14. Ghost overlay.** The spec lists the prior-image ghost overlay as a future milestone.
With a live AVFoundation preview it costs one image view, so it is included as a toggle on the
capture screen, off by default.
Ruling: yes. Cost if wrong: remove the toggle.

**Q15. Platform floor and language mode.** iOS 17.0, Swift 5 language mode with Swift 6
toolchain compatibility, no third-party dependencies.
Ruling: yes. Cost if wrong: raising the floor to iOS 18 unlocks nothing the prototype needs.

**Q16. Tests.** `SymmetryCore` is covered by XCTest and runs on Linux in CI and in this
build environment. The app target has a manual acceptance checklist in the README rather than
UI tests, because this environment cannot run Xcode.
Ruling: yes. Cost if wrong: UI regressions are caught by hand.

## Architecture

```
SymmetryPrototype/
  Package.swift                 SwiftPM manifest: SymmetryCore library + tests
  Sources/SymmetryCore/         Foundation-only geometry, metrics, quality, registration
  Tests/SymmetryCoreTests/      XCTest suite (runs on Linux)
  App/SymmetryPrototype/        SwiftUI app sources (Xcode only)
    App/                        entry point, root navigation, theme tokens
    Models/                     StudySession, CaptureSet, Capture (Codable)
    Persistence/                SessionStore (file protection, delete)
    Camera/                     CameraService, preview, guide overlays, motion level
    Imaging/                    UIImage -> luminance buffer bridge, annotated render
    Views/                      Session, Capture, Review, Landmark editor, Comparison,
                                Timeline, Export, Settings
  project.yml                   XcodeGen spec
  docs/                         this design, the plan, measurement definitions
```

`SymmetryCore` knows nothing about images as pixels except through a `LuminanceImage`
value (width, height, `[UInt8]`), and nothing about UI. The app converts captured photos to
that value on a background queue. Every number shown on screen comes from `SymmetryCore`
and has a test.

## Data model

- `StudySession`: id, studyID, createdAt, notes, `[CaptureSet]`.
- `CaptureSet`: id, stage (`OperativeStage`: preoperative marking, after mastectomy or
  resection, after implant or expander placement, after fat grafting, after closure, custom),
  positioning (table angle text, arm position, lighting note), capturedAt, three
  `Capture?` slots keyed by `ViewAngle`.
- `Capture`: id, angle, image filename, pixel size, `QualityReport`, device tilt at capture,
  `LandmarkSet?`, `qualityOverridden` flag.
- `LandmarkSet`: `[LandmarkType: Point2D]`, left and right contour `[Point2D]`, image size.

## Measurement definitions (frontal)

After rotating the landmark set so the midline (sternal notch to midline bottom) is vertical,
with reference length L:

- Vertical nipple difference: (y_leftNipple - y_rightNipple) / L. Positive means the
  patient's left nipple is lower in the image.
- Nipple-to-midline distances: horizontal distance of each nipple from the midline, each / L,
  and their difference (left minus right) / L.
- IMF height difference: (y_leftIMF - y_rightIMF) / L.
- Contour overlap: Dice coefficient between the patient-left contour and the mirrored
  patient-right contour, 0 to 1, or "not measured".

Each is reported with ± uncertainty from the landmark sigma. A comparison between two capture
sets reports the delta of each metric with combined uncertainty, the registration residual,
and every quality flag from either capture.

## Design direction (frontend-design pass)

Subject: an operating room. The phone is held by someone in gloves, often above a drape,
sometimes by a circulating nurse the surgeon is talking to. The screen is glanced at, not
read. Light is harsh and directional.

Plan:
- Colour tokens (theme "Scrub Light"): ink `#17201F`, paper `#F6F7F5`, slate `#5C6B69`,
  accent `#1E7F74` (deep teal reserved for the one primary action and the active guide),
  caution `#B8741A`, unreliable `#8A3B3B`. Dark capture surface `#0E1413`.
- Type: the system font only, with Dynamic Type honoured. Title weight semibold, body
  regular, numerals in monospaced digits so ± columns line up. No custom typeface, by
  choice: this is an instrument, not a brand.
- Layout: capture is a full-bleed viewfinder with a three-segment angle checklist pinned at
  the top and one capture button pinned at the bottom; the guides are the only decoration.
  Review and comparison are light screens with image pairs first and numbers second.
- Principle: the one bold element is the viewfinder guide set; everything else is quiet.
  Every number carries its uncertainty and its flag in the same row. Copy is plain and in
  sentence case: "Retake", "Keep anyway", "Comparison unreliable: landmarks did not align".

Reviewed against the generic default: a stats-first dashboard with cards and a teal
gradient was the obvious shape and was rejected. Images first, numbers second, no cards,
no gradients, no all-caps labels.

## Non-goals and anti-goals

- No automatic segmentation, face or body landmark detection, or machine-learned scoring.
- No network calls of any kind. No analytics. No crash reporting.
- No single symmetry score, no better or worse labels, no surgical recommendations.
- No patient identifiers.
- Failure even if it works: a surgeon changes an operative decision because a number on
  this screen looked precise. Every screen that shows a number also shows its uncertainty
  and the research-use notice.

## Open questions for the owner

1. Which midline-bottom landmark the team will use consistently (xiphoid vs umbilicus).
2. Whether institutional policy requires app-level encryption in addition to iOS data
   protection (Q10).
3. Quality thresholds after the first twenty real captures (Q6).
4. Whether the oblique views should carry any landmarks at all in the first study (Q9).
