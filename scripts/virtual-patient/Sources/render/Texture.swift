import CoreGraphics
import Foundation

/// Procedural textures. Everything is hash-based and seeded, so a run is deterministic.
enum Texture {
    static let size = 2048

    /// Grain amplitude as a fraction of luminance (plus or minus). Tuned with QualityCheck.
    static let grainAmplitude = 0.04
    /// Value-noise cell size on the body, metres. At about 2000 px per metre on the front
    /// of the torso this is about 12 px in the 1200 px image.
    static let grainCell = 0.006

    static let skin = RGB(0xCD, 0xB9, 0xA9)
    static let areola = RGB(0xA4, 0x84, 0x76)
    static let papilla = RGB(0x92, 0x70, 0x63)
    /// Blue-black skin-marker ink, so pen lines on the skin are never mistaken for the
    /// app's violet 'you marked this' ink.
    static let pen = RGB(0x1F, 0x2A, 0x44)
    /// A closed incision and its sutures.
    static let incision = RGB(0x7A, 0x55, 0x4C)
    static let suture = RGB(0x24, 0x2A, 0x36)
    /// The backdrop: a neutral dark charcoal, so the app's blue derived lines (#56B6D6)
    /// and violet marks read against it (about 6:1 for the blue).
    static let backdrop = RGB(0x23, 0x29, 0x2D)
    /// The hip drape: a darker surgical green, distinct from the backdrop.
    static let drape = RGB(0x2E, 0x55, 0x48)
    static let areolaRadius = 0.020

    struct RGB {
        let r: Double, g: Double, b: Double
        init(_ r: Int, _ g: Int, _ b: Int) { self.r = Double(r); self.g = Double(g); self.b = Double(b) }
        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
        func mixed(_ o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
        func scaled(_ k: Double) -> RGB { RGB(r: r * k, g: g * k, b: b * k) }
    }

    // MARK: - Noise

    @inline(__always) static func hash(_ x: Int64, _ y: Int64, _ z: Int64) -> Double {
        var h = UInt64(bitPattern: x) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: y) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= UInt64(bitPattern: z) &* 0x1656_67B1_9E37_79F9
        h ^= Stages.seed &* 0xD6E8_FEB8_6659_FD93
        // SplitMix64 finalizer.
        h = (h ^ (h >> 30)) &* 0xBF58_476D_1CE4_E5B9
        h = (h ^ (h >> 27)) &* 0x94D0_49BB_1331_11EB
        h ^= h >> 31
        return Double(h >> 11) / Double(1 << 53)
    }

    @inline(__always) static func fade(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    /// Trilinear value noise in [0, 1].
    static func valueNoise(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let fx = floor(x), fy = floor(y), fz = floor(z)
        let ix = Int64(fx), iy = Int64(fy), iz = Int64(fz)
        let tx = fade(x - fx), ty = fade(y - fy), tz = fade(z - fz)
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let c000 = hash(ix, iy, iz), c100 = hash(ix + 1, iy, iz)
        let c010 = hash(ix, iy + 1, iz), c110 = hash(ix + 1, iy + 1, iz)
        let c001 = hash(ix, iy, iz + 1), c101 = hash(ix + 1, iy, iz + 1)
        let c011 = hash(ix, iy + 1, iz + 1), c111 = hash(ix + 1, iy + 1, iz + 1)
        let x00 = lerp(c000, c100, tx), x10 = lerp(c010, c110, tx)
        let x01 = lerp(c001, c101, tx), x11 = lerp(c011, c111, tx)
        return lerp(lerp(x00, x10, ty), lerp(x01, x11, ty), tz)
    }

    // MARK: - Texel geometry

    /// Per-column sin/cos terms and per-row heights, shared by every stage.
    struct Layout {
        let theta: [Double]
        let sinTerm: [Double]
        let cosTerm: [Double]
        let y: [Double]
        let a: [Double]
        let b: [Double]

        init() {
            let n = Texture.size
            var theta = [Double](), s = [Double](), c = [Double](), ys = [Double](), a = [Double](), b = [Double]()
            for px in 0..<n {
                let u = (Double(px) + 0.5) / Double(n)
                let t = -Double.pi + 2 * Double.pi * u
                theta.append(t)
                s.append(TorsoModel.spow(sin(t)))
                c.append(TorsoModel.spow(cos(t)))
            }
            for py in 0..<n {
                let v = (Double(py) + 0.5) / Double(n)
                let y = TorsoModel.yMax - (TorsoModel.yMax - TorsoModel.yMin) * v
                ys.append(y)
                a.append(TorsoModel.halfWidth(y))
                b.append(TorsoModel.halfDepth(y))
            }
            self.theta = theta; sinTerm = s; cosTerm = c; y = ys; self.a = a; self.b = b
        }
    }

    /// Grain multiplier field (1 plus or minus the amplitude) on the base surface,
    /// identical for every stage.
    static func grainField(_ layout: Layout) -> [Float] {
        let n = size
        var out = [Float](repeating: 1, count: n * n)
        out.withUnsafeMutableBufferPointer { buf in
            for py in 0..<n {
                let y = layout.y[py], a = layout.a[py], b = layout.b[py]
                for px in 0..<n {
                    let x = a * layout.sinTerm[px], z = b * layout.cosTerm[px]
                    let g = valueNoise(x / grainCell, y / grainCell, z / grainCell) * 2 - 1
                    buf[py * n + px] = Float(1 + grainAmplitude * g)
                }
            }
        }
        return out
    }

    // MARK: - Skin

    @inline(__always) static func coverage(_ halfWidth: Double, _ dist: Double, _ aa: Double = 0.0006) -> Double {
        min(max((halfWidth - dist) / aa + 0.5, 0), 1)
    }

    /// Distance from (x, y) to the lower half of a mound's r = 1 boundary, metres.
    static func foldDistance(_ p: MoundParams, side s: Double, x: Double, y: Double) -> Double {
        let cx = s * p.nippleX, cy = p.nippleY
        let ry = p.nippleY - p.foldY
        guard y < cy + 0.002 else { return .infinity }
        let u = (x - cx) / p.rx, v = min(0, (y - cy)) / ry
        let rho = (u * u + v * v).squareRoot()
        guard rho > 1e-9 else { return .infinity }
        let local = ((p.rx * u / rho) * (p.rx * u / rho) + (ry * v / rho) * (ry * v / rho)).squareRoot()
        return abs(rho - 1) * local
    }

    /// Distance from (x, y) to the closure line of a reduction on mound p (side s): a
    /// periareolar circle and a vertical limb from the areola down to just above the fold.
    /// Also returns whether the point sits on a suture (short ticks across the line).
    static func closureDistance(_ p: MoundParams, side s: Double, x: Double, y: Double) -> (line: Double, suture: Bool) {
        let cx = s * p.nippleX, cy = p.nippleY
        let dx = x - cx, dy = y - cy
        let d = (dx * dx + dy * dy).squareRoot()
        let ring = abs(d - areolaRadius)
        let top = cy - areolaRadius, bottom = p.foldY + 0.006
        var limb = Double.infinity
        if y <= top && y >= bottom { limb = abs(dx) } else if y > top { limb = .infinity }
        let pitch = 0.008, tickHalfWidth = 0.00035, tickHalfLength = 0.0017
        var suture = false
        if ring < tickHalfLength {
            let arc = (atan2(dy, dx) + Double.pi) * areolaRadius
            let ph = arc.truncatingRemainder(dividingBy: pitch)
            suture = min(ph, pitch - ph) < tickHalfWidth
        }
        if !suture && limb < tickHalfLength {
            let ph = (top - y).truncatingRemainder(dividingBy: pitch)
            suture = min(ph, pitch - ph) < tickHalfWidth
        }
        return (min(ring, limb), suture)
    }

    /// The plain grained clay, for the arms (no features).
    static func clayImage(layout: Layout, grain: [Float]) -> CGImage {
        let n = size
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            let c = skin.scaled(Double(grain[i]))
            bytes[i * 4] = UInt8(max(0, min(255, c.r.rounded())))
            bytes[i * 4 + 1] = UInt8(max(0, min(255, c.g.rounded())))
            bytes[i * 4 + 2] = UInt8(max(0, min(255, c.b.rounded())))
        }
        return makeImage(bytes, width: n, height: n)
    }

    /// The diffuse texture for one stage: grained clay, nipple-areola complexes at the
    /// apexes, on stage 1 blue-black preoperative pen lines, and after resection the
    /// closed reduction incision on the patient-left breast.
    static func skinImage(model: TorsoModel, penMarks: Bool, closureLines: Bool, layout: Layout, grain: [Float]) -> CGImage {
        let n = size
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        let sides: [(Double, MoundParams)] = [(1, model.left), (-1, model.right)]
        bytes.withUnsafeMutableBufferPointer { out in
            for py in 0..<n {
                let y = layout.y[py], a = layout.a[py]
                for px in 0..<n {
                    var c = skin
                    let theta = layout.theta[px]
                    if cos(theta) > 0 {
                        let x = a * layout.sinTerm[px]
                        for (s, p) in sides {
                            let d = ((x - s * p.nippleX) * (x - s * p.nippleX) + (y - p.nippleY) * (y - p.nippleY)).squareRoot()
                            // A soft-edged areola that deepens slightly toward the centre,
                            // and a darker papilla.
                            let k = coverage(areolaRadius, d, 0.003)
                            if k > 0 { c = c.mixed(areola.scaled(1.0 - 0.05 * max(0, 1 - d / areolaRadius)), k) }
                            let kp = coverage(TorsoModel.papillaRadius * 0.9, d, 0.0015)
                            if kp > 0 { c = c.mixed(papilla, kp) }
                        }
                        if closureLines {
                            let cl = closureDistance(model.left, side: 1, x: x, y: y)
                            let line = coverage(0.0007, cl.line, 0.0006)
                            if line > 0 { c = c.mixed(incision, line * 0.75) }
                            if cl.suture { c = c.mixed(suture, 0.55) }
                        }
                    }
                    c = c.scaled(Double(grain[py * n + px]))
                    if penMarks && cos(theta) > 0 {
                        let x = a * layout.sinTerm[px]
                        var ink = 0.0
                        // Dashed midline from the notch to the umbilicus.
                        if y <= 0 && y >= TorsoModel.umbilicusY {
                            let phase = (-y).truncatingRemainder(dividingBy: 0.013)
                            if phase < 0.008 { ink = max(ink, coverage(0.0012, abs(x))) }
                        }
                        for (s, p) in sides { ink = max(ink, coverage(0.0010, foldDistance(p, side: s, x: x, y: y))) }
                        if ink > 0 { c = c.mixed(pen, ink * 0.92) }
                    }
                    let o = (py * n + px) * 4
                    out[o] = UInt8(max(0, min(255, c.r.rounded())))
                    out[o + 1] = UInt8(max(0, min(255, c.g.rounded())))
                    out[o + 2] = UInt8(max(0, min(255, c.b.rounded())))
                    out[o + 3] = 255
                }
            }
        }
        return makeImage(bytes, width: n, height: n)
    }

    // MARK: - Drape

    /// Cloth modulation (plus or minus) of the hip drape: a faint, soft value noise, so
    /// the sheet reads as matte cloth without the stripes a fine weave aliases into.
    static let weaveAmplitude = 0.025
    /// Noise cell of the drape cloth, texels of the 256 px tile.
    static let weaveCell = 16

    /// A 256 x 256 tileable tile of soft cloth noise on the drape green.
    static func drapeTile() -> CGImage {
        let n = 256, period = n / weaveCell
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                // Value noise wrapped on the tile period, so the tile repeats seamlessly.
                let fx = Double(x) / Double(weaveCell), fy = Double(y) / Double(weaveCell)
                let ix = Int(fx), iy = Int(fy)
                let tx = fade(fx - Double(ix)), ty = fade(fy - Double(iy))
                func h(_ a: Int, _ b: Int) -> Double { hash(Int64(a % period), Int64(b % period), 7) }
                let top = h(ix, iy) + (h(ix + 1, iy) - h(ix, iy)) * tx
                let bottom = h(ix, iy + 1) + (h(ix + 1, iy + 1) - h(ix, iy + 1)) * tx
                let g = (top + (bottom - top) * ty) * 2 - 1
                let c = drape.scaled(1 + weaveAmplitude * g)
                let o = (y * n + x) * 4
                bytes[o] = UInt8(max(0, min(255, c.r.rounded())))
                bytes[o + 1] = UInt8(max(0, min(255, c.g.rounded())))
                bytes[o + 2] = UInt8(max(0, min(255, c.b.rounded())))
            }
        }
        return makeImage(bytes, width: n, height: n)
    }

    static func makeImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage {
        let data = Data(bytes) as CFData
        let provider = CGDataProvider(data: data)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
}
