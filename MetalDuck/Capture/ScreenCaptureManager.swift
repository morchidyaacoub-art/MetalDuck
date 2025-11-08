//
//  ScreenCaptureManager.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import ScreenCaptureKit
import AppKit
import CoreMedia

@available(macOS 12.3, *)
class ScreenCaptureManager {
    private var captureSession: CaptureSession?
    private let settings: CaptureSettings
    weak var delegate: CaptureDelegate?
    private var isPickerActive: Bool = false
    
    init(settings: CaptureSettings, delegate: CaptureDelegate) {
        self.settings = settings
        self.delegate = delegate
    }
    
    func startCapture() async throws {
        if !PermissionManager.shared.hasScreenRecordingPermission {
            let granted = await PermissionManager.shared.requestScreenRecordingPermission()
            guard granted else {
                throw CaptureError.permissionDenied
            }
        }
        
        captureSession = CaptureSession(settings: settings, delegate: delegate ?? self)
        try await captureSession?.start()
    }
    
    func stopCapture() async {
        await captureSession?.stop()
        captureSession = nil
    }
    
    // MARK: - Content Picker
    
    func setPickerActive(_ active: Bool) {
        isPickerActive = active
        if active {
            SCContentSharingPicker.shared.add(self)
        } else {
            SCContentSharingPicker.shared.remove(self)
        }
    }
    
    func presentPicker() {
        if let _ = captureSession {
            // Present without binding to an existing stream for simplicity.
            SCContentSharingPicker.shared.present()
        } else {
            SCContentSharingPicker.shared.present()
        }
    }
    
    /// Apply a content filter selected from the picker to the running stream.
    func applyPickerFilter(_ filter: SCContentFilter) async {
        await captureSession?.updateContentFilter(filter)
    }
    
    static func getAvailableWindows() async -> [SCWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return []
        }
        return content.windows
    }
    
    static func getAvailableDisplays() async -> [SCDisplay] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return []
        }
        return content.displays
    }
    
    enum CaptureError: Error {
        case permissionDenied
        case sessionNotStarted
    }
}

@available(macOS 12.3, *)
extension ScreenCaptureManager: CaptureDelegate {
    func didCaptureFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        delegate?.didCaptureFrame(pixelBuffer, timestamp: timestamp)
    }
    
    func captureDidFail(with error: Error) {
        delegate?.captureDidFail(with: error)
    }
}

@available(macOS 12.3, *)
extension ScreenCaptureManager: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        // no-op
    }
    
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { [weak self] in
            await self?.applyPickerFilter(filter)
        }
    }
    
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        // no-op
    }
}

