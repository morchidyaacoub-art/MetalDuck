//
//  AppCoordinator.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import CoreVideo
import Foundation
import ScreenCaptureKit
import CoreMedia

@MainActor
@Observable
class AppCoordinator {
    static let shared = AppCoordinator()
    
    var appState = AppState()
    var captureSettings = CaptureSettings()
    var upscaleSettings = UpscaleSettings()
    
    private var metalRenderer: MetalRenderer?
    private var videoToolboxUpscaler: VideoToolboxUpscaler?
    private var metalPipeline: MetalPipeline?
    private var overlayManager: OverlayManager?
    private var captureManager: ScreenCaptureManager?
    private var menuBarController: MenuBarController?
    @available(macOS 14.0, *)
    private var interpolator: RealTimeFrameInterpolation?
    
    private var frameCount = 0
    private var lastFPSTime = Date()
    
    init() {
        setupComponents()
        setupNotifications()
    }
    
    private func setupComponents() {
        // Setup Metal
        guard let renderer = MetalRenderer() else {
            appState.setError("Failed to initialize Metal renderer")
            return
        }
        
        metalRenderer = renderer
        videoToolboxUpscaler = VideoToolboxUpscaler(renderer: renderer, settings: upscaleSettings)
        metalPipeline = MetalPipeline(renderer: renderer, upscaler: videoToolboxUpscaler!, settings: upscaleSettings)
        
        // Setup Overlay
        overlayManager = OverlayManager(renderer: renderer)
        
        // Setup Menu Bar
        menuBarController = MenuBarController(appState: appState)
        
        // Setup Capture (will be initialized when starting capture)
        if #available(macOS 12.3, *) {
            // Capture manager will be created on start
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .startCapture,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.startCapture()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .stopCapture,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.stopCapture()
            }
        }
    }
    
    func startCapture() async {
        guard !appState.isCapturing else { return }
        
        // Check permissions
        if !PermissionManager.shared.hasScreenRecordingPermission {
            let granted = await PermissionManager.shared.requestScreenRecordingPermission()
            if !granted {
                appState.setError("Screen recording permission is required")
                return
            }
        }
        
        guard let renderer = metalRenderer,
              let overlay = overlayManager
        else {
            appState.setError("Metal renderer or overlay not initialized")
            return
        }
        
        if #available(macOS 12.3, *) {
            captureManager = ScreenCaptureManager(settings: captureSettings, delegate: self)
            
            do {
                try await captureManager?.startCapture()
                appState.startCapture()
                if #available(macOS 14.0, *) {
                    interpolator = nil // will initialize lazily on first frame
                }
                
                // Create overlay window
                let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
                overlay.createOverlayWindow(frame: screenFrame)
                overlay.show()
            } catch {
                appState.setError("Failed to start capture: \(error.localizedDescription)")
            }
        } else {
            appState.setError("ScreenCaptureKit requires macOS 12.3 or later")
        }
    }
    
    func stopCapture() async {
        guard appState.isCapturing else { return }
        
        if #available(macOS 12.3, *) {
            await captureManager?.stopCapture()
        }
        
        overlayManager?.hide()
        appState.stopCapture()
    }
    
    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let pipeline = metalPipeline,
              let overlay = overlayManager
        else {
            return
        }
        
        // Upscale the frame using VideoToolbox
        pipeline.processFrame(pixelBuffer: pixelBuffer) { [weak self] upscaledTexture in
            guard let texture = upscaledTexture else { return }
            
            DispatchQueue.main.async {
                overlay.updateTexture(texture)
                self?.updateFPS()
            }
        }
    }
    
    private func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSTime)
        
        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            appState.updateFPS(fps)
            frameCount = 0
            lastFPSTime = now
        }
    }
    
    func updateUpscaleSettings(_ newSettings: UpscaleSettings) {
        upscaleSettings = newSettings
        videoToolboxUpscaler?.updateSettings(newSettings)
    }
    
    // MARK: - Picker
    @available(macOS 12.3, *)
    func presentPicker() {
        captureManager?.setPickerActive(true)
        captureManager?.presentPicker()
    }
}

@available(macOS 12.3, *)
extension AppCoordinator: CaptureDelegate {
    func didCaptureFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        // If interpolation is enabled, run through interpolator; else pass-through.
        if #available(macOS 14.0, *),
           upscaleSettings.mode == .frameInterpolation || upscaleSettings.frameInterpolationEnabled {
            Task { @MainActor in
                do {
                    if interpolator == nil {
                        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
                        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
                        let dims = CMVideoDimensions(width: width, height: height)
                        let numBetween = max(1, min(3, upscaleSettings.interpolationMultiplier - 1))
                        interpolator = try RealTimeFrameInterpolation(numFrames: numBetween, inputDimensions: dims)
                        try interpolator?.start()
                    }
                    if let outputs = try await interpolator?.process(currentBuffer: pixelBuffer, currentTimestamp: timestamp) {
                        for buffer in outputs {
                            self.processFrame(buffer)
                        }
                        return
                    }
                } catch {
                    // Fallback to passthrough on error
                }
                self.processFrame(pixelBuffer)
            }
        } else {
            processFrame(pixelBuffer)
        }
    }
    
    func captureDidFail(with error: Error) {
        Task { @MainActor in
            appState.setError("Capture failed: \(error.localizedDescription)")
            await stopCapture()
        }
    }
}
