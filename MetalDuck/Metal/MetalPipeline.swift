//
//  MetalPipeline.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import CoreVideo
import Foundation
import Metal

class MetalPipeline {
    private let renderer: MetalRenderer
    private let upscaler: VideoToolboxUpscaler
    private let settings: UpscaleSettings

    init(renderer: MetalRenderer, upscaler: VideoToolboxUpscaler, settings: UpscaleSettings) {
        self.renderer = renderer
        self.upscaler = upscaler
        self.settings = settings
    }

    func processFrame(
        pixelBuffer: CVPixelBuffer,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        // Upscale using VideoToolbox
        upscaler.upscale(pixelBuffer: pixelBuffer) { [weak self] upscaledBuffer in
            guard let self = self,
                  let upscaledBuffer = upscaledBuffer
            else {
                completion(nil)
                return
            }

            // Convert upscaled CVPixelBuffer to MTLTexture
            let texture = self.renderer.createTexture(from: upscaledBuffer)
            completion(texture)
        }
    }
}
