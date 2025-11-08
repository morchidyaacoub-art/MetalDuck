//
//  FrameConverter.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 08/11/25.
//
//  Utilities to bridge ScreenCaptureKit frame types to CVPixelBuffer and CMTime.
//

import Foundation
import CoreVideo
import CoreMedia
import IOSurface

enum FrameConverterError: Error {
    case failedToCreatePixelBufferFromIOSurface
}

struct FrameConverter {
    
    /// Creates a CVPixelBuffer that wraps the provided IOSurface.
    /// The returned pixel buffer references the IOSurface memory; no copy is performed.
    static func pixelBuffer(from surface: IOSurfaceRef,
                            pixelFormat: OSType = kCVPixelFormatType_32BGRA) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let options: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferPixelFormatTypeKey: pixelFormat
        ]
        let status = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault,
                                                      surface,
                                                      options as CFDictionary,
                                                      &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw FrameConverterError.failedToCreatePixelBufferFromIOSurface
        }
        return buffer
    }
    
    /// Creates a CMTime from a wall-clock date if presentation timestamps aren't available.
    /// Uses a fixed timescale of 600.
    static func cmTime(from date: Date) -> CMTime {
        CMTime(seconds: date.timeIntervalSince1970, preferredTimescale: 600)
    }
}


