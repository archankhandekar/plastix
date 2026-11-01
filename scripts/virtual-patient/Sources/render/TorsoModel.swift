import Foundation
import SceneKit
import simd

/// Analytic mannequin torso in metres. y is up, the patient faces +z, and the patient's
/// left is +x (which appears on the image's right in a frontal photo).
///
/// The base surface is a superellipse cross-section swept along y. Every feature (the
/// two mounds, the fold creases, the nipple domes, the sternal notch, the clavicle ridges
/// and the umbilicus) is a scalar displacement along the base-surface normal, so a
/// landmark is the same analytic function evaluated at its parameters as the mesh vertex
/// that would sit there.
struct TorsoModel {
    let left: MoundParams
    let right: MoundParams

    // MARK: - Constants

    static let thetaCount = 512
    static let yCount = 512
    static let yMin = -0.50
    /// The neck runs past the top of every frame, so no cut end is ever in shot.
    static let yMax = 0.30
    static let exponent = 2.6
    static let ryUpper = 0.070
    static let neckRadius = 0.066
    static let neckStart = 0.115
    /// Where the shoulder ease begins: the width just above the notch level, the depth a
    /// little below it, so the upper chest rolls back into the neck without an edge.
    static let widthEaseStart = -0.01
    static let depthEaseStart = -0.05
    static let umbilicusY = -0.36

    /// Half-width a(y): (y, a) knots, ascending y.
    static let widthKnots: [(Double, Double)] = [(-0.50, 0.160), (-0.34, 0.135), (-0.24, 0.145), (-0.10, 0.163), (0.02, 0.160)]
    /// Half-depth b(y): (y, b) knots, ascending y.
    static let depthKnots: [(Double, Double)] = [(-0.50, 0.115), (-0.34, 0.105), (-0.12, 0.120), (0.02, 0.110)]

    // MARK: - Base surface

    /// Catmull-Rom (finite-difference tangents) cubic Hermite through non-uniform knots.
    static func spline(_ knots: [(Double, Double)], _ y: Double) -> Double {
        let n = knots.count
        if y <= knots[0].0 { return knots[0].1 }
        if y >= knots[n - 1].0 { return knots[n - 1].1 }
        func tangent(_ i: Int) -> Double {
            if i == 0 { return (knots[1].1 - knots[0].1) / (knots[1].0 - knots[0].0) }
            if i == n - 1 { return (knots[n - 1].1 - knots[n - 2].1) / (knots[n - 1].0 - knots[n - 2].0) }
            return (knots[i + 1].1 - knots[i - 1].1) / (knots[i + 1].0 - knots[i - 1].0)
        }
        var k = 0
        while k < n - 2 && y > knots[k + 1].0 { k += 1 }
        let (y0, p0) = knots[k], (y1, p1) = knots[k + 1]
        let h = y1 - y0
        let t = (y - y0) / h
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1, h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2, h11 = t3 - t2
        return h00 * p0 + h10 * h * tangent(k) + h01 * p1 + h11 * h * tangent(k + 1)
    }

    /// Above y = 0 the radius eases to the neck radius at `neckStart` along a smoothstep:
    /// a rounded shoulder, a sloping trapezius line and a concave fillet into the neck,
    /// which then runs straight up and out of frame.
    static func shoulderEase(_ start: Double, _ atStart: Double, _ y: Double) -> Double {
        if y >= neckStart { return neckRadius }
        let t = (y - start) / (neckStart - start)
        return neckRadius + (atStart - neckRadius) * (1 - t * t * (3 - 2 * t))
    }

    static let widthAtEase = spline(widthKnots, widthEaseStart)
    static let depthAtEase = spline(depthKnots, depthEaseStart)

    static func halfWidth(_ y: Double) -> Double {
        y > widthEaseStart ? shoulderEase(widthEaseStart, widthAtEase, y) : spline(widthKnots, y)
    }

    static func halfDepth(_ y: Double) -> Double {
        y > depthEaseStart ? shoulderEase(depthEaseStart, depthAtEase, y) : spline(depthKnots, y)
    }

    @inline(__always) static func spow(_ v: Double) -> Double {
        let m = pow(abs(v), 2.0 / exponent)
        return v < 0 ? -m : m
    }

    static func base(theta: Double, y: Double) -> SIMD3<Double> {
        SIMD3(halfWidth(y) * spow(sin(theta)), y, halfDepth(y) * spow(cos(theta)))
    }

    /// Outward unit normal of the base surface from central differences of the analytic
    /// parameterization.
    static func baseNormal(theta: Double, y: Double) -> SIMD3<Double> {
        let dt = 1e-5, dy = 1e-5
        let pt = base(theta: theta + dt, y: y) - base(theta: theta - dt, y: y)
        let py = base(theta: theta, y: y + dy) - base(theta: theta, y: y - dy)
        let n = simd_cross(pt, py)
        let len = simd_length(n)
        return len > 0 ? n / len : SIMD3(0, 0, 1)
    }

    /// Front-facing theta for a base-surface x at height y (|x| clamped inside a(y)).
    static func theta(forBaseX x: Double, y: Double) -> Double {
        let a = halfWidth(y)
        let r = min(abs(x) / a, 1)
        let s = pow(r, exponent / 2)
        return x < 0 ? -asin(s) : asin(s)
    }

    // MARK: - Displacement fields

    @inline(__always) static func smoothstep(_ e0: Double, _ e1: Double, _ v: Double) -> Double {
        let t = min(max((v - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Features act on the front only. The gate follows how far the base surface has
    /// turned away from the front (the z component of its normal): 1 where the normal is
    /// within about 37 degrees of +z, fading to 0 where the side of the torso faces
    /// sideways. Every landmark sits where the gate is 1 (main checks this), so nothing is
    /// cut off at the silhouette and the parts of a mound that would spill around the side
    /// of the torso taper away.
    static let gateLow = 0.0
    static let gateHigh = 0.80

    @inline(__always) static func frontGate(theta: Double, y: Double) -> Double {
        guard cos(theta) > 0 else { return 0 }
        return smoothstep(gateLow, gateHigh, baseNormal(theta: theta, y: y).z)
    }

    func mound(_ side: Double) -> MoundParams { side > 0 ? left : right }

    /// Profile exponent of the mound: 2 on the upper pole (a long, gently concave slope
    /// from the chest) easing to 1.1 on the lower pole (a full lower pole that turns
    /// sharply into the fold). Smooth in v, so the surface has no seam at the centre line.
    @inline(__always) static func profileExponent(_ v: Double) -> Double {
        2.0 - 0.9 * smoothstep(0.35, -0.55, v)
    }

    /// Papilla radius and height, and the raised areola, metres.
    static let papillaRadius = 0.0055
    static let papillaHeight = 0.0050
    static let areolaRise = 0.0012

    /// The mound height plus the fold groove and the nipple-areola complex for one side.
    func breastField(side s: Double, xb: Double, y: Double) -> Double {
        let p = mound(s)
        let cx = s * p.nippleX, cy = p.nippleY
        let ryLower = p.nippleY - p.foldY
        let ry = y >= cy ? TorsoModel.ryUpper : ryLower
        let u = (xb - cx) / p.rx, v = (y - cy) / ry
        let r2 = u * u + v * v
        var h = 0.0
        if r2 < 1 { h += p.P * pow(1 - r2, TorsoModel.profileExponent(v)) }

        // Fold crease: a groove centred on the r = 1 boundary below the centre, fading
        // out toward the sides of the mound.
        if y < cy {
            let rho = r2.squareRoot()
            if rho > 1e-9 {
                let localRadius = ((p.rx * u / rho) * (p.rx * u / rho) + (ryLower * v / rho) * (ryLower * v / rho)).squareRoot()
                let dist = (rho - 1) * localRadius
                let fade = pow(max(0, -v / rho), 1.5)
                h -= 0.004 * exp(-dist * dist / (2 * 0.006 * 0.006)) * fade
            }
        }

        // Nipple-areola complex: a slightly raised areola and a papilla with a rounded,
        // flat-topped profile. Both peak exactly at the apex.
        let dx = xb - cx, dy = y - cy
        let d = (dx * dx + dy * dy).squareRoot()
        h += TorsoModel.areolaRise * (1 - TorsoModel.smoothstep(0.6, 1.0, d / Texture.areolaRadius))
        h += TorsoModel.papillaHeight * (1 - TorsoModel.smoothstep(0.45, 1.0, d / TorsoModel.papillaRadius))
        return h
    }

    static func segmentDistance(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let vx = bx - ax, vy = by - ay
        let t = min(max(((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy), 0), 1)
        let qx = ax + t * vx - px, qy = ay + t * vy - py
        return (qx * qx + qy * qy).squareRoot()
    }

    /// The breasts project mostly forward, as they do on a standing patient, rather than
    /// along the curved base normal (which pushed a lateral apex out to the silhouette):
    /// their displacement direction is the base normal blended this far toward +z.
    static let forwardBlend = 0.55

    /// Total displacement at (theta, y): along the base normal for the chest features and
    /// along the forward-blended direction for the breasts, both gated to the front.
    func displacement(theta: Double, y: Double) -> (chest: Double, breast: Double) {
        let gate = TorsoModel.frontGate(theta: theta, y: y)
        if gate <= 0 { return (0, 0) }
        let xb = TorsoModel.base(theta: theta, y: y).x
        let breast = breastField(side: 1, xb: xb, y: y) + breastField(side: -1, xb: xb, y: y)
        var h = 0.0

        // Sternal notch.
        h -= 0.006 * exp(-(xb * xb + y * y) / (2 * 0.012 * 0.012))
        // Clavicle ridges, rising gently from the notch toward the shoulders.
        for s in [-1.0, 1.0] {
            let d = TorsoModel.segmentDistance(xb, y, s * 0.022, 0.006, s * 0.13, 0.028)
            h += 0.003 * exp(-d * d / (2 * 0.009 * 0.009))
        }
        // Umbilicus with a shallow rim.
        let uy = y - TorsoModel.umbilicusY
        let du = (xb * xb + uy * uy).squareRoot()
        h -= 0.006 * exp(-du * du / (2 * 0.007 * 0.007))
        h += 0.0015 * exp(-(du - 0.010) * (du - 0.010) / (2 * 0.002 * 0.002))
        return (gate * h, gate * breast)
    }

    /// A point on the displaced surface.
    func point(theta: Double, y: Double) -> SIMD3<Double> {
        let n = TorsoModel.baseNormal(theta: theta, y: y)
        let h = displacement(theta: theta, y: y)
        var p = TorsoModel.base(theta: theta, y: y) + n * h.chest
        if h.breast != 0 {
            let w = TorsoModel.forwardBlend
            p += simd_normalize(n * (1 - w) + SIMD3(0, 0, w)) * h.breast
        }
        return p
    }

    /// A point on the displaced front surface at base-surface x and height y.
    func point(baseX x: Double, y: Double) -> SIMD3<Double> {
        point(theta: TorsoModel.theta(forBaseX: x, y: y), y: y)
    }

    // MARK: - Landmarks

    var sternalNotch: SIMD3<Double> { point(theta: 0, y: 0) }
    var umbilicus: SIMD3<Double> { point(theta: 0, y: TorsoModel.umbilicusY) }

    /// The nipple apex: the mound apex plus the dome, at exactly the nipple parameters.
    func nipple(side s: Double) -> SIMD3<Double> {
        let p = mound(s)
        return point(baseX: s * p.nippleX, y: p.nippleY)
    }

    /// The point of the displaced front surface at height y that reaches farthest toward
    /// side s (the lateral silhouette of the frontal view at that height), with its
    /// base-surface x.
    func lateralSilhouette(side s: Double, y: Double) -> (point: SIMD3<Double>, baseX: Double) {
        func reach(_ t: Double) -> Double { s * point(theta: s * t, y: y).x }
        let steps = 120
        var best = 0.0, bestValue = -Double.infinity
        for k in 0...steps {
            let t = Double.pi / 2 * Double(k) / Double(steps)
            let v = reach(t)
            if v > bestValue { bestValue = v; best = t }
        }
        // Golden-section refinement around the coarse maximum.
        var lo = max(0, best - Double.pi / 2 / Double(steps)), hi = min(Double.pi / 2, best + Double.pi / 2 / Double(steps))
        let g = (5.0.squareRoot() - 1) / 2
        for _ in 0..<40 {
            let a = hi - g * (hi - lo), b = lo + g * (hi - lo)
            if reach(a) < reach(b) { lo = a } else { hi = b }
        }
        let theta = s * (lo + hi) / 2
        return (point(theta: theta, y: y), TorsoModel.base(theta: theta, y: y).x)
    }

    /// A point on a mound's r = 1 boundary on the displaced surface. Where the boundary
    /// would run past the lateral silhouette (the mounds are wider than the front of the
    /// torso), it follows the silhouette instead, which is where the outline is seen and
    /// drawn in a frontal photo. The switch is continuous: both rules give the same point
    /// where the boundary's base x equals the silhouette's.
    func boundaryPoint(side s: Double, phi: Double) -> SIMD3<Double> {
        let p = mound(s)
        let ry = sin(phi) >= 0 ? TorsoModel.ryUpper : p.nippleY - p.foldY
        let y = p.nippleY + ry * sin(phi)
        let x = s * p.nippleX + p.rx * cos(phi)
        if s * x > p.nippleX {
            let sil = lateralSilhouette(side: s, y: y)
            if s * x >= s * sil.baseX { return sil.point }
        }
        return point(baseX: x, y: y)
    }

    /// 200 samples of the fold crease (the lower half of the r = 1 boundary).
    func creaseSamples(side s: Double, count: Int = 200) -> [SIMD3<Double>] {
        (0..<count).map { k in
            let phi = -Double.pi + Double.pi * Double(k) / Double(count - 1)
            return boundaryPoint(side: s, phi: phi)
        }
    }

    /// 48 samples of the whole r = 1 boundary on the displaced surface.
    func boundarySamples(side s: Double, count: Int = 48) -> [SIMD3<Double>] {
        (0..<count).map { k in
            boundaryPoint(side: s, phi: Double.pi / 2 - 2 * Double.pi * Double(k) / Double(count))
        }
    }

    // MARK: - Mesh

    static func gridTheta(_ i: Int) -> Double { -Double.pi + 2 * Double.pi * Double(i) / Double(thetaCount) }
    static func gridY(_ j: Int) -> Double { yMin + (yMax - yMin) * Double(j) / Double(yCount - 1) }

    /// Texture coordinates: u follows theta, v runs from the top of the torso (0) to the
    /// bottom (1).
    static func texcoord(theta: Double, y: Double) -> (Double, Double) {
        ((theta + Double.pi) / (2 * Double.pi), (yMax - y) / (yMax - yMin))
    }

    func geometry() -> SCNGeometry {
        let nt = TorsoModel.thetaCount, ny = TorsoModel.yCount
        var grid = [SIMD3<Double>](repeating: .zero, count: nt * ny)
        for j in 0..<ny {
            let y = TorsoModel.gridY(j)
            for i in 0..<nt { grid[j * nt + i] = point(theta: TorsoModel.gridTheta(i), y: y) }
        }

        var positions: [Float] = []
        var normals: [Float] = []
        var uvs: [Float] = []
        positions.reserveCapacity((nt * ny + nt + 1) * 3)
        for j in 0..<ny {
            let y = TorsoModel.gridY(j)
            for i in 0..<nt {
                let p = grid[j * nt + i]
                let pl = grid[j * nt + (i + nt - 1) % nt], pr = grid[j * nt + (i + 1) % nt]
                let pd = grid[max(j - 1, 0) * nt + i], pu = grid[min(j + 1, ny - 1) * nt + i]
                var n = simd_cross(pr - pl, pu - pd)
                let len = simd_length(n)
                n = len > 0 ? n / len : SIMD3(0, 0, 1)
                positions += [Float(p.x), Float(p.y), Float(p.z)]
                normals += [Float(n.x), Float(n.y), Float(n.z)]
                let (u, v) = TorsoModel.texcoord(theta: TorsoModel.gridTheta(i), y: y)
                uvs += [Float(u), Float(v)]
            }
        }
        // Flat neck cap: the top row again with an upward normal, plus a centre vertex.
        let capStart = nt * ny
        for i in 0..<nt {
            let p = grid[(ny - 1) * nt + i]
            positions += [Float(p.x), Float(p.y), Float(p.z)]
            normals += [0, 1, 0]
            uvs += [Float(Double(i) / Double(nt)), 0]
        }
        positions += [0, Float(TorsoModel.yMax), 0]
        normals += [0, 1, 0]
        uvs += [0.5, 0]
        let capCentre = capStart + nt

        var body: [UInt32] = []
        body.reserveCapacity((ny - 1) * nt * 6)
        for j in 0..<(ny - 1) {
            for i in 0..<nt {
                let i1 = (i + 1) % nt
                let v00 = UInt32(j * nt + i), v10 = UInt32(j * nt + i1)
                let v01 = UInt32((j + 1) * nt + i), v11 = UInt32((j + 1) * nt + i1)
                body += [v00, v10, v11, v00, v11, v01]
            }
        }
        var cap: [UInt32] = []
        for i in 0..<nt {
            cap += [UInt32(capCentre), UInt32(capStart + i), UInt32(capStart + (i + 1) % nt)]
        }

        let vertexCount = positions.count / 3
        let posData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let nrmData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let f = MemoryLayout<Float>.size
        let sources = [
            SCNGeometrySource(data: posData, semantic: .vertex, vectorCount: vertexCount, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: f, dataOffset: 0, dataStride: 3 * f),
            SCNGeometrySource(data: nrmData, semantic: .normal, vectorCount: vertexCount, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: f, dataOffset: 0, dataStride: 3 * f),
            SCNGeometrySource(data: uvData, semantic: .texcoord, vectorCount: vertexCount, usesFloatComponents: true,
                              componentsPerVector: 2, bytesPerComponent: f, dataOffset: 0, dataStride: 2 * f),
        ]
        let elements = [SCNGeometryElement(indices: body, primitiveType: .triangles),
                        SCNGeometryElement(indices: cap, primitiveType: .triangles)]
        return SCNGeometry(sources: sources, elements: elements)
    }
}
