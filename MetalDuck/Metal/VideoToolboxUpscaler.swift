//
//  VideoToolboxUpscaler.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import AVFoundation
import CoreVideo
import Foundation
import Metal
@preconcurrency import VideoToolbox

class VideoToolboxUpscaler {
    private let renderer: MetalRenderer
    private var transferSession: VTPixelTransferSession?
    private var settings: UpscaleSettings
    
    // Super-resolution scaler
    @available(macOS 14.0, *)
    private var superResolutionFrameProcessor: VTFrameProcessor?
    
    @available(macOS 14.0, *)
    private var superResolutionConfiguration: VTLowLatencySuperResolutionScalerConfiguration?
    
    @available(macOS 14.0, *)
    private var superResolutionPixelBufferPool: CVPixelBufferPool?
    
    @available(macOS 14.0, *)
    private var superResolutionSessionStarted = false
    
    // Frame interpolation - using actor-based processor (exactly like Apple's implementation)
    @available(macOS 14.0, *)
    private var frameInterpolationProcessor: FrameInterpolationProcessor?
    
    // Source frame rate (default to 30fps, can be updated)
    private var sourceFrameRate: Int = 30
    
    init(renderer: MetalRenderer, settings: UpscaleSettings) {
        self.renderer = renderer
        self.settings = settings
        setupTransferSession()
        if #available(macOS 14.0, *) {
            setupAdvancedFeatures()
        }
    }
    
    private func setupTransferSession() {
        var session: VTPixelTransferSession?
        let status = VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session)
        
        guard status == noErr, let transferSession = session else {
            print("Failed to create VTPixelTransferSession: \(status)")
            return
        }
        
        self.transferSession = transferSession
    }
    
    @available(macOS 14.0, *)
    private func setupAdvancedFeatures() {
        print("🎬 VideoToolboxUpscaler: Setting up advanced features")
        print("   Mode: \(settings.mode)")
        print("   Source Resolution: \(Int(settings.sourceResolution.width))x\(Int(settings.sourceResolution.height))")
        print("   Target Resolution: \(Int(settings.targetResolution.width))x\(Int(settings.targetResolution.height))")
        print("   Source Frame Rate: \(sourceFrameRate) fps")
        
        // Setup super-resolution scaler if enabled
        if settings.superResolutionEnabled || settings.mode == .superResolution {
            print("   ✅ Enabling Super Resolution")
            setupSuperResolutionScaler()
        }
        
        // Setup frame interpolation if enabled
        if settings.frameInterpolationEnabled || settings.mode == .frameInterpolation {
            let targetFPS = settings.targetFrameRate(sourceFrameRate: sourceFrameRate)
            print("   ✅ Enabling Frame Interpolation")
            print("      Multiplier: \(settings.interpolationMultiplier)x")
            print("      Target Frame Rate: \(targetFPS) fps")
            setupFrameInterpolation()
        }
    }
    
    @available(macOS 14.0, *)
    private func setupSuperResolutionScaler() {
        print("🔧 Setting up Super Resolution Scaler...")
        
        // Clean up existing session
        if superResolutionSessionStarted, let processor = superResolutionFrameProcessor {
            print("   Cleaning up existing session")
            processor.endSession()
            superResolutionSessionStarted = false
        }
        
        // Reset components
        superResolutionConfiguration = nil
        superResolutionPixelBufferPool = nil
        superResolutionFrameProcessor = nil
        
        // Create super-resolution scaler configuration
        let sourceWidth = Int(settings.sourceResolution.width)
        let sourceHeight = Int(settings.sourceResolution.height)
        let targetWidth = Int(settings.targetResolution.width)
        let targetHeight = Int(settings.targetResolution.height)
        
        print("   Source: \(sourceWidth)x\(sourceHeight)")
        print("   Target: \(targetWidth)x\(targetHeight)")
        print("   Quality: \(settings.superResolutionQuality)")
        
        let result = VideoToolboxAdvanced.createSuperResolutionScaler(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            quality: settings.superResolutionQuality
        )
        
        if let config = result.configuration, let pool = result.pixelBufferPool {
            print("   ✅ Super Resolution Scaler configured successfully")
            superResolutionConfiguration = config
            superResolutionPixelBufferPool = pool
            superResolutionFrameProcessor = VTFrameProcessor()
            print("   ✅ Processor created: \(superResolutionFrameProcessor != nil)")
            print("   ✅ Configuration set: \(superResolutionConfiguration != nil)")
            print("   ✅ Pixel buffer pool set: \(superResolutionPixelBufferPool != nil)")
        } else {
            print("   ❌ Failed to configure Super Resolution Scaler")
            print("   ❌ Configuration: \(result.configuration != nil ? "✅" : "❌")")
            print("   ❌ Pixel buffer pool: \(result.pixelBufferPool != nil ? "✅" : "❌")")
        }
    }
    
    @available(macOS 14.0, *)
    private func setupFrameInterpolation() {
        print("🔧 Setting up Frame Interpolation...")
        
        // Clean up existing processor (exactly as Apple example - end session before reconfiguring)
        Task {
            if let processor = await frameInterpolationProcessor {
                await processor.endSession()
            }
        }
        
        // Create frame interpolation processor (exactly like Apple's init)
        let sourceWidth = Int(settings.sourceResolution.width)
        let sourceHeight = Int(settings.sourceResolution.height)
        let targetFrameRate = settings.targetFrameRate(sourceFrameRate: sourceFrameRate)
        
        print("   Resolution: \(sourceWidth)x\(sourceHeight)")
        print("   Source FPS: \(sourceFrameRate)")
        print("   Target FPS: \(targetFrameRate) (multiplier: \(settings.interpolationMultiplier)x)")
        
        // Calculate number of interpolated frames (exactly as Apple)
        let frameRateRatio = Float(targetFrameRate) / Float(sourceFrameRate)
        let requestedFrames = max(1, Int(ceil(frameRateRatio)) - 1)
        let numFrames = min(3, requestedFrames) // Apple limits to max 3
        
        let inputDimensions = CMVideoDimensions(width: Int32(sourceWidth), height: Int32(sourceHeight))
        
        do {
            let processor = try FrameInterpolationProcessor(
                numFrames: numFrames,
                inputDimensions: inputDimensions
            )
            frameInterpolationProcessor = processor
            print("   ✅ Frame Interpolation processor created successfully")
            print("   📊 Number of interpolated frames: \(numFrames)")
            // Start the actor's session immediately so model initialization can occur
            Task {
                do {
                    try await processor.startSession()
                    print("   ✅ FrameInterpolationProcessor session started (setup)")
                    // Warm up the processor to avoid early visual artifacts
                    do {
                        try await processor.warmUp()
                        print("   ✅ FrameInterpolationProcessor warm-up complete")
                    } catch {
                        print("   ⚠️ FrameInterpolationProcessor warm-up failed: \(error)")
                    }
                } catch {
                    print("   ❌ Failed to start FrameInterpolationProcessor in setup: \(error)")
                    // Release the actor so a subsequent setup can retry
                    frameInterpolationProcessor = nil
                }
            }
        } catch {
            print("   ❌ Failed to create Frame Interpolation processor: \(error)")
            frameInterpolationProcessor = nil
        }
    }
    
    func updateSettings(_ newSettings: UpscaleSettings) {
        let oldMode = settings.mode
        let oldMultiplier = settings.interpolationMultiplier
        let oldSourceResolution = settings.sourceResolution
        let oldTargetResolution = settings.targetResolution
        settings = newSettings
        
        print("🔄 VideoToolboxUpscaler: Settings updated")
        print("   Mode: \(oldMode) → \(settings.mode)")
        print("   Super Resolution Enabled: \(settings.superResolutionEnabled)")
        
        let sourceResolutionChanged = oldSourceResolution.width != settings.sourceResolution.width ||
            oldSourceResolution.height != settings.sourceResolution.height
        let targetResolutionChanged = oldTargetResolution.width != settings.targetResolution.width ||
            oldTargetResolution.height != settings.targetResolution.height
        
        if sourceResolutionChanged {
            print("   Source Resolution: \(Int(oldSourceResolution.width))x\(Int(oldSourceResolution.height)) → \(Int(settings.sourceResolution.width))x\(Int(settings.sourceResolution.height))")
        }
        if targetResolutionChanged {
            print("   Target Resolution: \(Int(oldTargetResolution.width))x\(Int(oldTargetResolution.height)) → \(Int(settings.targetResolution.width))x\(Int(settings.targetResolution.height))")
        }
        
        if oldMultiplier != settings.interpolationMultiplier {
            print("   Interpolation Multiplier: \(oldMultiplier)x → \(settings.interpolationMultiplier)x")
        }
        
        if #available(macOS 14.0, *) {
            // Re-setup advanced features if settings changed
            // Re-setup super resolution if mode/enabled changed OR if source/target resolution changed
            if settings.superResolutionEnabled || settings.mode == .superResolution {
                if sourceResolutionChanged || targetResolutionChanged {
                    print("   ✅ Reconfiguring Super Resolution (source/target resolution changed)")
                } else {
                    print("   ✅ Setting up Super Resolution (mode: \(settings.mode), enabled: \(settings.superResolutionEnabled))")
                }
                setupSuperResolutionScaler()
            } else {
                print("   ⚠️  Not setting up Super Resolution (mode: \(settings.mode), enabled: \(settings.superResolutionEnabled))")
            }
            if settings.frameInterpolationEnabled || settings.mode == .frameInterpolation {
                setupFrameInterpolation()
            }
        } else {
            print("   ⚠️  macOS 14.0+ required for advanced features")
        }
    }
    
    /// Updates the source frame rate (from capture settings)
    func updateSourceFrameRate(_ frameRate: Int) {
        let oldFrameRate = sourceFrameRate
        sourceFrameRate = frameRate
        
        if oldFrameRate != frameRate {
            print("🔄 VideoToolboxUpscaler: Source frame rate updated: \(oldFrameRate) fps → \(frameRate) fps")
            
            // Re-setup frame interpolation if active, since it depends on source frame rate
            if #available(macOS 14.0, *) {
                if settings.frameInterpolationEnabled || settings.mode == .frameInterpolation {
                    print("   Reconfiguring Frame Interpolation with new source frame rate")
                    setupFrameInterpolation()
                }
            }
        }
    }
    
    /// Updates the source resolution from the actual pixel buffer dimensions
    func updateSourceResolution(from pixelBuffer: CVPixelBuffer) {
        let actualWidth = CVPixelBufferGetWidth(pixelBuffer)
        let actualHeight = CVPixelBufferGetHeight(pixelBuffer)
        let currentWidth = Int(settings.sourceResolution.width)
        let currentHeight = Int(settings.sourceResolution.height)
        
        if actualWidth != currentWidth || actualHeight != currentHeight {
            print("🔄 VideoToolboxUpscaler: Source resolution updated: \(currentWidth)x\(currentHeight) → \(actualWidth)x\(actualHeight)")
            settings.sourceResolution = CGSize(width: actualWidth, height: actualHeight)
            
            // Re-setup super resolution if active, since it depends on source resolution
            if #available(macOS 14.0, *) {
                if settings.superResolutionEnabled || settings.mode == .superResolution {
                    print("   Reconfiguring Super Resolution with new source resolution")
                    setupSuperResolutionScaler()
                }
            }
        }
    }
    
    // Frame processing counter for logging
    private var frameCount: Int = 0
    private var lastLogTime: Date = .init()
    
    func upscale(
        pixelBuffer: CVPixelBuffer,
        completion: @escaping (CVPixelBuffer?) -> Void
    ) {
        frameCount += 1
        let now = Date()
        
        // Update source resolution from actual pixel buffer dimensions (only on first frame or when changed)
        if frameCount == 1 || frameCount % 100 == 0 {
            updateSourceResolution(from: pixelBuffer)
        }
        
        // Log every 30 frames or every 1 second
        if frameCount % 30 == 0 || now.timeIntervalSince(lastLogTime) >= 1.0 {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            print("📹 Processing frame #\(frameCount) (\(width)x\(height)) - Mode: \(settings.mode)")
            lastLogTime = now
        }
        
        // Route to appropriate upscaling method based on mode
        switch settings.mode {
        case .superResolution:
            if #available(macOS 14.0, *) {
                upscaleWithSuperResolution(pixelBuffer: pixelBuffer, completion: completion)
            } else {
                print("   ⚠️  Super Resolution not available (requires macOS 14.0+), using fallback")
                fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
            }
        case .frameInterpolation:
            if #available(macOS 14.0, *) {
                interpolateFrames(pixelBuffer: pixelBuffer, completion: completion)
            } else {
                print("   ⚠️  Frame Interpolation not available (requires macOS 14.0+), using fallback")
                fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
            }
        case .temporal, .quality, .spatial:
            // Use traditional upscaling with optional enhancements
            if #available(macOS 14.0, *), settings.superResolutionEnabled {
                upscaleWithSuperResolution(pixelBuffer: pixelBuffer, completion: completion)
            } else {
                fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
            }
        }
    }
    
    @available(macOS 14.0, *)
    private func upscaleWithSuperResolution(
        pixelBuffer: CVPixelBuffer,
        completion: @escaping (CVPixelBuffer?) -> Void
    ) {
        guard let processor = superResolutionFrameProcessor,
              let configuration = superResolutionConfiguration,
              let pixelBufferPool = superResolutionPixelBufferPool
        else {
            // Log why we're falling back
            if superResolutionFrameProcessor == nil {
                print("   ⚠️  Super Resolution not configured: processor is nil")
            }
            if superResolutionConfiguration == nil {
                print("   ⚠️  Super Resolution not configured: configuration is nil")
            }
            if superResolutionPixelBufferPool == nil {
                print("   ⚠️  Super Resolution not configured: pixelBufferPool is nil")
            }
            print("   🔄 Falling back to traditional upscaling - Super Resolution setup may have failed")
            // Fallback to traditional scaling
            fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
            return
        }
        
        // Verify source dimensions match configuration (critical - must match exactly)
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let configWidth = Int(configuration.frameWidth)
        let configHeight = Int(configuration.frameHeight)
        
        if sourceWidth != configWidth || sourceHeight != configHeight {
            print("   ⚠️  Dimension mismatch! Source: \(sourceWidth)x\(sourceHeight), Config: \(configWidth)x\(configHeight)")
            print("   🔄 Updating source resolution and reconfiguring...")
            
            // End existing session
            if superResolutionSessionStarted {
                processor.endSession()
                superResolutionSessionStarted = false
            }
            
            // Update source resolution and reconfigure
            settings.sourceResolution = CGSize(width: sourceWidth, height: sourceHeight)
            setupSuperResolutionScaler()
            
            // Get updated components
            guard let newProcessor = superResolutionFrameProcessor,
                  let newConfig = superResolutionConfiguration,
                  let newPool = superResolutionPixelBufferPool
            else {
                print("   ❌ Failed to reconfigure, falling back")
                fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
                return
            }
            
            // Retry with new configuration
            return upscaleWithSuperResolution(pixelBuffer: pixelBuffer, completion: completion)
        }
        
        // Verify and convert source pixel buffer to match sourcePixelBufferAttributes (like Apple's VerifyBufferAttributes)
        let sourcePixelBufferAttributes = configuration.sourcePixelBufferAttributes
        var processedPixelBuffer = pixelBuffer
        
        // Check if source buffer matches required attributes
        if let receivedAttributes = CVPixelBufferCopyCreationAttributes(pixelBuffer) as? [String: Any] {
            let criticalKeys = [
                kCVPixelBufferExtendedPixelsLeftKey as String,
                kCVPixelBufferExtendedPixelsTopKey as String,
                kCVPixelBufferExtendedPixelsRightKey as String,
                kCVPixelBufferExtendedPixelsBottomKey as String
            ]
            
            var needsConversion = false
            for criticalKey in criticalKeys {
                if let desiredValue = sourcePixelBufferAttributes[criticalKey] as? Int {
                    let receivedValue = (receivedAttributes[criticalKey] as? Int) ?? 0
                    if receivedValue != desiredValue {
                        needsConversion = true
                        break
                    }
                }
            }
            
            // Convert if needed (like Apple's VerifyBufferAttributes)
            if needsConversion {
                var transferSession: VTPixelTransferSession?
                if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                                pixelTransferSessionOut: &transferSession) == noErr,
                    let transferSession = transferSession
                {
                    // Create compatible buffer from pool with source attributes
                    var conversionPool: CVPixelBufferPool?
                    let poolAttributes: [String: Any] = [
                        kCVPixelBufferPoolMinimumBufferCountKey as String: 1
                    ]
                    if CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                               poolAttributes as NSDictionary?,
                                               sourcePixelBufferAttributes as NSDictionary?,
                                               &conversionPool) == kCVReturnSuccess,
                        let pool = conversionPool
                    {
                        var convertedBuffer: CVPixelBuffer?
                        if CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &convertedBuffer) == kCVReturnSuccess,
                           let converted = convertedBuffer
                        {
                            if VTPixelTransferSessionTransferImage(transferSession,
                                                                   from: pixelBuffer,
                                                                   to: converted) == noErr
                            {
                                processedPixelBuffer = converted
                            }
                        }
                    }
                    VTPixelTransferSessionInvalidate(transferSession)
                }
            }
        }
        
        // Start session if not already started (exactly as Apple example - start once, keep open)
        if !superResolutionSessionStarted {
            print("   🚀 Starting Super Resolution session...")
            print("   📐 Configuration: \(configWidth)x\(configHeight)")
            print("   📐 Source: \(sourceWidth)x\(sourceHeight)")
            do {
                try processor.startSession(configuration: configuration)
                superResolutionSessionStarted = true
                print("   ✅ Super Resolution session started")
            } catch {
                print("   ❌ Failed to start super-resolution session: \(error)")
                fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
                return
            }
        }
        
        // Create timestamp (exactly as Apple example - use source PTS)
        let timestamp = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        
        // Create source frame using processed pixel buffer (exactly as Apple example)
        var sourceFrame: VTFrameProcessorFrame?
        sourceFrame = VTFrameProcessorFrame(buffer: processedPixelBuffer, presentationTimeStamp: timestamp)
        guard let sourceFrame else {
            print("   ❌ Failed to create source frame")
            fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
            return
        }
        
        // Create output pixel buffer from pool (exactly as Apple example)
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pixelBufferPool,
            &outputBuffer
        )
        guard let output = outputBuffer else {
            print("   ❌ Failed to create output pixel buffer from pool")
            fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
            return
        }
        
        // Propagate attachments BEFORE creating destination frame (exactly as Apple example)
        processedPixelBuffer.propagateAttachments(to: output)
        
        // Create destination frame with same timestamp as source (exactly as Apple example)
        guard let destinationFrame = VTFrameProcessorFrame(buffer: output, presentationTimeStamp: timestamp) else {
            print("   ❌ Failed to create destination frame")
            fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
            return
        }
        
        // Create parameters (exactly as Apple example)
        let parameters = VTLowLatencySuperResolutionScalerParameters(
            sourceFrame: sourceFrame,
            destinationFrame: destinationFrame
        )
        
        // Process asynchronously (exactly as Apple example)
        Task {
            do {
                let startTime = Date()
                try await processor.process(parameters: parameters)
                
                // Propagate attachments AFTER processing (exactly as Apple example)
                processedPixelBuffer.propagateAttachments(to: output)
                
                let duration = Date().timeIntervalSince(startTime) * 1000 // Convert to ms
                let outputWidth = CVPixelBufferGetWidth(output)
                let outputHeight = CVPixelBufferGetHeight(output)
                let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
                let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
                let outputFormat = CVPixelBufferGetPixelFormatType(output)
                let sourceFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
                print("   ✅ Super Resolution processed in \(String(format: "%.1f", duration))ms → \(sourceWidth)x\(sourceHeight) → \(outputWidth)x\(outputHeight)")
                print("   📊 Source format: \(sourceFormat), Output format: \(outputFormat)")
                print("   📊 Output buffer bytesPerRow: \(CVPixelBufferGetBytesPerRow(output)), height: \(CVPixelBufferGetHeight(output))")
                
                // Convert YUV output to BGRA if needed (super resolution outputs YUV format)
                var finalOutput = output
                if outputFormat != kCVPixelFormatType_32BGRA {
                    print("   🔄 Converting YUV output to BGRA format...")
                    // Create BGRA output buffer
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
                        let bgra = bgraBuffer
                    {
                        // Use transfer session to convert YUV to BGRA
                        var transferSession: VTPixelTransferSession?
                        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                                        pixelTransferSessionOut: &transferSession) == noErr,
                            let session = transferSession
                        {
                            if VTPixelTransferSessionTransferImage(session,
                                                                   from: output,
                                                                   to: bgra) == noErr
                            {
                                finalOutput = bgra
                                print("   ✅ Converted to BGRA successfully")
                            } else {
                                print("   ⚠️  Failed to convert YUV to BGRA, using original")
                            }
                            VTPixelTransferSessionInvalidate(session)
                        } else {
                            print("   ⚠️  Failed to create transfer session for conversion")
                        }
                    } else {
                        print("   ⚠️  Failed to create BGRA buffer for conversion")
                    }
                }
                
                await MainActor.run {
                    completion(finalOutput)
                }
            } catch {
                print("   ❌ Super-resolution processing failed: \(error.localizedDescription)")
                print("      Error code: \((error as NSError).code)")
                print("      Error domain: \((error as NSError).domain)")
                await MainActor.run {
                    fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
                }
            }
        }
    }
    
    @available(macOS 14.0, *)
    private func interpolateFrames(
        pixelBuffer: CVPixelBuffer,
        completion: @escaping (CVPixelBuffer?) -> Void
    ) {
        guard let processor = frameInterpolationProcessor else {
            // Fallback to traditional scaling
            fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
            return
        }
        
        // Create timestamp
        let currentTimestamp = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        
        // Process using actor-based processor (exactly like Apple's implementation)
        Task {
            do {
                // Process frame (actor ensures serialized access)
                try await processor.processFrame(
                    currentBuffer: pixelBuffer,
                    currentTimestamp: currentTimestamp
                ) { results in
                    if !results.isEmpty {
                        // Return each interpolated frame in sequence
                        for out in results {
                            completion(out)
                        }
                    } else {
                        // Fallback if no interpolated frame
                        self.fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
                    }
                }
            } catch {
                print("   ❌ Frame interpolation failed: \(error)")
                await MainActor.run {
                    fallbackUpscale(pixelBuffer: pixelBuffer, completion: completion)
                }
            }
        }
    }
    
    private var fallbackCount: Int = 0
    
    private func fallbackUpscale(
        pixelBuffer: CVPixelBuffer,
        completion: @escaping (CVPixelBuffer?) -> Void
    ) {
        fallbackCount += 1
        
        // Log every 30 frames to avoid spam
        if fallbackCount % 30 == 0 {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let targetWidth = Int(settings.targetResolution.width)
            let targetHeight = Int(settings.targetResolution.height)
            print("   🔄 Using fallback upscaling (frame #\(fallbackCount)): \(width)x\(height) → \(targetWidth)x\(targetHeight)")
        }
        
        // Create output pixel buffer
        guard let output = createOutputBuffer() else {
            if fallbackCount % 30 == 0 {
                print("   ❌ Failed to create output buffer for fallback upscaling")
            }
            completion(nil)
            return
        }
        
        // Use VTPixelTransferSession to scale
        if let session = transferSession {
            let transferStatus = VTPixelTransferSessionTransferImage(
                session,
                from: pixelBuffer,
                to: output
            )
            
            if transferStatus == noErr {
                completion(output)
            } else {
                if fallbackCount % 30 == 0 {
                    print("   ⚠️  VTPixelTransferSessionTransferImage failed: \(transferStatus), using Metal scaling")
                }
                // Fallback to Metal scaling
                scaleWithMetal(source: pixelBuffer, destination: output, completion: completion)
            }
        } else {
            // Fallback to Metal scaling
            scaleWithMetal(source: pixelBuffer, destination: output, completion: completion)
        }
    }
    
    private func createOutputBuffer() -> CVPixelBuffer? {
        var outputBuffer: CVPixelBuffer?
        var pixelBufferPool: CVPixelBufferPool?
        
        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 3
        ]
        
        let pixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferWidthKey: Int(settings.targetResolution.width),
            kCVPixelBufferHeightKey: Int(settings.targetResolution.height),
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        
        let poolStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pixelBufferPool
        )
        
        if poolStatus == kCVReturnSuccess, let pool = pixelBufferPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault,
                pool,
                &outputBuffer
            )
            
            if status == kCVReturnSuccess, let output = outputBuffer {
                return output
            }
        }
        
        // Fallback: create buffer directly
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(settings.targetResolution.width),
            Int(settings.targetResolution.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &outputBuffer
        )
        
        return (status == kCVReturnSuccess) ? outputBuffer : nil
    }
    
    private func scaleWithMetal(
        source: CVPixelBuffer,
        destination: CVPixelBuffer,
        completion: @escaping (CVPixelBuffer?) -> Void
    ) {
        // For now, just copy - we can add proper Metal scaling later
        // This is a placeholder that will work but won't actually upscale
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        
        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let destBase = CVPixelBufferGetBaseAddress(destination)
        else {
            completion(nil)
            return
        }
        
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        let destWidth = CVPixelBufferGetWidth(destination)
        let destHeight = CVPixelBufferGetHeight(destination)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(source)
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(destination)
        
        // Simple nearest-neighbor scaling (can be improved with Metal compute shader)
        let scaleX = Double(sourceWidth) / Double(destWidth)
        let scaleY = Double(sourceHeight) / Double(destHeight)
        
        for y in 0..<destHeight {
            let sourceY = Int(Double(y) * scaleY)
            if sourceY < sourceHeight {
                let sourceRow = sourceBase.advanced(by: sourceY * sourceBytesPerRow)
                let destRow = destBase.advanced(by: y * destBytesPerRow)
                
                for x in 0..<destWidth {
                    let sourceX = Int(Double(x) * scaleX)
                    if sourceX < sourceWidth {
                        let sourcePixel = sourceRow.advanced(by: sourceX * 4)
                        let destPixel = destRow.advanced(by: x * 4)
                        memcpy(destPixel, sourcePixel, 4)
                    }
                }
            }
        }
        
        completion(destination)
    }
    
    deinit {
        if let session = transferSession {
            VTPixelTransferSessionInvalidate(session)
        }
        
        if #available(macOS 14.0, *) {
            // Cleanup advanced features
            if superResolutionSessionStarted, let processor = superResolutionFrameProcessor {
                processor.endSession()
            }
            Task {
                if let processor = await frameInterpolationProcessor {
                    await processor.endSession()
                }
            }
            superResolutionFrameProcessor = nil
            superResolutionConfiguration = nil
            superResolutionPixelBufferPool = nil
            frameInterpolationProcessor = nil
        }
     }
}
