//
//  PermissionManager.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import AVFoundation
import Foundation
import ScreenCaptureKit

class PermissionManager {
    static let shared = PermissionManager()
    
    private init() {}
    
    var hasScreenRecordingPermission: Bool {
        if #available(macOS 12.3, *) {
            return CGPreflightScreenCaptureAccess()
        } else {
            // Fallback for older macOS versions
            return CGPreflightScreenCaptureAccess()
        }
    }
    
    func requestScreenRecordingPermission() async -> Bool {
        if hasScreenRecordingPermission {
            return true
        }
        
        if #available(macOS 12.3, *) {
            return CGRequestScreenCaptureAccess()
        } else {
            // For older macOS, use the legacy method
            return await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    let result = CGRequestScreenCaptureAccess()
                    continuation.resume(returning: result)
                }
            }
        }
    }
    
    var hasAccessibilityPermission: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
