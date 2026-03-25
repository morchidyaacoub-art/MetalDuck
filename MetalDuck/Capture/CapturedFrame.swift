//
//  CapturedFrame.swift
//  MetalDuck
//
//  Value type for captured screen content, replacing the CaptureDelegate protocol.
//

import Foundation
import CoreMedia
import CoreVideo
import IOSurface
import ScreenCaptureKit

struct CapturedFrame: @unchecked Sendable {
    let surface: IOSurface
    let pixelBuffer: CVPixelBuffer
    let presentationTimestamp: CMTime
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat

    var size: CGSize { contentRect.size }
}

@available(macOS 12.3, *)
extension CapturedFrame {
    /// Creates a CapturedFrame from a CMSampleBuffer produced by SCStream.
    /// Returns nil if the frame status is not `.complete` or required data is missing.
    static func from(sampleBuffer: CMSampleBuffer) -> CapturedFrame? {
        guard sampleBuffer.isValid else { return nil }

        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first
        else { return nil }

        guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue),
              status == .complete
        else { return nil }

        guard let pixelBuffer = sampleBuffer.imageBuffer else { return nil }

        guard let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }
        let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)

        guard let contentRectDict = attachments[.contentRect],
              let contentRect = CGRect(dictionaryRepresentation: contentRectDict as! CFDictionary),
              let contentScale = attachments[.contentScale] as? CGFloat,
              let scaleFactor = attachments[.scaleFactor] as? CGFloat
        else { return nil }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        return CapturedFrame(
            surface: surface,
            pixelBuffer: pixelBuffer,
            presentationTimestamp: timestamp,
            contentRect: contentRect,
            contentScale: contentScale,
            scaleFactor: scaleFactor
        )
    }
}
