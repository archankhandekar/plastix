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
| `App/SymmetryPrototype` | SwiftUI app: sessions, AVFoundation capture with guides, the per-set left-right symmetry result and obliques, landmark editor, across stages, comparison, export, settings, the virtual patient, and the DEBUG route harness. | Simulator build in CI; device run via acceptance checklist |
| `project.yml` | XcodeGen spec that generates the Xcode project. | |
| `docs/DESIGN.md`, `docs/PLAN.md` | Written design with rulings, and the task-by-task plan the code follows. | |

Nothing in the app makes a network call. There is no analytics, crash reporting, or
cloud dependency. The only identifier collected is a study ID restricted to letters,
digits and dashes.

## Try it on the virtual patient

The app is about bilateral symmetry, not only before and after: every photo set leads to
its own left-right result, and change across stages is a second view on the same
centre-zero axis. To show this without a real patient, the app ships a virtual patient:
a rendered, faceless clay mannequin under a drape at four operative stages, with pixel
ground truth for every point.

1. Launch the app (simulator or phone). On Sessions, tap **Try the virtual patient** in the
   hatched Practice section. This seeds the practice session DEMO-VP1: set 1
   (preoperative marking) and set 2 (after mastectomy or resection) taken and marked,
   set 3 (after fat grafting) taken but not marked, no set 4.
2. Follow the practice tour on the session home, or press the one Next button each time:
   read the left and right result for set 1, look at the obliques side by side, mark the
   points on set 3 (the rings show where the virtual patient's points are), take set 4
   with the virtual camera (practise a retake), then see how each difference changed
   across stages. Export shows what a report would contain and refuses to export.
3. **Reset the virtual patient** (on Sessions, on the home or in Settings) starts again.

Safeguards: practice data lives in its own store (Application Support/Practice), never
in the study store; every practice screen carries the 45-degree hatch band "Practice:
virtual patient. Nothing here is study data."; the reserved DEMO- study code cannot be
used for a study session; practice sessions are refused by export on two independent
markers (the session kind and the DEMO- code); the teaching rings only ever attach to a
photo whose recorded `DemoAssetKey` says it is a bundled render. The mannequin's numbers
say nothing about any patient.

To re-render the mannequin (macOS, about 10 seconds, deterministic):

```bash
swift run --package-path scripts/virtual-patient render \
    --out App/SymmetryPrototype/Resources/VirtualPatient --debug build/virtual-patient-debug
```

See `scripts/virtual-patient/README.md` for the model, the stage design and the checks the
run asserts before it writes anything.

## The Plumb design language

The app looks like an intraoperative measuring instrument used with gloves under OR lights.

- **One axis.** A 2pt Drape-blue rule at exactly half the width means the patient's
  midline or zero difference, and nothing else: on the plate, the lean gauges, the stage
  charts, the capture guide and the point editor's chip map.
- **Columns face the patient.** Patient right is the screen-left column and patient left
  the screen-right column, as in a frontal photo, including the obliques pair (the right
  oblique is flipped and shown on the left). Sides are named "Patient right" and "Patient
  left", never by colour and never as L or R (L is the reference length).
- **Colour shows provenance.** Violet is what you marked. Blue is what the app drew from
  your marks. The white caliper is the difference itself. Everything else is quiet steel
  (Tray, Graduation, Ink). There is no red and there are no colour zones.
- **Boldness in one place.** The symmetry plate: the frontal photo on a dark plate, turned
  so the midline runs straight down, with an L ruler, nipple and fold height guides, nipple
  to midline brackets and the patient-right outline mirrored onto the left.
- **One Next action per screen**, a 64pt verb-first button with no arrows. Every hit area is
  at least 56pt; nothing is smaller than `.subheadline`.
- **Never judge.** Every number is a verbatim `MetricFormatter` string with its ±; a value
  that cannot be computed says "Not measured" and why. There is no single score.
- **Practice data always carries the hatch**; nothing else uses it.

The tokens and components are in `App/SymmetryPrototype/Design` and `App/Theme.swift`; the
full rationale is Q21 in `docs/DESIGN.md`.

## Screenshot harness (DEBUG only)

Debug builds can open any screen straight from launch arguments, over freshly seeded
temporary data:

```bash
xcrun simctl launch --terminate-running-process booted org.research.symmetry.SymmetryPrototype \
    -UIRoute symmetry -UIStage 2 -UIFocus nippleHeight -UIScheme dark -UITextSize accessibility3 -UIStatic 1
```

Routes: `notice`, `sessions`, `home`, `tour`, `symmetry`, `obliques`, `stages`, `compare`,
`capture`, `photocheck`, `review`, `mark`, `export`, `settings`, `explainer`, `newSession`,
`newSet`, `gallery`. Other keys: `-UIDemo`, `-UISeedStudy`, `-UISkipNotice`, `-UIStage`,
`-UIFocus`, `-UIState` (`complete`, `unmarked`, `missingFold`, `noOutlines`,
`blurredKept`), `-UIShowTruth`, `-UIObliqueMode` (`pair`, `wipe`, `switch`),
`-UICaptureAngle`, `-UIPracticeRetake`, `-UIStudyCode`, `-UIScheme`, `-UITextSize`,
`-UIStatic`. The parser is `App/SymmetryPrototype/Debug/LaunchRoute.swift` and the seeding
is `Debug/RouteHarness.swift`; both are compiled only in Debug.

Every harness launch uses new temporary roots (`tmp/RouteHarness-<uuid>/Study` and
`/Practice`) and a wiped UserDefaults suite named `RouteHarness`; it never reads or writes
real study data or real UI flags, and there is no argument that points it at real data.
It prints one `RouteHarness:` line with the temporary roots. CI checks that the Release
binary contains no `UIRoute`, `UIDemo` or `RouteHarness` strings.

`sh scripts/screens.sh` builds, installs and shoots all 34 routes in light and dark at
`large`, `xxxLarge` and `accessibility3` (204 PNGs) into `build/screens/`, gathers the
harness log lines into `build/screens/harness.log`, writes `build/screens/contact-sheet.png`
(with `uv run --with pillow`) and runs the copy guard. `sh scripts/screens.sh home mark`
shoots only those rows; `UDID`, `SCHEMES`, `SIZES` and `SETTLE` override the defaults.

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
  environment. The `xcodebuild` log is uploaded as an artifact;
- an unsigned Release build for `generic/platform=iOS`, then a `strings` check that the
  Release binary contains no `UIRoute`, `UIDemo` or `RouteHarness`, and a grep that fails
  if the route harness is named outside `Debug/` or outside `#if DEBUG`;
- the app unit tests (`xcodebuild test` on an iPhone 16 simulator).

macOS runners cost ten times the Linux minute rate on private repositories; the app build
takes a few minutes.

The Linux job also runs `scripts/check-copy.sh`, a copy guard over every string literal in
`App/SymmetryPrototype`. It fails the build if user-facing text contains a clinical
judgement (better, worse, improve, normal, abnormal), a physical unit (mm, millimetre), a
percentage or a literal percent sign that is not a format conversion, or the word score;
a judging term (symmetric, asymmetric, good, bad, correct, ideal, target, accurate,
success, poor and others); a phrase that compares by distance from zero ("more even",
"closer to zero"); a middle dot; an arrow; an ALL-CAPS label; or a side abbreviated as
"L nipple" / "R fold". A second pass fails on fonts below the `.subheadline` floor
(`.caption`, `.caption2`, `.footnote`). The bare word "symmetry" is allowed.
A line that ends in `// copy-guard: allow` is exempt. Run it locally with
`sh scripts/check-copy.sh` before opening a pull request. The app's own unit tests
(`App/SymmetryPrototypeTests`: the wizard, readings, plate layout, virtual patient, route
harness parser and seeding) run from the `SymmetryPrototype` scheme
with Cmd-U in Xcode or `xcodebuild test -scheme SymmetryPrototype -destination
'platform=iOS Simulator,name=iPhone 16'`.

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
- [ ] "Next: Take the first 3 photos" opens New photo set (stage pre-selected, positioning
      pre-filled from the last set) and then the rear camera.
- [ ] The session screen shows the four numbered steps with status lines and exactly one
      Next button.
- [ ] The viewfinder shows the three-view checklist (Frontal, Left oblique, Right oblique),
      the midline guide, the level line that follows phone roll, and per-angle guidance.
- [ ] Capturing shows the image with one plain sentence per check; a blurred or tilted shot
      offers Retake first (accent), Keep anyway second; a passed shot offers Use this photo
      first.
- [ ] After the third view the capture screen closes and the set appears in the timeline
      with three thumbnails.
- [ ] While a set is incomplete the session screen shows a caution card and the Next button
      reads "Next: Take the missing photo(s)".
- [ ] Review lets you swap oblique labels, retake one view, and open the landmark editor.
- [ ] The landmark editor places six landmarks by tap, moves them by drag with a loupe,
      draws contours, and shows live metrics with ± values, and "Not measured" rows that
      name the missing points.
- [ ] Compare two sets in detail shows baseline and current images per angle, the registered overlay, metric
      rows with uncertainties, and flags; oblique sections show only images and the
      descriptive note.
- [ ] No number appears without an uncertainty; no screen says better or worse; no
      millimetres or percentages appear.
- [ ] Export is disabled until the privacy acknowledgment is on; it produces a JSON report
      and definitions file and offers only the system share sheet.
- [ ] Settings > Delete all sessions removes every session and image.
- [ ] With the device in airplane mode every feature works identically.
- [ ] scripts/check-copy.sh passes.

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
- The app target compiles for the iOS simulator in CI (Xcode 16, unsigned) and the two
  Swift packages pass their tests on Linux and macOS, but the app has not yet been run on
  a device from this repository. Work through the acceptance checklist on an iPhone.

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
