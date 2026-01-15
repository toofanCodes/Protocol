//
//  MediaCaptureViewModel.swift
//  Protocol
//
//  MVVM logic for media capture UI.
//

import Foundation
import SwiftUI
import SwiftData
import os.log

/// ViewModel for managing media capture state and operations
@MainActor
final class MediaCaptureViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isShowingCaptureSheet = false
    @Published var selectedAtomInstance: AtomInstance?
    @Published var selectedSettings: MediaCaptureSettings?
    @Published var storageReport: MediaStorageReport?
    @Published var isLoadingStorage = false
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.Toofan.Toofanprotocol", category: "MediaCaptureVM")
    private let captureService = MediaCaptureService.shared
    private let fileManager = MediaFileManager.shared
    
    // MARK: - Initialization
    
    init() {
        loadStorageReport()
    }
    
    // MARK: - Public Methods
    
    /// Opens the capture sheet for the given atom instance
    func startCapture(for atomInstance: AtomInstance) {
        guard let template = atomInstance.parentMoleculeInstance?.parentTemplate,
              let atomTemplate = template.atomTemplates.first(where: { $0.id == atomInstance.sourceTemplateId }),
              let settings = atomTemplate.mediaCaptureSettings else {
            logger.warning("No media capture settings for atom \(atomInstance.id)")
            return
        }
        
        selectedAtomInstance = atomInstance
        selectedSettings = settings
        isShowingCaptureSheet = true
    }
    
    /// Closes the capture sheet
    func dismissCaptureSheet() {
        isShowingCaptureSheet = false
        selectedAtomInstance = nil
        selectedSettings = nil
    }
    
    /// Loads current storage usage
    func loadStorageReport() {
        isLoadingStorage = true
        
        Task {
            storageReport = fileManager.calculateStorageUsage()
            isLoadingStorage = false
        }
    }
    
    /// Cleans up old media files using the default retention policy
    func cleanupOldMedia() async throws {
        try fileManager.cleanupOldMedia(policy: .default)
        loadStorageReport()
    }
    
    /// Deletes a specific media capture and its files
    func deleteCapture(_ capture: MediaCapture, context: ModelContext) throws {
        // Delete file from disk
        if let path = capture.mediaFileURL {
            try fileManager.deleteMedia(relativePath: path)
        }
        
        // Delete snoring clip files
        for event in capture.snoringEvents {
            if let clipPath = event.audioClipURL {
                try? fileManager.deleteMedia(relativePath: clipPath)
            }
        }
        
        // Remove from atom instance
        capture.parentAtomInstance?.mediaCapture = nil
        
        // Delete from SwiftData
        context.delete(capture)
        try context.save()
        
        loadStorageReport()
        logger.info("Deleted media capture \(capture.id)")
    }
    
    /// Checks if an atom instance has media capture configured
    func hasMediaCaptureSettings(for atomInstance: AtomInstance) -> Bool {
        guard let template = atomInstance.parentMoleculeInstance?.parentTemplate,
              let atomTemplate = template.atomTemplates.first(where: { $0.id == atomInstance.sourceTemplateId }) else {
            return false
        }
        return atomTemplate.hasMediaCapture
    }
    
    /// Gets the media capture settings for an atom instance
    func getSettings(for atomInstance: AtomInstance) -> MediaCaptureSettings? {
        guard let template = atomInstance.parentMoleculeInstance?.parentTemplate,
              let atomTemplate = template.atomTemplates.first(where: { $0.id == atomInstance.sourceTemplateId }) else {
            return nil
        }
        return atomTemplate.mediaCaptureSettings
    }
    
    /// Gets the capture state
    var captureState: CaptureState {
        captureService.state
    }
    
    /// Checks if capture is in progress
    var isCapturing: Bool {
        captureService.state.isActive
    }
}

// MARK: - Storage Report Extension

extension MediaStorageReport {
    var photoMB: Double { Double(photoBytes) / 1_000_000 }
    var videoMB: Double { Double(videoBytes) / 1_000_000 }
    var audioMB: Double { Double(audioBytes) / 1_000_000 }
    var clipsMB: Double { Double(snoringClipBytes) / 1_000_000 }
    
    var formattedBreakdown: String {
        var parts: [String] = []
        
        if photoBytes > 0 {
            parts.append(String(format: "Photos: %.1f MB", photoMB))
        }
        if videoBytes > 0 {
            parts.append(String(format: "Videos: %.1f MB", videoMB))
        }
        if audioBytes > 0 {
            parts.append(String(format: "Audio: %.1f MB", audioMB))
        }
        if snoringClipBytes > 0 {
            parts.append(String(format: "Clips: %.1f MB", clipsMB))
        }
        
        return parts.isEmpty ? "No media" : parts.joined(separator: ", ")
    }
}
