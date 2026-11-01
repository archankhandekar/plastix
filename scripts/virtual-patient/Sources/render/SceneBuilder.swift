import AppKit
import Metal
import SceneKit
import simd

/// The three views rendered per stage. Raw values match SymmetryCore.ViewAngle.
enum ViewKind: String, CaseIterable {
    case frontal, leftOblique, rightOblique

    /// Orbit about the vertical axis through the target. The left oblique moves toward
    /// +x, the patient's left, as ViewAngle.guidanceText asks.
    var orbitDegrees: Double {
        switch self {
        case .frontal: return 0
        case .leftOblique: return 45
        case .rightOblique: return -45
        }
    }
}

enum SceneBuilder {
    static let imageWidth = 1200
    static let imageHeight = 1600
    static let target = SIMD3<Float>(0, -0.235, 0)

    // Light intensities (SceneKit units; 1000 is unit strength). Tuned with QualityCheck
    // so that clipped highlights and shadows stay under 0.02 of the pixels.
    static let keyIntensity: CGFloat = 900
    static let keyPitchDegrees: CGFloat = -60
    static let fillIntensity: CGFloat = 300
    static let ambientIntensity: CGFloat = 250

    static let backDrapeZ: Float = -0.4
    static let hipDrapeTop: Float = -0.395

    static func color(_ c: Texture.RGB) -> NSColor {
        NSColor(srgbRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 1)
    }

    // MARK: - Scene

    static func clayMaterial(_ texture: CGImage) -> SCNMaterial {
        let clay = SCNMaterial()
        clay.lightingModel = .blinn
        clay.diffuse.contents = texture
        clay.diffuse.mipFilter = .linear
        clay.diffuse.minificationFilter = .linear
        clay.diffuse.magnificationFilter = .linear
        clay.specular.contents = NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0, alpha: 1)
        clay.shininess = 0.08
        clay.isDoubleSided = false
        return clay
    }

    static func scene(model: TorsoModel, skin: CGImage, clay: CGImage, weave: CGImage) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = color(Texture.backdrop)

        // Torso: matte clay.
        let torso = SCNNode(geometry: model.geometry())
        torso.geometry?.materials = [clayMaterial(skin)]
        scene.rootNode.addChildNode(torso)
        scene.rootNode.addChildNode(arms(clayMaterial(clay)))

        // Back drape at z = -0.4: a flat, unlit neutral charcoal, so it renders exactly
        // as the backdrop colour in every view.
        let plane = SCNPlane(width: 8, height: 6)
        let backMaterial = SCNMaterial()
        backMaterial.lightingModel = .constant
        backMaterial.diffuse.contents = color(Texture.backdrop)
        backMaterial.isDoubleSided = true
        plane.materials = [backMaterial]
        let back = SCNNode(geometry: plane)
        back.simdPosition = SIMD3(0, target.y, backDrapeZ)
        scene.rootNode.addChildNode(back)

        scene.rootNode.addChildNode(hipDrape(weave))

        // Lights: the overhead OR key, a side fill and ambient.
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = keyIntensity
        key.light!.color = NSColor.white
        key.eulerAngles = SCNVector3(keyPitchDegrees * .pi / 180, 0, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.intensity = fillIntensity
        fill.light!.color = NSColor.white
        fill.eulerAngles = SCNVector3(-15 * CGFloat.pi / 180, -55 * CGFloat.pi / 180, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = ambientIntensity
        ambient.light!.color = NSColor.white
        scene.rootNode.addChildNode(ambient)
        return scene
    }

    static func drapeMaterial(_ weave: CGImage, repeatsU: CGFloat, repeatsV: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = weave
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.minificationFilter = .linear
        m.diffuse.magnificationFilter = .linear
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatsU, repeatsV, 1)
        m.specular.contents = NSColor.black
        m.isDoubleSided = true
        return m
    }

    /// A cloth sheet wrapped around the hips, covering everything below y = -0.395 (just
    /// under the umbilicus). A smooth-shaded tube that hugs the torso at its top hem and
    /// falls in a few soft, wide folds that deepen toward the bottom of the frame. Smooth
    /// normals (central differences on the grid) keep it free of faceted vertical bands.
    static func hipDrape(_ weave: CGImage) -> SCNNode {
        let top = Double(hipDrapeTop), bottom = -1.05
        let rows = 90, cols = 480
        func spow(_ v: Double) -> Double { TorsoModel.spow(v) }
        func surface(_ theta: Double, _ y: Double) -> SIMD3<Double> {
            let drop = top - y
            let a = TorsoModel.halfWidth(max(y, TorsoModel.yMin)), b = TorsoModel.halfDepth(max(y, TorsoModel.yMin))
            let clearance = 0.004 + 0.030 * TorsoModel.smoothstep(0, 0.30, drop)
            let amp = 0.030 * TorsoModel.smoothstep(0.01, 0.35, drop)
            let fold = 1 + amp * (0.5 + 0.5 * sin(5 * theta + 1.2 * sin(2 * theta + 0.4) + 0.8))
            return SIMD3(fold * (a + clearance) * spow(sin(theta)), y, fold * (b + clearance) * spow(cos(theta)))
        }
        var grid = [SIMD3<Double>](repeating: .zero, count: rows * cols)
        for j in 0..<rows {
            let y = top + (bottom - top) * Double(j) / Double(rows - 1)
            for i in 0..<cols { grid[j * cols + i] = surface(-Double.pi + 2 * Double.pi * Double(i) / Double(cols), y) }
        }
        let perimeter = 2.0 * Double.pi * 0.17
        var uvs: [Float] = []
        for j in 0..<rows {
            for i in 0..<cols {
                // One 256 px cloth tile spans 0.12 m.
                uvs += [Float(perimeter * Double(i) / Double(cols) / 0.12), Float((top - grid[j * cols + i].y) / 0.12)]
            }
        }
        let geometry = gridGeometry(grid, rows: rows, cols: cols, uvs: uvs, fallbackNormal: { _ in SIMD3(0, 0, 1) })
        geometry.materials = [drapeMaterial(weave, repeatsU: 1, repeatsV: 1)]
        return SCNNode(geometry: geometry)
    }

    /// Simple clay arms hanging at the sides, slightly away from the body: one smooth,
    /// tapered limb per side from a rounded deltoid down past the bottom of the frame
    /// (the hands are never in shot), so there are no joints or seams to read as a doll.
    static func arms(_ clay: SCNMaterial) -> SCNNode {
        let node = SCNNode()
        for s in [-1.0, 1.0] {
            // Centreline: shoulder, elbow, wrist, hand. Radius knots by arclength share.
            let path = [SIMD3(s * 0.158, -0.026, -0.014), SIMD3(s * 0.236, -0.320, -0.030),
                        SIMD3(s * 0.266, -0.580, -0.006), SIMD3(s * 0.274, -0.760, 0.004)]
            let radii: [(Double, Double)] = [(0.0, 0.056), (0.10, 0.049), (0.24, 0.042), (0.34, 0.040), (0.47, 0.034),
                                             (0.56, 0.035), (0.70, 0.033), (0.82, 0.026), (0.90, 0.030), (1.0, 0.026)]
            let limb = limbGeometry(path: path, radii: radii)
            limb.materials = [clay]
            node.addChildNode(SCNNode(geometry: limb))
        }
        return node
    }

    /// A smooth tube along a Catmull-Rom centreline with a radius that eases between
    /// knots, closed by hemispherical caps, with central-difference normals.
    static func limbGeometry(path: [SIMD3<Double>], radii: [(Double, Double)]) -> SCNGeometry {
        func catmull(_ t: Double) -> SIMD3<Double> {
            let n = path.count - 1
            let x = min(max(t, 0), 1) * Double(n)
            let k = min(Int(x), n - 1)
            let u = x - Double(k)
            let p0 = path[max(k - 1, 0)], p1 = path[k], p2 = path[k + 1], p3 = path[min(k + 2, n)]
            let u2 = u * u, u3 = u2 * u
            let a = 2 * p1, b = p2 - p0, c = 2 * p0 - 5 * p1 + 4 * p2 - p3, d = -p0 + 3 * p1 - 3 * p2 + p3
            return 0.5 * (a + b * u + c * u2 + d * u3)
        }
        // Arclength table.
        let samples = 400
        var pts: [SIMD3<Double>] = [], arc: [Double] = [0]
        for k in 0...samples { pts.append(catmull(Double(k) / Double(samples))) }
        for k in 1...samples { arc.append(arc[k - 1] + simd_distance(pts[k], pts[k - 1])) }
        let total = arc[samples]
        func radius(_ share: Double) -> Double {
            var k = 0
            while k < radii.count - 2 && share > radii[k + 1].0 { k += 1 }
            let (s0, r0) = radii[k], (s1, r1) = radii[k + 1]
            return r0 + (r1 - r0) * TorsoModel.smoothstep(s0, s1, share)
        }
        func frame(_ k: Int) -> (t: SIMD3<Double>, n1: SIMD3<Double>, n2: SIMD3<Double>) {
            let t = simd_normalize(pts[min(k + 1, samples)] - pts[max(k - 1, 0)])
            let n1 = simd_normalize(simd_cross(t, SIMD3(0, 0, 1)))
            return (t, n1, simd_cross(n1, t))
        }
        let cols = 128, capRows = 16, bodyRows = 160
        var rings: [(centre: SIMD3<Double>, n1: SIMD3<Double>, n2: SIMD3<Double>, r: Double, v: Double)] = []
        let f0 = frame(0), fN = frame(samples)
        let rStart = radius(0), rEnd = radius(1)
        for k in 0..<capRows {
            let phi = Double.pi / 2 * Double(k) / Double(capRows)
            rings.append((pts[0] - f0.t * rStart * cos(phi), f0.n1, f0.n2, rStart * sin(phi), -rStart * cos(phi)))
        }
        for k in 0...bodyRows {
            let target = total * Double(k) / Double(bodyRows)
            var i = 0
            while i < samples - 1 && arc[i + 1] < target { i += 1 }
            let fr = frame(i)
            rings.append((pts[i], fr.n1, fr.n2, radius(target / total), target))
        }
        for k in 1...capRows {
            let phi = Double.pi / 2 * Double(k) / Double(capRows)
            rings.append((pts[samples] + fN.t * rEnd * sin(phi), fN.n1, fN.n2, rEnd * cos(phi), total + rEnd * sin(phi)))
        }
        let rows = rings.count
        var grid = [SIMD3<Double>](repeating: .zero, count: rows * cols)
        for (j, ring) in rings.enumerated() {
            for i in 0..<cols {
                let a = 2 * Double.pi * Double(i) / Double(cols)
                grid[j * cols + i] = ring.centre + ring.r * (cos(a) * ring.n1 + sin(a) * ring.n2)
            }
        }
        var uvs: [Float] = []
        for ring in rings {
            // The clay texture spans about 1 m around and 0.8 m down the torso.
            for i in 0..<cols { uvs += [Float(0.26 * Double(i) / Double(cols)), Float(0.3 + ring.v / 0.8)] }
        }
        let tStart = f0.t, tEnd = fN.t
        return gridGeometry(grid, rows: rows, cols: cols, uvs: uvs, fallbackNormal: { j in j < rows / 2 ? -tStart : tEnd })
    }

    /// Triangles over a rows x cols vertex grid, closed in columns, with normals from
    /// central differences (or the fallback where a row collapses to a point).
    static func gridGeometry(_ grid: [SIMD3<Double>], rows: Int, cols: Int, uvs: [Float],
                             fallbackNormal: (Int) -> SIMD3<Double>) -> SCNGeometry {
        var positions: [Float] = [], normals: [Float] = []
        for j in 0..<rows {
            for i in 0..<cols {
                let p = grid[j * cols + i]
                let pl = grid[j * cols + (i + cols - 1) % cols], pr = grid[j * cols + (i + 1) % cols]
                let pa = grid[max(j - 1, 0) * cols + i], pb = grid[min(j + 1, rows - 1) * cols + i]
                var n = simd_cross(pr - pl, pa - pb)
                let len = simd_length(n)
                n = len > 1e-12 ? n / len : fallbackNormal(j)
                positions += [Float(p.x), Float(p.y), Float(p.z)]
                normals += [Float(n.x), Float(n.y), Float(n.z)]
            }
        }
        var indices: [UInt32] = []
        for j in 0..<(rows - 1) {
            for i in 0..<cols {
                let i1 = (i + 1) % cols
                let v00 = UInt32(j * cols + i), v10 = UInt32(j * cols + i1)
                let v01 = UInt32((j + 1) * cols + i), v11 = UInt32((j + 1) * cols + i1)
                indices += [v00, v01, v11, v00, v11, v10]
            }
        }
        let f = MemoryLayout<Float>.size
        let count = positions.count / 3
        let sources = [
            SCNGeometrySource(data: positions.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .vertex, vectorCount: count,
                              usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: f, dataOffset: 0, dataStride: 3 * f),
            SCNGeometrySource(data: normals.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .normal, vectorCount: count,
                              usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: f, dataOffset: 0, dataStride: 3 * f),
            SCNGeometrySource(data: uvs.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .texcoord, vectorCount: count,
                              usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: f, dataOffset: 0, dataStride: 2 * f),
        ]
        return SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    // MARK: - Camera

    static func cameraNode(view: ViewKind, stage: StageSpec) -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Stages.yFovDegrees)
        camera.projectionDirection = .vertical
        camera.zNear = 0.01
        camera.zFar = 10
        let node = SCNNode()
        node.camera = camera
        let psi = Float(view.orbitDegrees * Double.pi / 180)
        let r = Float(stage.radiusMetres)
        node.simdPosition = target + SIMD3(r * sin(psi), 0, r * cos(psi))
        node.simdLook(at: target, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        if stage.rollDegrees != 0 {
            node.simdLocalRotate(by: simd_quatf(angle: Float(stage.rollDegrees * Double.pi / 180), axis: SIMD3(0, 0, 1)))
        }
        return node
    }

    // MARK: - Render

    static func makeRenderer(scene: SCNScene) -> SCNRenderer {
        guard let device = MTLCreateSystemDefaultDevice() else { fail("No Metal device") }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        return renderer
    }

    static func snapshot(_ renderer: SCNRenderer, camera: SCNNode) -> CGImage {
        renderer.pointOfView = camera
        _ = renderer.prepare(renderer.scene!.rootNode, shouldAbortBlock: nil)
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: imageWidth, height: imageHeight),
                                      antialiasingMode: .multisampling4X)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fail("Snapshot has no CGImage") }
        guard cg.width == imageWidth, cg.height == imageHeight else {
            fail("Snapshot is \(cg.width)x\(cg.height), expected \(imageWidth)x\(imageHeight)")
        }
        return cg
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("render: " + message + "\n").data(using: .utf8)!)
    exit(1)
}
