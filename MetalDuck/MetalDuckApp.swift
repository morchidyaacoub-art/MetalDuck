//
//  MetalDuckApp.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import AppKit
import SwiftUI

@main
struct MetalDuckApp: App {
    @Bindable private var coordinator = AppCoordinator.shared

    init() {
        // Configure app to run as menu bar app
        NSApp.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            PreferencesView(
                captureSettings: Binding(
                    get: { coordinator.captureSettings },
                    set: { coordinator.captureSettings = $0 }
                ),
                upscaleSettings: Binding(
                    get: { coordinator.upscaleSettings },
                    set: { coordinator.upscaleSettings = $0 }
                )
            )
        }
    }
}
