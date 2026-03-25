//
//  DeviceCapabilityDatabase.swift
//  MetalDuck
//
//  Loads the bundled DeviceCapabilities.json and provides support/recommendation
//  lookups keyed by chip name. The JSON is updated by the developer based on
//  diagnostics reports submitted via GitHub issues.
//

import Foundation
import Metal

// MARK: - JSON Schema

private struct DatabaseFile: Decodable {
    let schemaVersion: Int
    let lastUpdated: String
    let entries: [DeviceEntry]
}

struct DeviceEntry: Decodable {
    let chipPattern: String
    let frameInterpolation: FrameInterpolationData
    let superResolution: SuperResolutionData?
    let reportCount: Int
    let notes: String?

    struct FrameInterpolationData: Decodable {
        let supported: [String]
        let unsupported: [String]
        let recommended: String?
    }

    struct SuperResolutionData: Decodable {
        let maxInputLabel: String?
        let supportedInputs: [String]
        let unsupportedInputs: [String]
    }
}

// MARK: - Public API

enum ResolutionSupport {
    /// Known working on this device (confirmed by user report).
    case knownSupported
    /// Known to fail on this device (confirmed by user report).
    case knownUnsupported
    /// Chip is in the database but this resolution was not tested.
    case unknown
    /// Chip has no entry in the database yet.
    case noData
}

struct DeviceCapabilityDatabase {
    static let shared = DeviceCapabilityDatabase()

    private let entries: [DeviceEntry]
    let currentChip: String

    init() {
        currentChip = MTLCreateSystemDefaultDevice()?.name ?? "Unknown"

        guard let url = Bundle.main.url(forResource: "DeviceCapabilities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let db = try? JSONDecoder().decode(DatabaseFile.self, from: data) else {
            entries = []
            return
        }
        entries = db.entries
    }

    // MARK: - Lookups

    /// Returns the database entry whose chipPattern is contained in or equals the given chip name.
    func entry(for chip: String? = nil) -> DeviceEntry? {
        let name = chip ?? currentChip
        // Exact match first, then substring match (handles minor variant suffixes)
        return entries.first { name == $0.chipPattern }
            ?? entries.first { name.contains($0.chipPattern) || $0.chipPattern.contains(name) }
    }

    func frameInterpolationSupport(for resolution: ProcessingResolution, chip: String? = nil) -> ResolutionSupport {
        guard let e = entry(for: chip) else { return .noData }
        if e.frameInterpolation.supported.contains(resolution.rawValue)   { return .knownSupported }
        if e.frameInterpolation.unsupported.contains(resolution.rawValue) { return .knownUnsupported }
        return .unknown
    }

    func recommendedFrameInterpolationResolution(chip: String? = nil) -> ProcessingResolution? {
        guard let rec = entry(for: chip)?.frameInterpolation.recommended else { return nil }
        return ProcessingResolution(rawValue: rec)
    }
}
