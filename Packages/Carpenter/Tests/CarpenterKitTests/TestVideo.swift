import AVFoundation
import CoreVideo
import Foundation

enum TestVideo {
    static func make(
        seconds: Int, size: CGSize = CGSize(width: 1280, height: 720), fps: Int32 = 2,
        tagged: Bool = true, noisy: Bool = false
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
                let length = CVPixelBufferGetBytesPerRow(buffer) * Int(size.height)
                if noisy {
                    var state = UInt64(frame + 1) &* 0x9E37_79B9_7F4A_7C15
                    let words = base.bindMemory(to: UInt64.self, capacity: length / 8)
                    for index in 0..<(length / 8) {
                        state ^= state << 13
                        state ^= state >> 7
                        state ^= state << 17
                        words[index] = state
                    }
                } else {
                    memset(base, Int32(40 + (frame * 9) % 200), length)
                }
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
