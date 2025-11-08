//
//  MaterialView.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import SwiftUI

/// A wrapper view around NSVisualEffectView.
struct MaterialView: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

