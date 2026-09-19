import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 4, let px = Int(args[3]) else {
    FileHandle.standardError.write(Data("usage: render-icon in.svg out.png px [hex|none] [gray] [opaque]\n".utf8))
    exit(2)
}
guard let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write(Data("cannot load \(args[1])\n".utf8))
    exit(1)
}
image.size = NSSize(width: px, height: px)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: px, height: px)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let bounds = NSRect(x: 0, y: 0, width: px, height: px)

if args.count > 4, args[4] != "none" {
    let hex = UInt32(args[4].replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    ).setFill()
    bounds.fill()
}
image.draw(in: bounds)
NSGraphicsContext.restoreGraphicsState()

var output = rep
if args.dropFirst(4).contains("gray") {
    let ci = CIImage(bitmapImageRep: rep)!
    let mono = ci.applyingFilter("CIPhotoEffectMono")
    let context = CIContext()
    let cg = context.createCGImage(mono, from: mono.extent)!
    output = NSBitmapImageRep(cgImage: cg)
}
if args.dropFirst(4).contains("opaque"), let drawn = output.cgImage {
    let flat = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    flat.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    flat.fill(CGRect(x: 0, y: 0, width: px, height: px))
    flat.draw(drawn, in: CGRect(x: 0, y: 0, width: px, height: px))
    output = NSBitmapImageRep(cgImage: flat.makeImage()!)
}
try output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
