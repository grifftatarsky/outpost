import CoreGraphics
import Foundation

public struct AvatarCrop: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let whole = AvatarCrop(x: 0, y: 0, width: 1, height: 1)

    public var shortestSide: Double { min(width, height) }

    public func pixels(inWidth imageWidth: Int, height imageHeight: Int) -> CGRect {
        let whole = CGRect(x: 0, y: 0, width: CGFloat(imageWidth), height: CGFloat(imageHeight))
        let asked = CGRect(
            x: CGFloat(x) * whole.width, y: CGFloat(y) * whole.height,
            width: CGFloat(width) * whole.width, height: CGFloat(height) * whole.height)
        let kept = asked.intersection(whole).integral
        guard !kept.isNull, kept.width >= 1, kept.height >= 1 else { return whole }
        return kept
    }
}

public struct PickedAvatar: Hashable, Sendable {
    public var data: Data
    public var crop: AvatarCrop

    public init(data: Data, crop: AvatarCrop = .whole) {
        self.data = data
        self.crop = crop
    }
}
