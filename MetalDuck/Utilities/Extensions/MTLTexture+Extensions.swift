//
//  MTLTexture+Extensions.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import Metal
import CoreGraphics

extension MTLTexture {
    var size: CGSize {
        return CGSize(width: width, height: height)
    }
}

