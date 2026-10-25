import Foundation

/// All hand-placed annotations for one image, in image pixel coordinates.
public struct LandmarkSet: Codable, Hashable, Sendable {
    public var points: [LandmarkType: Point2D]
    /// Patient-left breast contour as an ordered polyline in pixel coordinates.
    public var leftContour: [Point2D]
    /// Patient-right breast contour as an ordered polyline in pixel coordinates.
    public var rightContour: [Point2D]
    /// Width and height of the image the coordinates refer to.
    public var imageSize: Point2D

    public init(points: [LandmarkType: Point2D] = [:],
                leftContour: [Point2D] = [],
                rightContour: [Point2D] = [],
                imageSize: Point2D) {
        self.points = points
        self.leftContour = leftContour
        self.rightContour = rightContour
        self.imageSize = imageSize
    }

    /// Landmark types not yet placed, in declaration order.
    public var missing: [LandmarkType] {
        LandmarkType.allCases.filter { points[$0] == nil }
    }

    /// True when every point landmark is placed. Contours are optional.
    public var isComplete: Bool { missing.isEmpty }

    public subscript(type: LandmarkType) -> Point2D? {
        get { points[type] }
        set { points[type] = newValue }
    }
}
