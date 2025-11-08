//
//  IOSurface+Extensions.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import IOSurface
import Metal

extension IOSurface {
    func createMetalTexture(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: Int(width),
            height: Int(height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        return device.makeTexture(descriptor: descriptor, iosurface: self, plane: 0)
    }
}

