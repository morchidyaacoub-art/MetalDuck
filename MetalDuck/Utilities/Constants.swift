//
//  Constants.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import CoreGraphics

enum Constants {
    static let defaultCaptureFPS = 60
    static let defaultSourceResolution = CGSize(width: 1920, height: 1080)
    static let defaultTargetResolution = CGSize(width: 3840, height: 2160)
    static let overlayWindowLevel = Int(CGWindowLevelKey.overlayWindow.rawValue)
}

