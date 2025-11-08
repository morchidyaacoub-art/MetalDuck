//
//  CaptureDelegate.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import ScreenCaptureKit
import CoreVideo
import CoreMedia

protocol CaptureDelegate: AnyObject {
    func didCaptureFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime)
    func captureDidFail(with error: Error)
}

