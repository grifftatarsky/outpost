import CarpenterKit
import CarpenterMedia
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@Suite("Preparing a photo to send")
struct ImagePreparerTests {
    private static func photo(width: Int, height: Int, tagged: Bool = true) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if tagged {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W",
            ]
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifLensModel: "test lens",
                kCGImagePropertyExifDateTimeOriginal: "2026:09:04 10:00:00",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("A large photo is scaled to the long edge and keeps its proportions")
    func scaled() throws {
        let prepared = try ImagePreparer.prepare(try Self.photo(width: 3000, height: 2000))
        #expect(prepared.width == 2048)
        #expect(prepared.height == 1365)
        #expect(ImagePreparer.size(of: prepared.bytes)?.width == 2048, "the bytes disagree with the declared size")
        #expect(prepared.kind == .image)
    }

    @Test("A small photo is not made larger")
    func notUpscaled() throws {
        let prepared = try ImagePreparer.prepare(try Self.photo(width: 100, height: 80))
        #expect(prepared.width == 100 && prepared.height == 80)
    }

    @Test("Location, camera and time are stripped")
    func metadataIsStripped() throws {
        let original = try Self.photo(width: 800, height: 600)
        let before = ImagePreparer.identifyingMetadata(of: original)
        try #require(
            before.contains("{GPS}.Latitude") && before.contains("{Exif}.LensModel"),
            "the fixture carries no identifying tags, so this test proves nothing: \(before)")

        let prepared = try ImagePreparer.prepare(original)

        #expect(ImagePreparer.identifyingMetadata(of: prepared.bytes).isEmpty,
            "identifying metadata survived: \(ImagePreparer.identifyingMetadata(of: prepared.bytes))")
        if let preview = prepared.preview {
            #expect(ImagePreparer.identifyingMetadata(of: preview).isEmpty)
        }
    }

    @Test("The preview fits the entry and is tiny")
    func previewFits() throws {
        let prepared = try ImagePreparer.prepare(try Self.photo(width: 3000, height: 2000))
        let preview = try #require(prepared.preview)
        #expect(preview.count <= MediaBody.previewByteCap)
        let size = try #require(ImagePreparer.size(of: preview))
        #expect(max(size.width, size.height) <= ImagePreparer.previewLongestEdge)
    }

    @Test("Something that is not an image is refused, not sent")
    func garbageIsRefused() {
        #expect(throws: ImagePreparer.Failure.undecodable) {
            try ImagePreparer.prepare(Data("not a photo".utf8))
        }
    }

    @Test("A caption rides along")
    func caption() throws {
        let prepared = try ImagePreparer.prepare(try Self.photo(width: 10, height: 10), caption: "hi")
        #expect(prepared.caption == "hi")
    }
}

@Suite("Cropping a picked avatar")
struct AvatarCropTests {
    private static func landmarked(
        width: Int = 800, height: Int = 800, corner: (x: Int, y: Int)
    ) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(
            CGRect(
                x: corner.x * width / 2, y: (1 - corner.y) * height / 2,
                width: width / 2, height: height / 2))
        let image = try #require(context.makeImage())

        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private static func middleIsRed(_ jpeg: Data) throws -> Bool {
        let image = try ImagePreparer.thumbnail(jpeg, edge: 64)
        let space = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.draw(
                image,
                in: CGRect(
                    x: -Double(image.width) / 2 + 0.5, y: -Double(image.height) / 2 + 0.5,
                    width: Double(image.width), height: Double(image.height)))
        }
        return pixel[0] > 180 && pixel[1] < 90 && pixel[2] < 90
    }

    @Test("A crop over one corner comes back containing that corner")
    func cropLandsOnTheLandmark() throws {
        let topLeft = try Self.landmarked(corner: (x: 0, y: 0))
        let over = AvatarCrop(x: 0.05, y: 0.05, width: 0.4, height: 0.4)
        #expect(try Self.middleIsRed(try ImagePreparer.avatar(topLeft, crop: over)))

        let bottomRight = try Self.landmarked(corner: (x: 1, y: 1))
        #expect(try !Self.middleIsRed(try ImagePreparer.avatar(bottomRight, crop: over)))
        #expect(
            try Self.middleIsRed(
                try ImagePreparer.avatar(
                    bottomRight, crop: AvatarCrop(x: 0.55, y: 0.55, width: 0.4, height: 0.4))))
    }

    @Test("No crop is still the largest centred square")
    func noCropIsTheCentredSquare() throws {
        let wide = try Self.landmarked(width: 800, height: 400, corner: (x: 0, y: 0))
        let plain = try ImagePreparer.avatar(wide)
        let whole = try ImagePreparer.avatar(wide, crop: .whole)
        #expect(ImagePreparer.size(of: plain)?.width == ImagePreparer.size(of: plain)?.height)
        #expect(try !Self.middleIsRed(plain))
        #expect(try !Self.middleIsRed(whole))
    }

    @Test("A rectangle off the edge is brought back rather than refused")
    func nonsenseIsClamped() throws {
        let picture = try Self.landmarked(corner: (x: 0, y: 0))
        let escaping = AvatarCrop(x: -3, y: -3, width: 9, height: 9)
        #expect(throws: Never.self) { try ImagePreparer.avatar(picture, crop: escaping) }
        #expect(throws: Never.self) {
            try ImagePreparer.avatar(picture, crop: AvatarCrop(x: 2, y: 2, width: 0, height: 0))
        }
    }

    @Test("Zooming in decodes more of the original, not less")
    func zoomingDecodesEnough() {
        #expect(ImagePreparer.decodeEdge(for: 320, crop: nil) == 640)
        #expect(ImagePreparer.decodeEdge(for: 320, crop: .whole) == 640)
        #expect(ImagePreparer.decodeEdge(for: 320, crop: AvatarCrop(x: 0, y: 0, width: 0.25, height: 0.5)) == 2560)
        #expect(ImagePreparer.decodeEdge(for: 320, crop: AvatarCrop(x: 0, y: 0, width: 0.001, height: 0.001)) == 4096)
    }
}
