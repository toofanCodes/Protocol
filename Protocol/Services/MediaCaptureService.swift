//
//  MediaCaptureService.swift
//  Protocol
//
//  Orchestrates media capture operations and coordinates with SwiftData.
//  This is the main entry point for UI to trigger captures.
//

import Foundation
import SwiftData
import os.log

// MARK: - Capture Error

enum CaptureError: LocalizedError {
    case alreadyInProgress
    case missingSettings
    case permissionDenied(String)
    case hardwareUnavailable
    case insufficientStorage
    case interrupted(reason: String)
    case saveFailed
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "A capture is already in progress"
        case .missingSettings:
            return "Media capture settings not configured"
        case .permissionDenied(let type):
            return "\(type) permission denied"
        case .hardwareUnavailable:
            return "Required hardware is not available"
        case .insufficientStorage:
            return "Not enough storage space"
        case .interrupted(let reason):
            return "Capture interrupted: \(reason)"
        case .saveFailed:
            return "Failed to save media"
        case .cancelled:
            return "Capture was cancelled"
        }
    }
}

// MARK: - Capture State

enum CaptureState: Equatable {
    case idle
    case preparing
    case capturing
    case processing
    case completed
    case failed(String)
    
    var isActive: Bool {
        switch self {
        case .preparing, .capturing, .processing:
            return true
        default:
            return false
        }
    }
}

// MARK: - Media Capture Service

/// Main orchestrator for all media capture operations
@MainActor @Observable
final class MediaCaptureService {
    
    // MARK: - Singleton
    
    static let shared = MediaCaptureService()
    
    // MARK: - Observable Properties
    
    var state: CaptureState = .idle
    var captureProgress: Double = 0
    var elapsedTime: TimeInterval = 0
    var currentSnoringIntensity: Double = 0
    var detectedSnoringEvents: [DetectedSnoringEvent] = []
    
    // MARK: - Retake Logic
    var pendingCapture: MediaCapture?
    private var isRetake: Bool = false
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.Toofan.Toofanprotocol", category: "MediaCaptureService")
    private let fileManager = MediaFileManager.shared
    
    private var photoHandler: PhotoCaptureHandler?
    private var videoHandler: VideoCaptureHandler?
    private var audioHandler: AudioCaptureHandler?
    
    private var currentAtomInstance: AtomInstance?
    private var currentSettings: MediaCaptureSettings?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Checks if capture can be started
    var canStartCapture: Bool {
        switch state {
        case .idle, .completed, .failed:
            return true
        default:
            return false
        }
    }
    
    /// Starts a media capture for the given atom instance
    /// - Parameters:
    ///   - atomInstance: The atom instance to attach the capture to
    ///   - settings: Capture configuration
    ///   - context: SwiftData model context for saving
    func startCapture(
        for atomInstance: AtomInstance,
        settings: MediaCaptureSettings,
        context: ModelContext
    ) async throws {
        guard !state.isActive else {
            throw CaptureError.alreadyInProgress
        }
        
        state = .preparing
        currentAtomInstance = atomInstance
        currentSettings = settings
        detectedSnoringEvents = []
        captureProgress = 0
        elapsedTime = 0
        currentSnoringIntensity = 0
        isRetake = false
        pendingCapture = nil
        
        logger.info("Starting \(settings.captureType.rawValue) capture for atom \(atomInstance.id)")
        
        try await beginCapture(settings: settings, context: context)
    }
    
    /// Starts a retake session (safe capture without deleting old media yet)
    func startRetake(
        for atomInstance: AtomInstance,
        settings: MediaCaptureSettings,
        context: ModelContext
    ) async throws {
        guard !state.isActive else {
            throw CaptureError.alreadyInProgress
        }
        
        state = .preparing
        currentAtomInstance = atomInstance
        currentSettings = settings
        detectedSnoringEvents = []
        captureProgress = 0
        elapsedTime = 0
        currentSnoringIntensity = 0
        isRetake = true
        pendingCapture = nil
        
        logger.info("Starting RETAKE \(settings.captureType.rawValue) capture for atom \(atomInstance.id)")
        
        try await beginCapture(settings: settings, context: context)
    }
    
    private func beginCapture(settings: MediaCaptureSettings, context: ModelContext) async throws {
        do {
            switch settings.captureType {
            case .photo:
                try await capturePhoto(settings: settings.photoSettings ?? PhotoCaptureSettings(), context: context)
                
            case .video:
                try await captureVideo(settings: settings.videoSettings ?? VideoCaptureSettings(), context: context)
                
            case .audio:
                try await startAudioCapture(settings: settings.audioSettings ?? AudioCaptureSettings())
            }
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }
    
    /// Stops an ongoing audio capture
    func stopAudioCapture(context: ModelContext) async throws -> MediaCapture? {
        guard state == .capturing, let audioHandler = audioHandler else {
            return nil
        }
        
        state = .processing
        
        do {
            let (analysis, audioPath) = try await audioHandler.stopRecording()
            
            let relativePath = audioPath
            
            let capture = MediaCapture(
                audioRecordingStartTime: Date().addingTimeInterval(-elapsedTime),
                audioRecordingEndTime: Date(),
                mediaFileURL: relativePath,
                snoringScore: analysis?.score,
                totalSnoringDuration: analysis?.totalSnoringDuration,
                snoringEventCount: analysis?.events.count,
                parentAtomInstance: isRetake ? nil : currentAtomInstance
            )
            
            // Create SnoringEvent records
            if let events = analysis?.events {
                for event in events {
                    let snoringEvent = SnoringEvent(
                        timestamp: event.startTime,
                        duration: event.duration,
                        intensity: event.intensity,
                        audioClipURL: nil,  // TODO: Save individual clips
                        parentCapture: capture
                    )
                    capture.snoringEvents.append(snoringEvent)
                }
            }
            
            if isRetake {
                self.pendingCapture = capture
                 // Don't insert or save yet if we want to be purely provisional
                 // But we need the file. File is saved.
                 // We can insert into context, but not link to Atom.
                 context.insert(capture)
            } else {
                currentAtomInstance?.mediaCapture = capture
                context.insert(capture)
                currentAtomInstance?.markComplete()
            }
            
            try context.save()
            
            state = .completed
            self.audioHandler = nil
            // Don't nil currentAtomInstance yet if retaking, might need it for commit
            if !isRetake {
                currentAtomInstance = nil
                currentSettings = nil
            }
            
            logger.info("Audio capture saved. Score: \(analysis?.score ?? 0), Events: \(analysis?.events.count ?? 0)")
            
            return capture
            
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }
    
    /// Cancels an ongoing capture
    func cancelCapture() {
        audioHandler?.cancelRecording()
        
        state = .idle
        audioHandler = nil
        photoHandler = nil
        videoHandler = nil
        currentAtomInstance = nil
        currentSettings = nil
        detectedSnoringEvents = []
        isRetake = false
        pendingCapture = nil
        
        logger.info("Capture cancelled")
    }
    
    /// Deletes the media associated with an atom instance
    func deleteMedia(for atomInstance: AtomInstance, context: ModelContext) async throws {
        guard let capture = atomInstance.mediaCapture else { return }
        
        // 1. Delete file from disk
        if let path = capture.mediaFileURL {
            try fileManager.deleteMedia(relativePath: path)
        }
        
        // 2. Delete from SwiftData
        atomInstance.mediaCapture = nil
        context.delete(capture)
        
        // 3. Mark atom incomplete
        atomInstance.isCompleted = false
        
        try context.save()
        
        state = .idle
        logger.info("Media deleted for atom \(atomInstance.id)")
    }
    
    // MARK: - Retake Operations
    
    func commitRetake(context: ModelContext) async throws {
        guard let newCapture = pendingCapture, let atom = currentAtomInstance else { return }
        
        // 1. Delete old media if it exists
        if let oldCapture = atom.mediaCapture {
             if let path = oldCapture.mediaFileURL {
                try? fileManager.deleteMedia(relativePath: path)
            }
            context.delete(oldCapture)
        }
        
        // 2. Assign new capture
        // Is newCapture already inserted? Yes, in save* methods.
        newCapture.parentAtomInstance = atom
        atom.mediaCapture = newCapture
        atom.markComplete()
        
        try context.save()
        
        pendingCapture = nil
        isRetake = false
        currentAtomInstance = nil
        currentSettings = nil
        state = .idle // or .completed?
    }
    
    func discardRetake(context: ModelContext) async {
        guard let capture = pendingCapture else { return }
        
        // Delete the temp file we just created
        if let path = capture.mediaFileURL {
            try? fileManager.deleteMedia(relativePath: path)
        }
        
        context.delete(capture)
        try? context.save()
        
        pendingCapture = nil
        isRetake = false
        
        // We revert to where we were... viewing the old media
        // state logic is handled by caller mostly (view state)
    }
    
    // MARK: - Private Methods
    
    private func capturePhoto(settings: PhotoCaptureSettings, context: ModelContext) async throws {
        let handler = PhotoCaptureHandler()
        photoHandler = handler
        state = .capturing
        
        let data = try await handler.capturePhoto(
            useFrontCamera: settings.useFrontCamera,
            compressionQuality: settings.compressionQuality
        )
        
        state = .processing
        
        // Save photo file
        guard let atomID = currentAtomInstance?.id else {
            throw CaptureError.saveFailed
        }
        
        let relativePath = try fileManager.saveMedia(data: data, type: .photo, atomInstanceID: atomID)
        
        // Save to Photos library if requested
        if settings.saveToPhotos {
            try await handler.saveToPhotosLibrary(data)
        }
        
        // Create MediaCapture record
        let capture = MediaCapture(
            captureType: "photo",
            mediaFileURL: relativePath,
            parentAtomInstance: isRetake ? nil : currentAtomInstance
        )
        
        context.insert(capture)
        
        if isRetake {
            self.pendingCapture = capture
            // Do NOT update atom yet
        } else {
            currentAtomInstance?.mediaCapture = capture
            currentAtomInstance?.markComplete()
        }
        
        try context.save()
        
        state = .completed
        photoHandler = nil
        
        // Reset if normal capture
        if !isRetake {
            currentAtomInstance = nil
            currentSettings = nil
        }
        
        logger.info("Photo captured and saved: \(relativePath)")
    }
    
    private func captureVideo(settings: VideoCaptureSettings, context: ModelContext) async throws {
        let handler = VideoCaptureHandler()
        videoHandler = handler
        state = .capturing
        
        let data = try await handler.captureVideo(
            maxDuration: settings.maxDuration,
            quality: settings.quality
        )
        
        state = .processing
        
        // Save video file
        guard let atomID = currentAtomInstance?.id else {
            throw CaptureError.saveFailed
        }
        
        let relativePath = try fileManager.saveMedia(data: data, type: .video, atomInstanceID: atomID)
        
        // Save to Photos library if requested
        if settings.saveToPhotos {
            try await handler.saveToPhotosLibrary(data)
        }
        
        // Create MediaCapture record
        let capture = MediaCapture(
            captureType: "video",
            mediaFileURL: relativePath,
            parentAtomInstance: isRetake ? nil : currentAtomInstance
        )
        
        context.insert(capture)
        
        if isRetake {
             self.pendingCapture = capture
        } else {
            currentAtomInstance?.mediaCapture = capture
            currentAtomInstance?.markComplete()
        }
        
        try context.save()
        
        state = .completed
        videoHandler = nil
        
        if !isRetake {
            currentAtomInstance = nil
            currentSettings = nil
        }
        
        logger.info("Video captured and saved: \(relativePath)")
    }
    
    private func startAudioCapture(settings: AudioCaptureSettings) async throws {
        guard let atomID = currentAtomInstance?.id else {
            throw CaptureError.saveFailed
        }
        
        let handler = AudioCaptureHandler()
        audioHandler = handler
        
        try await handler.startRecording(settings: settings, atomInstanceID: atomID)
        
        state = .capturing
        
        // Observe handler updates
        Task { @MainActor in
            while self.state == .capturing {
                self.elapsedTime = handler.elapsedTime
                self.currentSnoringIntensity = handler.currentIntensity
                self.detectedSnoringEvents = handler.detectedEvents
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
