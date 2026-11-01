# Virtual-patient renderer

A small macOS-only SwiftPM package that renders the virtual patient used by the app's
practice mode: a matte, faceless, draped clay mannequin at four operative stages, with
pixel ground truth for every landmark. It is **not** part of the root package, the app
scheme or the Linux CI. It depends only on `SymmetryCore` (through the root package) and
on SceneKit, Metal, CoreGraphics, CoreText, CoreImage and ImageIO.

The output is pixel truth of a render, not anatomy. The mannequin is a teaching prop for
how the app is used; its numbers say nothing about any patient, and the app never shows
or uses them for study photos.

## Run

```bash
swift run --package-path scripts/virtual-patient render \
    --out App/SymmetryPrototype/Resources/VirtualPatient \
    [--debug build/virtual-patient-debug] [--stage N]
```

- `--out` (required): where the 16 JPEGs and `ground-truth.json` go.
- `--debug`: where the debug PNGs go (default `build/virtual-patient-debug`, git-ignored,
  never bundled). Each render is drawn with its ground-truth dots (white notch and
  umbilicus, orange patient left, blue patient right, a cross for a landmark hidden in that
  view), the frontal outlines and the faint crease samples.
- `--stage N`: render one stage only, for quick looks. `ground-truth.json` is then not
  written.

A run takes about 10 seconds on an Apple-silicon Mac. It is deterministic: fixed seed
20261031, hash-based noise, no system random. Two runs give byte-identical JSON (and, on
the same Mac, identical JPEGs).

The run exits non-zero if any quality or stage check fails (see below), and prints a table
of designed and actual values for every stage.

Before committing new assets, open `build/virtual-patient-debug` and check that the dots
sit on the notch, the umbilicus, the nipple apexes and the lowest fold points, that the
outlines follow the mound boundaries, that there is no face or head, that the drape covers
everything below the umbilicus, that the look is matte, and that 'Virtual patient' is
legible in the lower-left corner.

## Files

| File | What it does |
|------|--------------|
| `Package.swift` | Tools 5.9, macOS 13. Depends on the root package by the explicit name `SymmetryPrototype` (path identity would follow the checkout directory name, which differs between worktrees). |
| `Sources/render/main.swift` | Arguments, the per-stage loop, JPEG and PNG output, the self-check, the table, the stage sign checks and `ground-truth.json`. |
| `Sources/render/Stages.swift` | The four stage parameter sets and their design targets. |
| `Sources/render/TorsoModel.swift` | The analytic torso: superellipse base surface, the a(y) and b(y) splines, shoulder ease and neck stump, every displacement field, the landmark points, the crease and boundary samplers, and the 256 x 384 SCNGeometry. |
| `Sources/render/Texture.swift` | The 2048 x 2048 clay texture (grain, areolas, stage 1 pen lines) and the woven drape tile. |
| `Sources/render/SceneBuilder.swift` | Scene, materials, back and hip drapes, the three lights, the camera rig and the SCNRenderer snapshot. |
| `Sources/render/GroundTruth.swift` | The JSON schema types, projection, hit-test visibility, outline ordering, the self-check record and the debug overlay. |
| `Sources/render/QualityCheck.swift` | The app's luminance downsample (a copy of `ImageBridge.luminance`), `QualityGate` on every encoded JPEG, and JPEG/PNG encoding. |
| `Sources/render/Watermark.swift` | Burns in 'Virtual patient' and makes the blurred variant. |

## Model

Metres; y is up; the patient faces +z; the patient's left is +x, which appears on the
image's right.

- Torso: a 256 (theta) x 384 (y) vertex grid, closed in theta, theta in [-pi, pi) with 0 at
  the front, y in [-0.50, +0.12]. Cross-section: superellipse with exponent 2.6.
- Half-width a(y): Catmull-Rom through (+0.02, 0.200), (-0.10, 0.168), (-0.24, 0.145),
  (-0.34, 0.135), (-0.50, 0.160). Half-depth b(y): (+0.02, 0.110), (-0.12, 0.120),
  (-0.34, 0.105), (-0.50, 0.115). Above y = 0 both ease on a quarter ellipse to the neck
  radius 0.065 at +0.07; the neck stump runs to +0.12 with a flat cap. No arms, head or face.
- Features are displacements along the base-surface normal; final normals come from central
  differences on the displaced grid (smooth shading). They act on the front only, through a
  gate that is 1 where the base normal is within about 37 degrees of +z and fades to 0 at
  the side of the torso, so mounds that would spill around the side taper away. Every
  landmark sits where the gate is 1.
- Mound per side: centre (s * nippleX, nippleY); ry = 0.070 above the centre and
  nippleY - foldY below; r^2 from the base-surface x; h = P (1 - r^2)^2 for r < 1. The apex
  is exactly at the nipple parameters.
- Fold crease: a Gaussian groove (depth 0.004, sigma 0.006) on the r = 1 boundary below the
  centre, fading toward the sides. Nipple dome: +0.004 within 0.006 of the apex.
- Sternal notch: dent depth 0.006, sigma 0.012 at (0, 0), between clavicle ridges (height
  0.004) from (+-0.02, 0.005) to (+-0.15, 0.02). Umbilicus: dent depth 0.006, sigma 0.007
  at (0, -0.36), with a +0.0015 rim at r = 0.010.
- Material: Blinn, specular #1E1E1E, shininess 0.08. Diffuse texture: base #CDB9A9, value-
  noise grain with a 6 mm cell (about 12 px in the 1200 px image) at plus or minus 4
  percent luminance, areola discs #A88E80 of radius 0.020 m, and on stage 1 only
  gentian-violet (#4B2A7B) preoperative pen lines (a dashed midline from the notch to the
  umbilicus and both fold curves), so practice teaches that ink on the skin is not an app
  mark.
- Drapes: a back plane at z = -0.4 and a hip sheet (an extruded SCNShape ring with soft
  folds) covering y < -0.395, both #2F6F73 with an 8 px weave at plus or minus 6 percent.
- Lights: directional key at pitch -60 degrees, intensity 900; directional side fill 300;
  ambient 250.
- Camera: perspective, vertical field of view 40 degrees, zNear 0.01, zFar 10, aimed at
  (0, -0.19, 0) from 1.22 m. The obliques orbit 45 degrees about the vertical axis through
  the target: the left oblique toward +x (the patient's left), the right oblique toward -x.
  Stage 4 adds a 4-degree roll about the view axis and a radius of 1.098 m.
- Output: 1200 x 1600 snapshots with 4x multisampling; 'Virtual patient' in system
  semibold 48 px, white at 90 percent on an rgba(12, 16, 19, 0.75) rounded backing, 32 px
  from the left and bottom; the blurred frontal is CIGaussianBlur radius 8 applied after the
  label is burned in; JPEG quality 0.8, sRGB.

## Stages

Values in L (the notch to umbilicus distance in the photo). The patient-right mound is the
same in every stage: nippleX 0.090, nippleY -0.175, foldY -0.245, rx 0.078, P 0.045.
The uncertainty of each difference is 0.015 x sqrt 2, about 0.021.

| Stage | Key | Patient-left mound (nippleX, nippleY, foldY, rx, P) | Camera | Designed: vertical, nipple to midline, fold, overlap | Rendered (this Mac) |
|---|---|---|---|---|---|
| 1 | preoperativeMarking | 0.101, -0.200, -0.263, 0.085, 0.055; pen lines | 1.22 m | +0.07, +0.03, +0.05, about 0.75 | +0.078, +0.060, +0.048, 0.78 |
| 2 | afterResection | 0.090, -0.1624, -0.2486, 0.072, 0.038 | 1.22 m | -0.035, 0.00, +0.01, about 0.86 | -0.039, -0.010, +0.010, 0.93 |
| 3 | afterFatGrafting | 0.079, -0.1714, -0.259, 0.080, 0.050 | 1.22 m | -0.01, -0.03, +0.04, about 0.80 | -0.011, -0.036, +0.039, 0.89 |
| 4 | afterClosure | as stage 3 | 1.098 m, rolled 4 degrees | as stage 3, within the plus or minus | -0.011, -0.036, +0.039, 0.89 |

The nipple-to-midline values differ from the design because each mound is displaced along
the curved base normal, which also moves the apex outward. The story is deliberately
non-monotonic (sign flips, values within the plus or minus, and a rolled, closer stage 4
that reads the same within the plus or minus). It never implies an outcome.

## Checks the run makes

- Every snapshot is 1200 x 1600, and the frontal notch projects near the centre column.
- Quality, on each encoded JPEG decoded again and downsampled exactly like
  `ImageBridge.luminance` (DeviceGray, longest side 256, interpolation .medium): every sharp
  render has `QualityGate.laplacianVariance` >= 90 and both clipped fractions <= 0.02;
  every blurred render has a blur value < 60. Current values are about 205 to 245 for
  sharp renders, about 9 for blurred ones, and no clipped pixels.
- Visibility: `renderer.hitTest` at each projected landmark. The y convention is chosen at
  runtime as the one under which every frontal landmark is hit within 0.005 m of itself,
  then used for the obliques. Because the notch and umbilicus sit exactly on a mesh column,
  the test also casts four rays 0.05 px away and keeps the nearest first hit.
- Stage signs, with u = 0.015 x sqrt 2: s1 vertical, nipple to midline and fold > u;
  s2 vertical < -u, nipple to midline and fold within u; s3 vertical within u, nipple to
  midline < -u, fold > u; s4 vertical, nipple to midline and fold each within
  sqrt(u3^2 + u4^2) of s3, and overlap within 0.03 of s3.

## ground-truth.json (version 1)

Pixel coordinates use a top-left origin with y down, in the JPEG's pixels. Points are
`[x, y]` number arrays. Keys are sorted; doubles are written at full precision, so the app
recomputes `selfCheck` to within 1e-9.

```json
{
  "version": 1,
  "generator": "scripts/virtual-patient render",
  "seed": 20261031,
  "imageSize": [1200, 1600],
  "midlineBottom": "umbilicus",
  "sigmaRatio": 0.015,
  "stages": [ {
    "index": 1,
    "stage": "preoperativeMarking",
    "positioning": { "tableAngle": "0°", "armPosition": "at sides", "lighting": "overhead lights", "note": "Virtual patient" },
    "camera": { "rollDegrees": 0, "radiusMetres": 1.22, "yFovDegrees": 40 },
    "params": { "left": { "nippleX": 0.101, "nippleY": -0.2, "foldY": -0.263, "rx": 0.085, "P": 0.055 }, "right": { ... }, "penMarks": true },
    "views": {
      "frontal": {
        "image": "vp-s1-frontal.jpg",
        "blurredImage": "vp-s1-frontal-blurred.jpg",
        "landmarks": { "sternalNotch": [x, y], "midlineBottom": [x, y], "leftNipple": [x, y], "rightNipple": [x, y], "leftIMF": [x, y], "rightIMF": [x, y] },
        "visible": { "sternalNotch": true, ...all six },
        "leftContour": [[x, y], ...48],
        "rightContour": [[x, y], ...48]
      },
      "leftOblique": { "image": "vp-s1-leftOblique.jpg", "landmarks": { only the visible ones }, "visible": { all six }, "leftContour": [], "rightContour": [] },
      "rightOblique": { ...same shape }
    },
    "selfCheck": { "verticalNippleDifference": [v, u], "leftNippleToMidline": [v, u], "rightNippleToMidline": [v, u], "nippleToMidlineDifference": [v, u], "imfHeightDifference": [v, u], "contourOverlap": [v, u] },
    "quality": { "frontal": { "blurScore": n, "highlight": f, "shadow": f }, "leftOblique": {...}, "rightOblique": {...}, "frontalBlurred": {...} }
  } ]
}
```

- `stage` is an `OperativeStage` key: preoperativeMarking, afterResection, afterFatGrafting,
  afterClosure.
- Nipples are the analytic apex plus the dome; the notch and umbilicus are the dent centres;
  each fold point is the crease sample (of 200) with the largest image y in that view.
- Outlines are the r = 1 boundary sampled at 48 points on the displaced surface, frontal
  only, ordered clockwise on screen. The mounds are wider than the front of the torso, so
  where the boundary would run past the lateral silhouette (the displaced-surface point
  that reaches farthest sideways at that height) it follows the silhouette instead. That is
  where the outline is seen and would be drawn in a frontal photo. The switch is
  continuous, but the silhouette itself has small steps where the mound bulge meets the
  side of the torso. The fold crease samples use the same rule.
- `selfCheck` is `FrontalMetricsCalculator.compute(LandmarkSet(points:leftContour:rightContour:imageSize:), landmarkSigmaRatio: 0.015)` on the frontal truth.
- `quality` holds `QualityGate` values on each encoded JPEG.

The app bundles `App/SymmetryPrototype/Resources/VirtualPatient` as a folder reference, so
files resolve with `Bundle.main.url(forResource:withExtension:subdirectory: "VirtualPatient")`.
`App/SymmetryPrototypeTests/VirtualPatientAssetTests.swift` checks these assets in the app.
