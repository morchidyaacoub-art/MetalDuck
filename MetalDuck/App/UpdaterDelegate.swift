//
//  UpdaterDelegate.swift
//  MetalDuck
//

import Sparkle

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://raw.githubusercontent.com/lospi/metalduck/main/appcast.xml"
    }
}
