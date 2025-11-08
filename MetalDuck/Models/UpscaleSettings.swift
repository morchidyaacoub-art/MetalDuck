//
//  UpscaleSettings.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import VideoToolbox

enum UpscaleMode: String, Codable, CaseIterable {
    case temporal = "Temporal"
    case quality = "Quality"
    case spatial = "Spatial"
    case superResolution = "Super Resolution"
    case frameInterpolation = "Frame Interpolation"
    
    var description: String {
        switch self {
        case .temporal:
            return "Temporal (Lower latency, good quality)"
        case .quality:
            return "Quality (Higher latency, best quality)"
        case .spatial:
            return "Spatial (Fast, basic upscaling)"
        case .superResolution:
            return "Super Resolution (AI-powered upscaling)"
        case .frameInterpolation:
            return "Frame Interpolation (Increase frame rate)"
        }
    }
}

struct UpscaleSettings: Codable {
    var mode: UpscaleMode
    var targetResolution: CGSize
    var sourceResolution: CGSize
    var sharpness: Float
    
    // Super Resolution parameters
    var superResolutionEnabled: Bool = false
    var superResolutionQuality: Float = 0.5 // 0.0 to 1.0
    
    // Frame Interpolation parameters
    var frameInterpolationEnabled: Bool = false
    var interpolationMultiplier: Int = 2 // Frame rate multiplier (e.g., 2x = double the frame rate)
    
    init() {
        self.mode = .temporal
        self.targetResolution = CGSize(width: 3840, height: 2160)
        self.sourceResolution = CGSize(width: 1920, height: 1080)
        self.sharpness = 0.5
        self.superResolutionEnabled = false
        self.superResolutionQuality = 0.5
        self.frameInterpolationEnabled = false
        self.interpolationMultiplier = 2
    }
    
    /// Calculates the target frame rate based on source frame rate and multiplier
    func targetFrameRate(sourceFrameRate: Int) -> Int {
        return sourceFrameRate * interpolationMultiplier
    }
    
    var scaleFactor: Float {
        let widthScale = Float(targetResolution.width / sourceResolution.width)
        let heightScale = Float(targetResolution.height / sourceResolution.height)
        return min(widthScale, heightScale)
    }
}

