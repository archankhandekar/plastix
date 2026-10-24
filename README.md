# Intraoperative Breast Symmetry Prototype

An offline-first iPhone research prototype for repeated intraoperative assessment of
bilateral breast symmetry from handheld photographs. Frontal, left oblique and right
oblique views are captured per operative stage, landmarks are placed by hand, and
matched views are compared with explicitly defined normalized geometry, uncertainty and
reliability flags.

**Status: research prototype, not clinically validated, not a medical device.** It makes
no recommendation about tissue addition or removal, implant sizing, or any surgical
action, and it never reports a single symmetry score. See `docs/DESIGN.md` for every
design decision and `Sources/SymmetryCore/Export/MeasurementDefinitions.swift` for what
each number means.

## What is in this repository

| Path | Purpose | Verified here |
|------|---------|---------------|
| `Sources/SymmetryCore` | Geometry, normalized frontal metrics with uncertainty, contour overlap, quality gates, similarity registration, comparison, report types. Foundation only. | `swift test`, 59 tests |
| `Sources/SymmetryModels` | Session, capture-set and capture models, file storage with iOS data protection, report builder. Foundation only. | `swift test`, 21 tests |
| `App/SymmetryPrototype` | SwiftUI app: sessions, AVFoundation capture with guides, review, landmark editor, comparison, timeline, export, settings. | Not compiled here (needs Xcode); see acceptance checklist |
| `project.yml` | XcodeGen spec that generates the Xcode project. | |
| `docs/DESIGN.md`, `docs/PLAN.md` | Written design with rulings, and the task-by-task plan the code follows. | |

Nothing in the app makes a network call. There is no analytics, crash reporting, or
cloud dependency. The only identifier collected is a study ID restricted to letters,
digits and dashes.

## Deploy to your iPhone in one command

Requirements: a Mac with Xcode 16 or later, an iPhone on iOS 17 or later with a cable,
and an Apple developer team (a free personal team works for device builds). The camera
does not work in the simulator.

```bash
git clone https://github.com/archankhandekar/plastix.git
cd plastix
./scripts/deploy-iphone.sh
```

The wizard checks Xcode, installs XcodeGen, asks for your Team ID, writes the git-ignored
`Config/Local.xcconfig`, generates the project, lists connected devices, builds with
automatic signing, installs the app on the phone and launches it. It remembers your
answers in `.deploy.env` (git-ignored) so a re-run is quick. Its last, optional stage
sets up the GitHub secrets for TestFlight uploads.

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and push to `main`:

- package tests on Linux (Swift 6.2 container) and on macOS;
- an unsigned iOS simulator build of the app target through XcodeGen and `xcodebuild`,
  which is the compile check for the SwiftUI layer that cannot run in this build
  environment. The `xcodebuild` log is uploaded as an artifact.

macOS runners cost ten times the Linux minute rate on private repositories; the app build
takes a few minutes.

`.github/workflows/testflight.yml` is a manual workflow that archives a Release build
with cloud-managed automatic signing and uploads it to TestFlight. It needs the App Store
Connect API key secrets and the team and bundle variables that the deploy wizard sets, and
an app record in App Store Connect. It has not been exercised from this repository yet.

## Build and run on a Mac by hand

Use this when you would rather not run the wizard. Requirements are the same as above.

### Option A: generate the project with XcodeGen

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then fill in DEVELOPMENT_TEAM
xcodegen generate
open SymmetryPrototype.xcodeproj
```

Then in Xcode: select the `SymmetryPrototype` target, set your team under Signing &
Capabilities, select your iPhone, and run.

### Option B: create the project by hand

1. File > New > Project > iOS > App. Product name `SymmetryPrototype`, interface SwiftUI,
   language Swift. Save it in a folder next to this repository, or inside it (the
   `.gitignore` already excludes `*.xcodeproj`).
2. Delete the generated `ContentView.swift` and `SymmetryPrototypeApp.swift`.
3. Drag the folder `App/SymmetryPrototype` into the project navigator. Choose
   "Create groups", add to the app target, and uncheck `Info.plist` if Xcode offers to add
   it as a resource.
4. File > Add Package Dependencies > Add Local… and pick this repository's root (the
   folder containing `Package.swift`). Add both products, `SymmetryCore` and
   `SymmetryModels`, to the app target.
5. In the target's Build Settings set `Info.plist File` to `App/SymmetryPrototype/Info.plist`
   and `Generate Info.plist File` to No. The supplied plist already contains
   `NSCameraUsageDescription`, `NSMotionUsageDescription`,
   `ITSAppUsesNonExemptEncryption = NO` and portrait-only orientation.
6. Set the deployment target to iOS 17.0 and Swift language version to Swift 5.
7. Select your team under Signing & Capabilities, choose your iPhone, build and run.

### Run the tests

The two packages test anywhere a Swift 5.9+ toolchain runs:

```bash
swift test
```

In Xcode, open the package (or the generated project), pick the `SymmetryPrototype-Package`
scheme and press Cmd-U.

## First-scaffold acceptance checklist

Check these on a physical iPhone before any further work. Each line maps to an acceptance
criterion in the specification.

- [ ] The app launches, shows the research-use notice once, then the session list.
- [ ] A new session accepts `S-014` and rejects `John Smith` and a 17-character code.
- [ ] "New capture set" asks for stage and positioning, then opens the rear camera.
- [ ] The viewfinder shows the three-view checklist (Frontal, Left oblique, Right oblique),
      the midline guide, the level line that follows phone roll, and per-angle guidance.
- [ ] Capturing shows the image with its quality result; a blurred or tilted shot offers
      Retake first, Keep anyway second.
- [ ] After the third view the capture screen closes and the set appears in the timeline
      with three thumbnails.
- [ ] "New capture set" is disabled while any set is incomplete; the incomplete set offers
      "Capture missing".
- [ ] Review lets you swap oblique labels, retake one view, and open the landmark editor.
- [ ] The landmark editor places six landmarks by tap, moves them by drag with a loupe,
      draws contours, and shows live metrics with ± values and "Not measured" where
      landmarks are missing.
- [ ] Compare shows baseline and current images per angle, the registered overlay, metric
      rows with uncertainties, and flags; oblique sections show only images and the
      descriptive note.
- [ ] No number appears without an uncertainty; no screen says better or worse; no
      millimetres or percentages appear.
- [ ] Export is disabled until the privacy acknowledgment is on; it produces a JSON report
      and definitions file and offers only the system share sheet.
- [ ] Settings > Delete all sessions removes every session and image.
- [ ] With the device in airplane mode every feature works identically.

## Measurement summary

All frontal values are fractions of the reference length L, the pixel distance from the
sternal notch to the midline bottom landmark, after rotating the landmark set so the
midline is vertical. "Left" and "right" are the patient's sides.

- Vertical nipple difference, nipple-to-midline distances and their difference,
  inframammary fold height difference, each ± first-order uncertainty from an assumed
  landmark placement sigma (default 0.015 L, editable).
- Contour overlap as a Dice coefficient of the patient-left contour against the mirrored
  patient-right contour.
- Comparisons register current landmarks onto the baseline with a 2D similarity
  transform; the normalized RMS residual above 0.05 L flags the comparison unreliable.
- Quality gate: Laplacian-variance blur score, clipped highlight and shadow fractions,
  phone roll from CoreMotion. Failed gates can be overridden; the override travels with
  the capture into every comparison and export.

## Limitations

- No physical calibration: nothing here is a millimetre, a volume or a percentage of
  symmetry. Ratios depend on consistent midline landmarks.
- Handheld photographs carry perspective, parallax, lens and distance variability.
  Landmark-only similarity registration does not remove perspective or pose change that
  the six landmarks do not capture. There is no pixel-based registration yet.
- Motion sensors describe the phone's orientation in the room, not the camera's pose
  relative to the patient. When the camera points straight down, roll is undefined and
  the gate is skipped.
- Oblique views are descriptive only. Three 2D views are not a volumetric reconstruction.
- Uncertainty excludes the placement error of the two midline landmarks; the registration
  residual is the separate check on frame stability.
- The quality thresholds and the landmark sigma are starting guesses until the
  repeated-capture and expert-annotation study replaces them.
- The app target has not been compiled or run in this build environment. The two Swift
  packages were built and tested with Swift 6.2.4 on Linux; the SwiftUI layer was
  reviewed statically. Expect to fix small compile issues on first build in Xcode.

## Safety, privacy and research use

Intraoperative images may be protected health information. Use only authorized,
consented or appropriately de-identified data, and obtain institutional privacy, security
and IRB review before use. Sessions are stored under iOS complete file protection,
excluded from backups, and deletable per session or all at once. Export requires an
in-app acknowledgment and only ever hands files to the system share sheet. App Store
distribution and medical-device classification depend on intended use and claims; no
clinical decision should rely on this unvalidated prototype.

## Next steps

1. Build in Xcode, work through the acceptance checklist, and fix anything that surfaces.
2. Run the repeated-capture and expert-annotation validation; replace the default sigma
   and thresholds with measured values.
3. Decide the midline-bottom landmark the study will use and fix it in the protocol.
4. Consider pixel-based registration and app-level encryption if the review requires it.
