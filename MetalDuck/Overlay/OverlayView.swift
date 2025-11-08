//
//  OverlayView.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import SwiftUI
import MetalKit

struct OverlayView: NSViewRepresentable {
    let metalView: MTKView
    
    func makeNSView(context: Context) -> MTKView {
        return metalView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update if needed
    }
}

