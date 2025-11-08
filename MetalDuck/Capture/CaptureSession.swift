//
//  CaptureSession.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import ScreenCaptureKit
import CoreVideo
import CoreMedia

@available(macOS 12.3, *)
class CaptureSession {
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    weak var delegate: CaptureDelegate?
    private let settings: CaptureSettings
    
    init(settings: CaptureSettings, delegate: CaptureDelegate) {
        self.settings = settings
        self.delegate = delegate
    }
    
    func start() async throws {
        guard let contentFilter = await settings.contentFilter() else {
            throw CaptureError.invalidContentFilter
        }
        
        let streamConfig: SCStreamConfiguration
        if #available(macOS 15.0, *), let preset = settings.selectedDynamicRangePreset?.scDynamicRangePreset {
            streamConfig = SCStreamConfiguration(preset: preset)
        } else {
            streamConfig = SCStreamConfiguration()
        }
        
        streamConfig.width = Int(settings.captureResolution.width)
        streamConfig.height = Int(settings.captureResolution.height)
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
        streamConfig.queueDepth = 3
        streamConfig.showsCursor = false
        streamConfig.capturesAudio = false
        
        streamOutput = StreamOutput(delegate: delegate)
        
        stream = SCStream(filter: contentFilter, configuration: streamConfig, delegate: nil)
        
        try stream?.addStreamOutput(
            streamOutput!,
            type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "com.metalduck.capture", qos: .userInitiated)
        )
        
        try await stream?.startCapture()
    }
    
    func updateContentFilter(_ filter: SCContentFilter) async {
        do {
            try await stream?.updateContentFilter(filter)
        } catch {
            print("Error updating content filter: \(error.localizedDescription)")
        }
    }
    
    func stop() async {
        do {
            try await stream?.stopCapture()
        } catch {
            // Log error but continue with cleanup
            print("Error stopping capture: \(error.localizedDescription)")
        }
        stream = nil
        streamOutput = nil
    }
    
    enum CaptureError: Error {
        case invalidContentFilter
        case streamCreationFailed
    }
}

@available(macOS 12.3, *)
private class StreamOutput: NSObject, SCStreamOutput {
    weak var delegate: CaptureDelegate?
    
    init(delegate: CaptureDelegate?) {
        self.delegate = delegate
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        delegate?.didCaptureFrame(pixelBuffer, timestamp: timestamp)
    }
}

