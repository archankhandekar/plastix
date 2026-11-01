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
    static let target = SIMD3<Float>(0, -0.19, 0)

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

    static func scene(model: TorsoModel, skin: CGImage, weave: CGImage) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = color(Texture.drape)

        // Torso: matte clay.
        let torso = SCNNode(geometry: model.geometry())
        let clay = SCNMaterial()
        clay.lightingModel = .blinn
        clay.diffuse.contents = skin
        clay.diffuse.mipFilter = .linear
        clay.diffuse.minificationFilter = .linear
        clay.diffuse.magnificationFilter = .linear
        clay.specular.contents = NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0, alpha: 1)
        clay.shininess = 0.08
        clay.isDoubleSided = false
        torso.geometry?.materials = [clay]
        scene.rootNode.addChildNode(torso)

        // Back drape at z = -0.4. One weave tile spans 16 px at the plane's distance
        // (about 1357 px per metre in the frontal view).
        let planeW: CGFloat = 8, planeH: CGFloat = 6
        let tileMetres: CGFloat = CGFloat(Texture.weaveCell * 2) / 1357
        let plane = SCNPlane(width: planeW, height: planeH)
        plane.materials = [drapeMaterial(weave, repeatsU: planeW / tileMetres, repeatsV: planeH / tileMetres)]
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

    /// A thin curved sheet wrapped around the hips, covering everything below
    /// y = -0.395 (just under the umbilicus). Built as an extruded SCNShape ring that
    /// follows the torso cross-section a few millimetres outside it.
    static func hipDrape(_ weave: CGImage) -> SCNNode {
        // Widest cross-section below the drape line, plus clearance.
        var maxA = 0.0, maxB = 0.0
        var y = TorsoModel.yMin
        while y <= Double(hipDrapeTop) { maxA = max(maxA, TorsoModel.halfWidth(y)); maxB = max(maxB, TorsoModel.halfDepth(y)); y += 0.001 }
        let outerA = maxA + 0.006, outerB = maxB + 0.006
        let thickness = 0.003
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        for (a, b) in [(outerA, outerB), (outerA - thickness, outerB - thickness)] {
            let n = 720
            for k in 0..<n {
                let t = 2 * Double.pi * Double(k) / Double(n)
                // Soft vertical folds, always outward, so the sheet reads as cloth.
                let fold = 1 + 0.035 * (0.5 + 0.5 * sin(18 * t + 0.7 * sin(5 * t)))
                let p = NSPoint(x: fold * a * TorsoModel.spow(sin(t)), y: fold * b * TorsoModel.spow(cos(t)))
                if k == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.close()
        }
        let depth: CGFloat = 0.6
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = 0
        let perimeter = 2 * Double.pi * ((outerA * outerA + outerB * outerB) / 2).squareRoot()
        // About 2000 px per metre at the hip drape's distance.
        let tileMetres = Double(Texture.weaveCell * 2) / 2000
        let side = drapeMaterial(weave, repeatsU: CGFloat(perimeter / tileMetres), repeatsV: CGFloat(Double(depth) / tileMetres))
        let cap = drapeMaterial(weave, repeatsU: CGFloat(2 * outerA / tileMetres), repeatsV: CGFloat(2 * outerB / tileMetres))
        shape.materials = [cap, cap, side]
        let node = SCNNode(geometry: shape)
        // Local z (the extrusion) becomes world -y; local y becomes world +z (front).
        node.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        node.simdPosition = SIMD3(0, hipDrapeTop - Float(depth) / 2, 0)
        return node
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
