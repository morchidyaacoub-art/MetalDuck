//
//  AppState.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import SwiftUI

@MainActor
@Observable
class AppState {
    var isCapturing: Bool = false
    var isUpscaling: Bool = false
    var isOverlayVisible: Bool = false
    var currentFPS: Double = 0.0
    var captureError: String?
    var processingStatus: String = "Idle"
    
    // Menu bar state
    var menuBarItem: NSStatusItem?
    
    func startCapture() {
        isCapturing = true
        isOverlayVisible = true
    }
    
    func stopCapture() {
        isCapturing = false
        isUpscaling = false
        isOverlayVisible = false
    }
    
    func updateFPS(_ fps: Double) {
        currentFPS = fps
    }
    
    func setError(_ error: String?) {
        captureError = error
    }
}
