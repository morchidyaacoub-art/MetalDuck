//
//  MetalRenderer.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import Metal
import MetalKit
import CoreVideo

class MetalRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    
    private let textureCache: CVMetalTextureCache
    
    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        
        // Set low priority for command queue to avoid impacting game performance
        commandQueue.label = "MetalDuck.RenderQueue"
        
        self.commandQueue = commandQueue
        
        guard let library = device.makeDefaultLibrary() else {
            return nil
        }
        
        self.library = library
        
        var textureCache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
        
        guard result == kCVReturnSuccess,
              let cache = textureCache else {
            return nil
        }
        
        self.textureCache = cache
    }
    
    func createTexture(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat? = nil) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bufferFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        // Determine Metal pixel format based on buffer format
        let metalFormat: MTLPixelFormat
        if let requestedFormat = pixelFormat {
            metalFormat = requestedFormat
        } else {
            // Map CVPixelFormat to MTLPixelFormat
            switch bufferFormat {
            case kCVPixelFormatType_32BGRA:
                metalFormat = .bgra8Unorm
            case kCVPixelFormatType_32ARGB:
                metalFormat = .bgra8Unorm // ARGB can be read as BGRA with swizzling
            case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                 kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
                metalFormat = .bgra8Unorm // Will need conversion
            default:
                metalFormat = .bgra8Unorm // Default fallback
            }
        }
        
        var metalTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            metalFormat,
            width,
            height,
            0,
            &metalTexture
        )
        
        guard result == kCVReturnSuccess,
              let texture = metalTexture,
              let mtlTexture = CVMetalTextureGetTexture(texture) else {
            print("⚠️ Failed to create Metal texture from pixel buffer. Format: \(bufferFormat), Width: \(width), Height: \(height)")
            return nil
        }
        
        return mtlTexture
    }
    
    func createTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        return device.makeTexture(descriptor: descriptor)
    }
}

