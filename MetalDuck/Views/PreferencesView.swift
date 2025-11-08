//
//  PreferencesView.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import SwiftUI
import ScreenCaptureKit
@preconcurrency import VideoToolbox

struct PreferencesView: View {
    @Binding var captureSettings: CaptureSettings
    @Binding var upscaleSettings: UpscaleSettings
    @State private var targetType: String = "Display"
    @State private var availableWindows: [(id: CGWindowID, title: String)] = []
    @State private var availableDisplays: [(id: CGDirectDisplayID, name: String)] = []
    @State private var selectedWindowID: CGWindowID?
    @State private var selectedDisplayID: CGDirectDisplayID?
    @State private var isLoading: Bool = false
    
    // Intermediate state for CGSize bindings
    @State private var captureWidth: Double = 1920
    @State private var captureHeight: Double = 1080
    @State private var targetWidth: Double = 3840
    @State private var targetHeight: Double = 2160
    
    private let sectionSpacing: CGFloat = 20
    private let verticalLabelSpacing: CGFloat = 8
    
    var body: some View {
        VStack {
            Form {
                HeaderView("Capture Settings")
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 1, trailing: 0))
                
                // A group that hides view labels.
                Group {
                    VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                        Text("Capture Type")
                        Picker("Capture", selection: $targetType) {
                            Text("Display")
                                .tag("Display")
                            Text("Window")
                                .tag("Window")
                        }
                        .onChange(of: targetType) { _, newValue in
                            if newValue == "Window" {
                                captureSettings.targetDisplayID = nil
                            } else {
                                captureSettings.targetWindowID = nil
                            }
                            loadAvailableTargets()
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                        Text("Screen Content")
                        if targetType == "Window" {
                            if isLoading {
                                Text("Loading windows...")
                                    .foregroundColor(.secondary)
                            } else if availableWindows.isEmpty {
                                Text("No windows available")
                                    .foregroundColor(.secondary)
                            } else {
                                Picker("Window", selection: Binding(
                                    get: { selectedWindowID },
                                    set: { newValue in
                                        selectedWindowID = newValue
                                        captureSettings.targetWindowID = newValue
                                        captureSettings.targetDisplayID = nil
                                    }
                                )) {
                                    Text("Select a window...").tag(nil as CGWindowID?)
                                    ForEach(availableWindows, id: \.id) { window in
                                        Text(window.title.isEmpty ? "Untitled Window" : window.title)
                                            .tag(window.id as CGWindowID?)
                                    }
                                }
                            }
                        } else {
                            if isLoading {
                                Text("Loading displays...")
                                    .foregroundColor(.secondary)
                            } else if availableDisplays.isEmpty {
                                Text("No displays available")
                                    .foregroundColor(.secondary)
                            } else {
                                Picker("Display", selection: Binding(
                                    get: { selectedDisplayID },
                                    set: { newValue in
                                        selectedDisplayID = newValue
                                        captureSettings.targetDisplayID = newValue
                                        captureSettings.targetWindowID = nil
                                    }
                                )) {
                                    Text("Select a display...").tag(nil as CGDirectDisplayID?)
                                    ForEach(availableDisplays, id: \.id) { display in
                                        Text(display.name)
                                            .tag(display.id as CGDirectDisplayID?)
                                    }
                                }
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                        Text("Resolution")
                        HStack {
                            TextField("Width", value: $captureWidth, format: .number)
                                .frame(width: 80)
                                .onChange(of: captureWidth) { _, newValue in
                                    captureSettings.captureResolution.width = CGFloat(newValue)
                                    // Update upscale source resolution to match capture resolution
                                    upscaleSettings.sourceResolution.width = CGFloat(newValue)
                                    AppCoordinator.shared.updateUpscaleSettings(upscaleSettings)
                                }
                            Text("x")
                            TextField("Height", value: $captureHeight, format: .number)
                                .frame(width: 80)
                                .onChange(of: captureHeight) { _, newValue in
                                    captureSettings.captureResolution.height = CGFloat(newValue)
                                    // Update upscale source resolution to match capture resolution
                                    upscaleSettings.sourceResolution.height = CGFloat(newValue)
                                    AppCoordinator.shared.updateUpscaleSettings(upscaleSettings)
                                }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                        Text("Frame Rate")
                        HStack {
                            TextField("Frame Rate", value: $captureSettings.frameRate, format: .number)
                                .frame(width: 80)
                            Text("fps")
                                .foregroundColor(.secondary)
                            Stepper("", value: $captureSettings.frameRate, in: 30...120, step: 30)
                                .labelsHidden()
                        }
                    }
                    
                    if #available(macOS 15.0, *) {
                        VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                            Text("Display HDR")
                            Picker("Select Preset", selection: $captureSettings.selectedDynamicRangePreset) {
                                Text("Default (None)")
                                    .tag(DynamicRangePreset?.none)
                                ForEach(DynamicRangePreset.allCases, id: \.self) {
                                    Text($0.rawValue)
                                        .tag(DynamicRangePreset?.some($0))
                                }
                            }
                        }
                    }
                }
                .labelsHidden()
                
                Toggle("Use Virtual Display", isOn: $captureSettings.useVirtualDisplay)
                
                if targetType == "Window" {
                    Button("Refresh Windows") {
                        loadAvailableTargets()
                    }
                } else {
                    Button("Refresh Displays") {
                        loadAvailableTargets()
                    }
                }
                
                // Add some space between sections.
                Spacer()
                    .frame(height: sectionSpacing)
                
                HeaderView("Content Picker")
                HStack {
                    Button("Present Picker") {
                        if #available(macOS 12.3, *) {
                            AppCoordinator.shared.presentPicker()
                        }
                    }
                }
                
                // Add some space between sections.
                Spacer()
                    .frame(height: sectionSpacing)
                
                HeaderView("Upscale Settings")
                
                Group {
                    VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                        Text("Mode")
                        Picker("Mode", selection: $upscaleSettings.mode) {
                            ForEach(UpscaleMode.allCases, id: \.self) { mode in
                                Text(mode.description).tag(mode)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                        Text("Target Resolution")
                        HStack {
                            TextField("Width", value: $targetWidth, format: .number)
                                .frame(width: 80)
                                .onChange(of: targetWidth) { _, newValue in
                                    upscaleSettings.targetResolution.width = CGFloat(newValue)
                                }
                            Text("x")
                            TextField("Height", value: $targetHeight, format: .number)
                                .frame(width: 80)
                                .onChange(of: targetHeight) { _, newValue in
                                    upscaleSettings.targetResolution.height = CGFloat(newValue)
                                }
                        }
                        
                        // Show scale factor and actual output resolution for Super Resolution
                        if upscaleSettings.mode == .superResolution || (upscaleSettings.mode != .frameInterpolation && upscaleSettings.superResolutionEnabled) {
                            if #available(macOS 14.0, *) {
                                let sourceWidth = Int(upscaleSettings.sourceResolution.width)
                                let sourceHeight = Int(upscaleSettings.sourceResolution.height)
                                let targetWidth = Int(upscaleSettings.targetResolution.width)
                                let targetHeight = Int(upscaleSettings.targetResolution.height)
                                
                                if sourceWidth > 0 && sourceHeight > 0 {
                                    let scaleFactor = Float(targetWidth) / Float(sourceWidth)
                                    let heightScaleFactor = Float(targetHeight) / Float(sourceHeight)
                                    let actualScaleFactor = min(scaleFactor, heightScaleFactor)
                                    
                                    // Get supported scale factors
                                    let supportedScaleFactors = VTLowLatencySuperResolutionScalerConfiguration.supportedScaleFactors(
                                        frameWidth: sourceWidth,
                                        frameHeight: sourceHeight
                                    )
                                    
                                    if let closestScaleFactor = supportedScaleFactors.min(by: { abs($0 - actualScaleFactor) < abs($1 - actualScaleFactor) }) {
                                        let actualOutputWidth = Int(Float(sourceWidth) * closestScaleFactor)
                                        let actualOutputHeight = Int(Float(sourceHeight) * closestScaleFactor)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Scale Factor: \(String(format: "%.2f", closestScaleFactor))x")
                                                .foregroundColor(.secondary)
                                                .font(.caption)
                                            Text("Actual Output: \(actualOutputWidth)x\(actualOutputHeight)")
                                                .foregroundColor(actualOutputWidth != targetWidth || actualOutputHeight != targetHeight ? .orange : .secondary)
                                                .font(.caption)
                                            if actualOutputWidth != targetWidth || actualOutputHeight != targetHeight {
                                                Text("Note: Super Resolution uses scale factors, not exact resolution")
                                                    .foregroundColor(.orange)
                                                    .font(.caption2)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                        Text("Sharpness")
                        Slider(value: $upscaleSettings.sharpness, in: 0...1)
                    }
                    
                    // Frame Rate Multiplier - only show when Frame Interpolation mode is selected
                    if upscaleSettings.mode == .frameInterpolation {
                        VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                            Text("Frame Rate Multiplier")
                            HStack {
                                TextField("Multiplier", value: $upscaleSettings.interpolationMultiplier, format: .number)
                                    .frame(width: 80)
                                Text("x")
                                    .foregroundColor(.secondary)
                                Stepper("", value: $upscaleSettings.interpolationMultiplier, in: 1...8, step: 1)
                                    .labelsHidden()
                            }
                            // Show calculated target frame rate
                            Text("\(captureSettings.frameRate) fps → \(upscaleSettings.targetFrameRate(sourceFrameRate: captureSettings.frameRate)) fps")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("Multiplies the source frame rate. Higher multipliers create smoother motion but require more processing.")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .labelsHidden()
            }
            .padding()
        }
        .background(MaterialView())
        .frame(minWidth: 550, minHeight: 500)
        .onChange(of: upscaleSettings.mode) { oldMode, newMode in
            print("🔄 PreferencesView: Mode changed from \(oldMode) to \(newMode)")
            AppCoordinator.shared.updateUpscaleSettings(upscaleSettings)
        }
        .onChange(of: upscaleSettings.targetResolution) { _, _ in
            AppCoordinator.shared.updateUpscaleSettings(upscaleSettings)
        }
        .onChange(of: upscaleSettings.superResolutionQuality) { _, _ in
            AppCoordinator.shared.updateUpscaleSettings(upscaleSettings)
        }
        .onChange(of: upscaleSettings.interpolationMultiplier) { _, _ in
            AppCoordinator.shared.updateUpscaleSettings(upscaleSettings)
        }
        .onChange(of: captureSettings.captureResolution) { oldResolution, newResolution in
            // Sync upscale source resolution with capture resolution
            let currentSourceWidth = Int(upscaleSettings.sourceResolution.width)
            let currentSourceHeight = Int(upscaleSettings.sourceResolution.height)
            let newWidth = Int(newResolution.width)
            let newHeight = Int(newResolution.height)
            
            if currentSourceWidth != newWidth || currentSourceHeight != newHeight {
                print("🔄 PreferencesView: Capture resolution changed, updating source resolution")
                print("   Capture: \(newWidth)x\(newHeight)")
                print("   Source: \(currentSourceWidth)x\(currentSourceHeight) → \(newWidth)x\(newHeight)")
                upscaleSettings.sourceResolution = newResolution
                AppCoordinator.shared.updateUpscaleSettings(upscaleSettings)
            }
        }
        .onAppear {
            // Sync initial values
            captureWidth = Double(captureSettings.captureResolution.width)
            captureHeight = Double(captureSettings.captureResolution.height)
            targetWidth = Double(upscaleSettings.targetResolution.width)
            targetHeight = Double(upscaleSettings.targetResolution.height)
            
            // Determine current target type
            if captureSettings.targetWindowID != nil {
                targetType = "Window"
                selectedWindowID = captureSettings.targetWindowID
            } else if captureSettings.targetDisplayID != nil {
                targetType = "Display"
                selectedDisplayID = captureSettings.targetDisplayID
            } else {
                targetType = "Display"
            }
            
            loadAvailableTargets()
        }
    }
    
    @available(macOS 12.3, *)
    private func loadAvailableTargets() {
        isLoading = true
        
        Task {
            if targetType == "Window" {
                let windows = await ScreenCaptureManager.getAvailableWindows()
                await MainActor.run {
                    availableWindows = windows.compactMap { window in
                        // SCWindow uses windowID property
                        let windowID = window.windowID
                        let title = window.title ?? window.owningApplication?.applicationName ?? "Untitled Window"
                        return (id: windowID, title: title)
                    }
                    isLoading = false
                }
            } else {
                let displays = await ScreenCaptureManager.getAvailableDisplays()
                await MainActor.run {
                    availableDisplays = displays.map { display in
                        let displayID = display.displayID
                        let width = Int(display.width)
                        let height = Int(display.height)
                        let name = "Display \(displayID) (\(width)x\(height))"
                        return (id: displayID, name: name)
                    }
                    isLoading = false
                }
            }
        }
    }
}

