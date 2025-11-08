//
//  ContentView.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import SwiftUI

struct ContentView: View {
    @Bindable private var coordinator = AppCoordinator.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .imageScale(.large)
                .foregroundStyle(.tint)
            
            Text("MetalDuck")
                .font(.title)
            
            if coordinator.appState.isCapturing {
                VStack {
                    Text("Capturing...")
                        .foregroundColor(.green)
                    Text("FPS: \(coordinator.appState.currentFPS, specifier: "%.1f")")
                        .font(.caption)
                }
            } else {
                Text("Ready to capture")
                    .foregroundColor(.secondary)
            }
            
            if let error = coordinator.appState.captureError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }
            
            HStack {
                Button("Start Capture") {
                    Task {
                        await coordinator.startCapture()
                    }
                }
                .disabled(coordinator.appState.isCapturing)
                
                Button("Stop Capture") {
                    Task {
                        await coordinator.stopCapture()
                    }
                }
                .disabled(!coordinator.appState.isCapturing)
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

#Preview {
    ContentView()
}
