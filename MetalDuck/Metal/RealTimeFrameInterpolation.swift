//
//  RealTimeFrameInterpolation.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 08/11/25.
//
//  Real-time frame interpolation using VTLowLatencyFrameInterpolation.
//  This actor processes live CVPixelBuffer frames (previous + current)
//  and produces one or more interpolated frames between them.
//

import Foundation
import CoreVideo
import CoreMedia
import AVFoundation
@preconcurrency import VideoToolbox

@available(macOS 14.0, *)
actor RealTimeFrameInterpolation {
    
    // MARK: - Configuration
    
    let numFrames: Int
    let inputDimensions: CMVideoDimensions
    
    let configuration: VTLowLatencyFrameInterpolationConfiguration
    let pixelBufferPool: CVPixelBufferPool
    nonisolated(unsafe) let frameProcessor = VTFrameProcessor()
    
    // MARK: - State
    
    private var sessionStarted = false
    private var previousFrame: (buffer: CVPixelBuffer, timestamp: CMTime)?
    
    // MARK: - Init
    
    init(numFrames: Int, inputDimensions: CMVideoDimensions) throws {
        self.numFrames = min(3, numFrames) // Apple limits to max 3
        self.inputDimensions = inputDimensions
        
        let width = Int(inputDimensions.width)
        let height = Int(inputDimensions.height)
        
        guard VTLowLatencyFrameInterpolationConfiguration.isSupported else {
            throw Fault.unsupportedProcessor
        }
        
        guard let configuration = VTLowLatencyFrameInterpolationConfiguration(
            frameWidth: width,
            frameHeight: height,
            numberOfInterpolatedFrames: self.numFrames
        ) else {
            throw Fault.failedToCreateConfiguration
        }
        self.configuration = configuration
        
        let destinationPixelBufferAttributes = configuration.destinationPixelBufferAttributes
        self.pixelBufferPool = try Self.createPixelBufferPool(for: destinationPixelBufferAttributes)
    }
    
    // MARK: - Lifecycle
    
    func start() throws {
        guard !sessionStarted else { return }
        try frameProcessor.startSession(configuration: configuration)
        sessionStarted = true
    }
    
    func stop() {
        guard sessionStarted else { return }
        frameProcessor.endSession()
        sessionStarted = false
        previousFrame = nil
    }
    
    func warmUp() async throws {
        // Create two dummy buffers and process once to ensure models are loaded
        let buf1 = try Self.createPixelBuffer(from: pixelBufferPool)
        let buf2 = try Self.createPixelBuffer(from: pixelBufferPool)
        let now = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        
        if !sessionStarted {
            try start()
        }
        
        _ = try await process(currentBuffer: buf1, currentTimestamp: now)
        _ = try await process(currentBuffer: buf2, currentTimestamp: CMTimeAdd(now, CMTime(value: 1, timescale: 600))))
    }
    
    // MARK: - Processing
    
    /// Processes the current frame. Returns interpolated frames between the previous frame and this one.
    /// If there is no previous frame yet, returns the current frame for passthrough.
    func process(currentBuffer: CVPixelBuffer, currentTimestamp: CMTime) async throws -> [CVPixelBuffer] {
        guard sessionStarted else {
            throw Fault.sessionNotStarted
        }
        
        // Need previous frame for interpolation
        guard let previous = previousFrame else {
            previousFrame = (buffer: currentBuffer, timestamp: currentTimestamp)
            return [currentBuffer]
        }
        
        guard let sourceFrame = VTFrameProcessorFrame(buffer: previous.buffer, presentationTimeStamp: previous.timestamp),
              let nextFrame = VTFrameProcessorFrame(buffer: currentBuffer, presentationTimeStamp: currentTimestamp) else {
            throw Fault.failedToCreateFrames
        }
        
        let intervals = interpolationIntervals()
        let destinationFrames = try framesBetween(firstPTS: previous.timestamp,
                                                  lastPTS: currentTimestamp,
                                                  interpolationIntervals: intervals)
        
        let intervalArray = intervals.map { Float($0) }
        guard let parameters = VTLowLatencyFrameInterpolationParameters(
            sourceFrame: nextFrame,
            previousFrame: sourceFrame,
            interpolationPhase: intervalArray,
            destinationFrames: destinationFrames
        ) else {
            throw Fault.failedToCreateParameters
        }
        
        var outputs: [CVPixelBuffer] = []
        let maxRetries = 6
        var attempt = 0
        
        while attempt < maxRetries {
            attempt += 1
            do {
                for try await readOnlyFrame in frameProcessor.process(parameters: parameters) {
                    let processedBuffer = try readOnlyFrame.frame.withUnsafeBuffer { readOnlyPixelBuffer -> CVPixelBuffer in
                        // Copy to writable buffer via VTPixelTransfer
                        let width = CVPixelBufferGetWidth(readOnlyPixelBuffer)
                        let height = CVPixelBufferGetHeight(readOnlyPixelBuffer)
                        let format = CVPixelBufferGetPixelFormatType(readOnlyPixelBuffer)
                        
                        var outputBuffer: CVPixelBuffer?
                        let attrs: [CFString: Any] = [
                            kCVPixelBufferWidthKey: width,
                            kCVPixelBufferHeightKey: height,
                            kCVPixelBufferPixelFormatTypeKey: format,
                            kCVPixelBufferIOSurfacePropertiesKey: [:]
                        ]
                        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attrs as CFDictionary, &outputBuffer) == kCVReturnSuccess,
                              let output = outputBuffer else {
                            throw Fault.failedToCreateOutputBuffer
                        }
                        
                        var transferSession: VTPixelTransferSession?
                        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transferSession) == noErr,
                           let session = transferSession {
                            let status = VTPixelTransferSessionTransferImage(session, from: readOnlyPixelBuffer, to: output)
                            VTPixelTransferSessionInvalidate(session)
                            guard status == noErr else {
                                throw Fault.failedToTransferImage
                            }
                        }
                        return output
                    }
                    outputs.append(processedBuffer)
                }
                break
            } catch {
                let ns = error as NSError
                if ns.domain == "com.apple.VideoProcessing" && ns.code == -12911 {
                    // Initialization failed; attempt restart
                    try? frameProcessor.startSession(configuration: configuration)
                    try? await Task.sleep(nanoseconds: UInt64(200 * attempt) * 1_000_000)
                    continue
                } else {
                    throw error
                }
            }
        }
        
        // Update previous for next call
        previousFrame = (buffer: currentBuffer, timestamp: currentTimestamp)
        
        // Fallback to passthrough when no outputs produced
        if outputs.isEmpty {
            outputs.append(currentBuffer)
        }
        return outputs
    }
    
    // MARK: - Helpers
    
    private func interpolationIntervals() -> [Double] {
        let step = 1.0 / (Double(numFrames) + 1)
        return Array(stride(from: step, through: 1.0, by: step).dropLast())
    }
    
    private func framesBetween(firstPTS: CMTime,
                               lastPTS: CMTime,
                               interpolationIntervals: [Double]) throws -> [VTFrameProcessorFrame] {
        let ptsRange = Double(CMTimeGetSeconds(lastPTS) - CMTimeGetSeconds(firstPTS))
        let ptsScale = lastPTS.timescale
        
        var frames: [VTFrameProcessorFrame] = []
        for interval in interpolationIntervals {
            let ptsValue = ptsRange * interval
            let pts = CMTime(seconds: ptsValue + CMTimeGetSeconds(firstPTS), preferredTimescale: ptsScale)
            let pixelBuffer = try Self.createPixelBuffer(from: pixelBufferPool)
            guard let frame = VTFrameProcessorFrame(buffer: pixelBuffer, presentationTimeStamp: pts) else {
                throw Fault.failedToCreateFrames
            }
            frames.append(frame)
        }
        return frames
    }
}

// MARK: - Static helpers

@available(macOS 14.0, *)
extension RealTimeFrameInterpolation {
    private static func createPixelBufferPool(for attributes: [String: Any]) throws -> CVPixelBufferPool {
        var pool: CVPixelBufferPool?
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                             poolAttributes as NSDictionary?,
                                             attributes as NSDictionary?,
                                             &pool)
        guard status == kCVReturnSuccess, let pool else {
            throw Fault.failedToCreatePixelBufferPool
        }
        return pool
    }
    
    private static func createPixelBuffer(from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw Fault.failedToCreatePixelBuffer
        }
        return buffer
    }
}

// MARK: - Errors

@available(macOS 14.0, *)
enum Fault: Error {
    case unsupportedProcessor
    case failedToCreateConfiguration
    case sessionNotStarted
    case failedToCreateFrames
    case failedToCreateParameters
    case failedToCreateOutputBuffer
    case failedToTransferImage
    case failedToCreatePixelBufferPool
    case failedToCreatePixelBuffer
}


