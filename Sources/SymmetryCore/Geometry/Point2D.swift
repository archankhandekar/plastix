import Foundation

/// A point or vector in image or normalized coordinates. Image coordinates follow the
/// usual convention: x grows to the right, y grows downward.
public struct Point2D: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)

    public static func + (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: Point2D, rhs: Double) -> Point2D {
        Point2D(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to other: Point2D) -> Double {
        (self - other).length
    }

    /// Rotates the point about the origin by `angle` radians (counter-clockwise in a
    /// y-up frame, which appears clockwise in a y-down image frame).
    public func rotated(by angle: Double) -> Point2D {
        let c = cos(angle)
        let s = sin(angle)
        return Point2D(x: x * c - y * s, y: x * s + y * c)
    }

    /// Reflects the point across the vertical line `x == axisX`.
    public func mirroredX(about axisX: Double) -> Point2D {
        Point2D(x: 2 * axisX - x, y: y)
    }
}
