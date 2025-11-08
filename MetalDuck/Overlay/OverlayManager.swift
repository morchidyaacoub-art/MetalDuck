//
//  OverlayManager.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import AppKit
import MetalKit

class OverlayManager: NSObject {
    private var overlayWindow: NSWindow?
    private var metalView: MTKView?
    private let renderer: MetalRenderer
    private var currentTexture: MTLTexture?
    
    init(renderer: MetalRenderer) {
        self.renderer = renderer
    }
    
    func createOverlayWindow(frame: CGRect) {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = NSWindow.Level(rawValue: Constants.overlayWindowLevel)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false
        
        let metalView = MTKView(frame: frame, device: renderer.device)
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        
        window.contentView = metalView
        self.overlayWindow = window
        self.metalView = metalView
        
        setupMetalView()
    }
    
    private func setupMetalView() {
        guard let metalView = metalView else { return }
        
        metalView.delegate = self
    }
    
    func show() {
        overlayWindow?.makeKeyAndOrderFront(nil)
    }
    
    func hide() {
        overlayWindow?.orderOut(nil)
    }
    
    func updateFrame(_ frame: CGRect) {
        overlayWindow?.setFrame(frame, display: true)
        metalView?.frame = frame
    }
    
    func updateTexture(_ texture: MTLTexture) {
        currentTexture = texture
        metalView?.draw()
    }
    
    func close() {
        overlayWindow?.close()
        overlayWindow = nil
        metalView = nil
    }
}

extension OverlayManager: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes if needed
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let texture = currentTexture else {
            return
        }
        
        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            return
        }
        
        // Copy texture to drawable using blit encoder
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return
        }
        
        blitEncoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: min(texture.width, drawable.texture.width), 
                               height: min(texture.height, drawable.texture.height), 
                               depth: 1),
            to: drawable.texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

