import AVFoundation
import CoreVideo
import Foundation

enum TestVideo {
    static func make(
        seconds: Int, size: CGSize = CGSize(width: 1280, height: 720), fps: Int32 = 2,
        tagged: Bool = true
    ) async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "test-clip-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
            ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])

        if tagged {
            let location = AVMutableMetadataItem()
            location.identifier = .quickTimeMetadataLocationISO6709
            location.dataType = kCMMetadataDataType_QuickTimeMetadataLocation_ISO6709 as String
            location.value = "+51.5000-000.1200/" as NSString
            let make = AVMutableMetadataItem()
            make.identifier = .quickTimeMetadataMake
            make.dataType = kCMMetadataBaseDataType_UTF8 as String
            make.value = "TestCam" as NSString
            writer.metadata = [location, make]
        }

        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<Int(Int32(seconds) * fps) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(40 + (frame * 9) % 200), CVPixelBufferGetBytesPerRow(buffer) * Int(size.height))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }
}
