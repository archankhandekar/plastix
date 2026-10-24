import Foundation

/// A small 8-bit greyscale image. The app downsamples each capture to a few hundred
/// pixels on a side before quality checks, so these routines stay cheap and the core
/// never touches platform image types.
public struct LuminanceImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Row-major luminance values, `width * height` entries.
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixel count must equal width * height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public var isEmpty: Bool { width == 0 || height == 0 }

    @inlinable public subscript(x: Int, y: Int) -> UInt8 { pixels[y * width + x] }
}
