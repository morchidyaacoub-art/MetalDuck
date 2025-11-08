//
//  ProcessManager.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import Foundation
import AppKit

class ProcessManager {
    static let shared = ProcessManager()
    
    private init() {}
    
    func getRunningApplications() -> [NSRunningApplication] {
        return NSWorkspace.shared.runningApplications
    }
    
    func findGameWindows() -> [NSWindow] {
        // This would enumerate windows to find game windows
        // For now, return empty array - can be enhanced later
        return []
    }
    
    func getWindowList() -> [[String: Any]] {
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windowList
    }
}

