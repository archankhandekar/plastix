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
    static let areola = RGB(0xA8, 0x8E, 0x80)
    static let pen = RGB(0x4B, 0x2A, 0x7B)
    static let drape = RGB(0x2F, 0x6F, 0x73)
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

    /// The diffuse texture for one stage: grained clay, areolas at the apexes and, for
    /// stage 1 only, gentian-violet preoperative pen lines.
    static func skinImage(model: TorsoModel, penMarks: Bool, layout: Layout, grain: [Float]) -> CGImage {
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
                            let k = coverage(areolaRadius, d)
                            if k > 0 { c = c.mixed(areola, k) }
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

    /// Weave modulation (plus or minus) of the drape cloth.
    static let weaveAmplitude = 0.06
    /// One weave cell, texels; the tile holds 2 x 2 cells.
    static let weaveCell = 8

    /// A 16 x 16 tile of basket weave: 8 px cells alternating horizontal and vertical
    /// threads, two threads per cell, on #2F6F73.
    static func drapeTile() -> CGImage {
        let n = weaveCell * 2
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let horizontal = ((x / weaveCell) + (y / weaveCell)) % 2 == 0
                let along = Double(horizontal ? y : x) + 0.5
                let stripe = cos(2 * Double.pi * along / Double(weaveCell / 2))
                let c = drape.scaled(1 + weaveAmplitude * stripe)
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
