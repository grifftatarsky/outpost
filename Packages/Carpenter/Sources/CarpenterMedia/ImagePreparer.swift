import CarpenterKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImagePreparer {
    public static let longestEdge = 2048
    public static let previewLongestEdge = 40
    public static let quality = 0.82
    public static let previewQuality = 0.5

    public enum Failure: Error, Hashable, Sendable {
        case undecodable
        case unencodable
    }

    public static func prepare(_ original: Data, caption: String? = nil) throws -> PreparedMedia {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil) else {
            throw Failure.undecodable
        }
        let image = try redrawn(try scaled(source, to: longestEdge))
        let bytes = try jpeg(image, quality: quality)

        let preview = try? jpeg(
            try redrawn(try scaled(source, to: previewLongestEdge)), quality: previewQuality)
        return PreparedMedia(
            kind: .image,
            width: image.width,
            height: image.height,
            bytes: bytes,
            preview: preview.flatMap { $0.count <= MediaBody.previewByteCap ? $0 : nil },
            caption: caption)
    }

    static func scaled(_ source: CGImageSource, to edge: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw Failure.undecodable }
        return image
    }

    static func redrawn(_ image: CGImage) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw Failure.unencodable }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let clean = context.makeImage() else { throw Failure.unencodable }
        return clean
    }

    public static func avatar(_ data: Data, edge: Int = 320, crop: AvatarCrop? = nil) throws -> Data {
        let scaled = try thumbnail(data, edge: decodeEdge(for: edge, crop: crop))
        let square =
            crop?.pixels(inWidth: scaled.width, height: scaled.height) ?? centredSquare(in: scaled)
        guard let cropped = scaled.cropping(to: square) else { throw Failure.undecodable }
        let sized = try Self.scaled(redrawn(cropped), to: edge)
        return try jpeg(sized, quality: 0.85)
    }

    public static func decodeEdge(for edge: Int, crop: AvatarCrop?) -> Int {
        guard let crop else { return edge * 2 }
        let fraction = min(1, max(0.05, crop.shortestSide))
        return min(4096, Int((Double(edge * 2) / fraction).rounded()))
    }

    static func centredSquare(in image: CGImage) -> CGRect {
        let side = min(image.width, image.height)
        return CGRect(
            x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
    }

    public static func thumbnail(_ data: Data, edge: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Failure.undecodable
        }
        return try scaled(source, to: edge)
    }

    static func scaled(_ image: CGImage, to edge: Int) throws -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > edge else { return try redrawn(image) }
        let factor = Double(edge) / Double(longest)
        let width = max(1, Int((Double(image.width) * factor).rounded()))
        let height = max(1, Int((Double(image.height) * factor).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw Failure.unencodable }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let clean = context.makeImage() else { throw Failure.unencodable }
        return clean
    }

    static func jpeg(_ image: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure.unencodable }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unencodable }
        return output as Data
    }

    public static func metadataKeys(of data: Data) -> Set<String> {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [] }
        return Set(properties.keys.filter { $0.hasPrefix("{") })
    }

    static let harmlessExif: Set<String> = [
        kCGImagePropertyExifColorSpace as String,
        kCGImagePropertyExifPixelXDimension as String,
        kCGImagePropertyExifPixelYDimension as String,
    ]

    public static func identifyingMetadata(of data: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [] }
        var found: [String] = []
        for block in ["{GPS}", "{TIFF}", "{IPTC}"] {
            if let dictionary = properties[block] as? [String: Any] {
                found += dictionary.keys.map { "\(block).\($0)" }
            }
        }
        if let exif = properties["{Exif}"] as? [String: Any] {
            found += exif.keys.filter { !harmlessExif.contains($0) }.map { "{Exif}.\($0)" }
        }
        return found.sorted()
    }

    public static func size(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
            let height = properties[kCGImagePropertyPixelHeight as String] as? Int
        else { return nil }
        return (width, height)
    }
}
