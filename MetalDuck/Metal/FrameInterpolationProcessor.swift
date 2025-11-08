//
//  FrameInterpolationProcessor.swift
//  MetalDuck
//
//  Adapted from Apple's LowLatencyFrameInterpolation sample
//

import Foundation
import CoreVideo
import AVFoundation
@preconcurrency import VideoToolbox

/// Actor-based frame interpolation processor (exactly like Apple's LowLatencyFrameInterpolation)
/// This ensures all processor access is serialized, preventing initialization issues
@available(macOS 14.0, *)
actor FrameInterpolationProcessor {
    
    let numFrames: Int
    let inputDimensions: CMVideoDimensions
    
    let configuration: VTLowLatencyFrameInterpolationConfiguration
    let pixelBufferPool: CVPixelBufferPool
    nonisolated(unsafe) let frameProcessor = VTFrameProcessor()
    
    private var sessionStarted = false
    private var previousFrame: (buffer: CVPixelBuffer, timestamp: CMTime)?
    
    init(numFrames: Int, inputDimensions: CMVideoDimensions) throws {
        self.numFrames = min(3, numFrames) // Apple limits to max 3 frames
        self.inputDimensions = inputDimensions
        
        let width = Int(inputDimensions.width)
        let height = Int(inputDimensions.height)
        
        guard VTLowLatencyFrameInterpolationConfiguration.isSupported else {
            throw FrameInterpolationError.unsupportedProcessor
        }
        
        guard let configuration = VTLowLatencyFrameInterpolationConfiguration(
            frameWidth: width,
            frameHeight: height,
            numberOfInterpolatedFrames: self.numFrames
        ) else {
            throw FrameInterpolationError.failedToCreateConfiguration
        }
        self.configuration = configuration
        
        let destinationPixelBufferAttributes = configuration.destinationPixelBufferAttributes
        self.pixelBufferPool = try Self.createPixelBufferPool(for: destinationPixelBufferAttributes)
    }
    
    /// Start the processing session (exactly as Apple's run() method)
    func startSession() throws {
        guard !sessionStarted else { return }
        
        // The processor may not be ready immediately after calling `startSession` due to model loading.
        // In real-time scenarios, avoid blocking critical tasks during `startSession` because
        // it may cause dropped or delayed frames.
        try frameProcessor.startSession(configuration: configuration)
        sessionStarted = true
        print("   ✅ Frame Interpolation session started")
    }
    
    /// End the processing session
    func endSession() {
        guard sessionStarted else { return }
        frameProcessor.endSession()
        sessionStarted = false
        previousFrame = nil
        print("   ✅ Frame Interpolation session ended")
    }
    
    /// Process a frame pair (adapted from Apple's interpolate method)
    /// Returns the first interpolated frame via completion handler
    func processFrame(
        currentBuffer: CVPixelBuffer,
        currentTimestamp: CMTime,
        completion: @escaping ([CVPixelBuffer]) -> Void
    ) async throws {
        guard sessionStarted else {
            throw FrameInterpolationError.sessionNotStarted
        }
        
        // Need previous frame for interpolation
        guard let previous = previousFrame else {
            // Store current frame as previous for next call
            previousFrame = (buffer: currentBuffer, timestamp: currentTimestamp)
            // Return current frame (can't interpolate without previous) as an array
            completion([currentBuffer])
            return
        }
        
        // Create source frames (exactly as Apple example)
        guard let sourceFrame = VTFrameProcessorFrame(buffer: previous.buffer, presentationTimeStamp: previous.timestamp),
              let nextFrame = VTFrameProcessorFrame(buffer: currentBuffer, presentationTimeStamp: currentTimestamp)
        else {
            throw FrameInterpolationError.failedToCreateFrames
        }
        
        // Calculate interpolation intervals (exactly as Apple example)
        let intervals = interpolationIntervals()
        let destinationFrames = try framesBetween(
            firstPTS: previous.timestamp,
            lastPTS: currentTimestamp,
            interpolationIntervals: intervals
        )
        
        let intervalArray = intervals.map { Float($0) }
        
        guard let parameters = VTLowLatencyFrameInterpolationParameters(
            sourceFrame: nextFrame,
            previousFrame: sourceFrame,
            interpolationPhase: intervalArray,
            destinationFrames: destinationFrames
        ) else {
            throw FrameInterpolationError.failedToCreateParameters
        }
        
        // Process interpolated frames (with retries on initialization failure)
        var outputs: [CVPixelBuffer] = []
        let maxRetries = 6
        var attempt = 0
        var processed = false

        while !processed && attempt < maxRetries {
            attempt += 1
            do {
                for try await readOnlyFrame in frameProcessor.process(parameters: parameters) {
                    // Extract pixel buffer from read-only frame (exactly as Apple example)
                    let processedBuffer = try readOnlyFrame.frame.withUnsafeBuffer { readOnlyPixelBuffer -> CVPixelBuffer in
                        // Create a writable copy
                        let width = CVPixelBufferGetWidth(readOnlyPixelBuffer)
                        let height = CVPixelBufferGetHeight(readOnlyPixelBuffer)
                        let format = CVPixelBufferGetPixelFormatType(readOnlyPixelBuffer)

                        var outputBuffer: CVPixelBuffer?
                        let attributes: [CFString: Any] = [
                            kCVPixelBufferWidthKey: width,
                            kCVPixelBufferHeightKey: height,
                            kCVPixelBufferPixelFormatTypeKey: format,
                            kCVPixelBufferIOSurfacePropertiesKey: [:]
                        ]

                        guard CVPixelBufferCreate(kCFAllocatorDefault,
                                                 width,
                                                 height,
                                                 format,
                                                 attributes as CFDictionary,
                                                 &outputBuffer) == kCVReturnSuccess,
                              let output = outputBuffer else {
                            throw FrameInterpolationError.failedToCreateOutputBuffer
                        }

                        // Copy using VTPixelTransferSession
                        var transferSession: VTPixelTransferSession?
                        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                                       pixelTransferSessionOut: &transferSession) == noErr,
                           let session = transferSession {
                            let status = VTPixelTransferSessionTransferImage(session,
                                                                           from: readOnlyPixelBuffer,
                                                                           to: output)
                            VTPixelTransferSessionInvalidate(session)
                            guard status == noErr else {
                                throw FrameInterpolationError.failedToTransferImage
                            }
                        }

                        return output
                    }

                    // Convert YUV to BGRA if needed
                    var finalOutput = processedBuffer
                    let outputFormat = CVPixelBufferGetPixelFormatType(processedBuffer)
                    if outputFormat != kCVPixelFormatType_32BGRA {
                        let outputWidth = CVPixelBufferGetWidth(processedBuffer)
                        let outputHeight = CVPixelBufferGetHeight(processedBuffer)
                        var bgraBuffer: CVPixelBuffer?
                        let bgraAttributes: [CFString: Any] = [
                            kCVPixelBufferWidthKey: outputWidth,
                            kCVPixelBufferHeightKey: outputHeight,
                            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                            kCVPixelBufferIOSurfacePropertiesKey: [:]
                        ]

                        if CVPixelBufferCreate(kCFAllocatorDefault,
                                             outputWidth,
                                             outputHeight,
                                             kCVPixelFormatType_32BGRA,
                                             bgraAttributes as CFDictionary,
                                             &bgraBuffer) == kCVReturnSuccess,
                           let bgra = bgraBuffer {
                            var transferSession: VTPixelTransferSession?
                            if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                                           pixelTransferSessionOut: &transferSession) == noErr,
                               let session = transferSession {
                                if VTPixelTransferSessionTransferImage(session,
                                                                       from: processedBuffer,
                                                                       to: bgra) == noErr {
                                    finalOutput = bgra
                                }
                                VTPixelTransferSessionInvalidate(session)
                            }
                        }
                    }

                    outputs.append(finalOutput)
                    // For our integration we collect all interpolated frames and return them
                    processed = true
                }
                // if we got here without throwing, processing succeeded (or yielded no frames)
                if processed { break }
            } catch {
                let ns = error as NSError
                // -12911 indicates initializationFailed / Processor not initialized
                if ns.domain == "com.apple.VideoProcessing" && ns.code == -12911 {
                    // attempt to (re)start session and back off
                    print("   ⚠️ FrameProcessor not initialized (attempt \(attempt)), restarting session and retrying...")
                    try? frameProcessor.startSession(configuration: configuration)
                    // Exponential backoff
                    let backoffMs = 200 * attempt
                    try? await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                    continue
                }
                // non-recoverable, rethrow up to caller
                throw error
            }
        }
        
        // Update previous frame for next call
        previousFrame = (buffer: currentBuffer, timestamp: currentTimestamp)

        // If we didn't produce any interpolated frames, fall back to returning the current buffer
        if outputs.isEmpty {
            outputs.append(currentBuffer)
        }

        // Return result via completion (all interpolated frames)
        completion(outputs)
    }

    /// Warm up the processor by running two dummy frames through the pipeline.
    /// This helps ensure model loading completes before real frames arrive.
    func warmUp() async throws {
        // create two dummy pixel buffers from pool
        let buf1 = try Self.createPixelBuffer(from: pixelBufferPool)
        let buf2 = try Self.createPixelBuffer(from: pixelBufferPool)
        let now = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)

        // ensure session started
        if !sessionStarted {
            try frameProcessor.startSession(configuration: configuration)
            sessionStarted = true
        }

        // First call will store previousFrame inside actor
        try await processFrame(currentBuffer: buf1, currentTimestamp: now) { _ in }
        // Second call should trigger processing and model initialization
        try await processFrame(currentBuffer: buf2, currentTimestamp: CMTimeAdd(now, CMTime(value: 1, timescale: 600))) { _ in }
    }
    
    // MARK: - Private Helpers (exactly as Apple example)
    
    private func interpolationIntervals() -> [Double] {
        let interpolationInterval = 1.0 / (Double(numFrames) + 1)
        return Array(stride(from: interpolationInterval, through: 1.0, by: interpolationInterval).dropLast())
    }
    
    private func framesBetween(firstPTS: CMTime, lastPTS: CMTime,
                               interpolationIntervals: [Double]) throws -> [VTFrameProcessorFrame] {
        let ptsRange = Double(CMTimeGetSeconds(lastPTS) - CMTimeGetSeconds(firstPTS))
        let ptsScale = lastPTS.timescale
        
        var interpolationFrames: [VTFrameProcessorFrame] = []
        
        // Calculate the expected `pts` based on the interpolation intervals
        for interpolationInterval in interpolationIntervals {
            let ptsValue = ptsRange * interpolationInterval
            let pts = CMTime(seconds: ptsValue + CMTimeGetSeconds(firstPTS), preferredTimescale: ptsScale)
            let pixelBuffer = try Self.createPixelBuffer(from: pixelBufferPool)
            guard let interpolationFrame = VTFrameProcessorFrame(buffer: pixelBuffer, presentationTimeStamp: pts) else {
                throw FrameInterpolationError.failedToCreateFrames
            }
            interpolationFrames.append(interpolationFrame)
        }
        return interpolationFrames
    }
    
    // MARK: - Static Helpers (from Apple's example)
    
    private static func createPixelBufferPool(for attributes: [String: Any]) throws -> CVPixelBufferPool {
        var pixelBufferPool: CVPixelBufferPool?
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as NSDictionary?,
            attributes as NSDictionary?,
            &pixelBufferPool
        )
        
        guard status == kCVReturnSuccess, let pool = pixelBufferPool else {
            throw FrameInterpolationError.failedToCreatePixelBufferPool
        }
        
        return pool
    }
    
    private static func createPixelBuffer(from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw FrameInterpolationError.failedToCreatePixelBuffer
        }
        
        return buffer
    }
}

// MARK: - Errors

@available(macOS 14.0, *)
enum FrameInterpolationError: Error {
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

