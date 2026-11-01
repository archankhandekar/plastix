import Foundation

/// Rasterized polygon overlap. Polygons are closed implicitly (last point joins first)
/// and filled with the even-odd rule, so concave contours are handled.
public enum PolygonRaster {
    /// Dice coefficient 2|A∩B| / (|A| + |B|) of two polygons rasterized on a
    /// `gridSize` × `gridSize` grid spanning `bounds`. Returns 0 when either polygon has
    /// fewer than three points or no area on the grid.
    public static func dice(_ a: [Point2D], _ b: [Point2D], gridSize: Int, bounds: (min: Point2D, max: Point2D)) -> Double {
        guard gridSize > 0, a.count >= 3, b.count >= 3 else { return 0 }
        let maskA = rasterize(a, gridSize: gridSize, bounds: bounds)
        let maskB = rasterize(b, gridSize: gridSize, bounds: bounds)
        var areaA = 0, areaB = 0, both = 0
        for i in 0..<maskA.count {
            if maskA[i] { areaA += 1 }
            if maskB[i] { areaB += 1 }
            if maskA[i] && maskB[i] { both += 1 }
        }
        guard areaA + areaB > 0 else { return 0 }
        return 2.0 * Double(both) / Double(areaA + areaB)
    }

    /// Even-odd fill mask, row-major, sampled at cell centres.
    static func rasterize(_ polygon: [Point2D], gridSize: Int, bounds: (min: Point2D, max: Point2D)) -> [Bool] {
        var mask = [Bool](repeating: false, count: gridSize * gridSize)
        let w = bounds.max.x - bounds.min.x
        let h = bounds.max.y - bounds.min.y
        guard w > 0, h > 0, polygon.count >= 3 else { return mask }
        let n = polygon.count
        for row in 0..<gridSize {
            let y = bounds.min.y + (Double(row) + 0.5) / Double(gridSize) * h
            // Collect x-crossings of the scanline with every edge.
            var crossings: [Double] = []
            for i in 0..<n {
                let p = polygon[i]
                let q = polygon[(i + 1) % n]
                if (p.y <= y && q.y > y) || (q.y <= y && p.y > y) {
                    let t = (y - p.y) / (q.y - p.y)
                    crossings.append(p.x + t * (q.x - p.x))
                }
            }
            guard !crossings.isEmpty else { continue }
            crossings.sort()
            var k = 0
            while k + 1 < crossings.count {
                let x0 = crossings[k], x1 = crossings[k + 1]
                let c0 = Int(((x0 - bounds.min.x) / w * Double(gridSize) - 0.5).rounded(.up))
                let c1 = Int(((x1 - bounds.min.x) / w * Double(gridSize) - 0.5).rounded(.down))
                if c1 >= c0 {
                    for col in max(c0, 0)...min(c1, gridSize - 1) {
                        mask[row * gridSize + col] = true
                    }
                }
                k += 2
            }
        }
        return mask
    }
}
