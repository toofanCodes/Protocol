//
//  MediaCapture.swift
//  Protocol
//
//  SwiftData models for media capture storage.
//  MediaCapture stores metadata about captured media (photo/video/audio).
//  SnoringEvent stores individual snoring occurrences detected during audio recording.
//

import Foundation
import SwiftData

// MARK: - MediaCapture Model

/// Stores metadata and file references for captured media associated with an AtomInstance.
/// The actual media files are stored on disk; this model only stores relative paths.
@Model
final class MediaCapture {
    // MARK: - Core Properties
    
    /// Unique identifier
    var id: UUID = UUID()
    
    /// Type of capture: "photo", "video", or "audio"
    var captureType: String = "photo"
    
    /// When the capture occurred
    @Attribute(originalName: "dateCreated")
    var capturedAt: Date = Date()
    
    /// Relative path to the media file in Documents/MediaCaptures/
    /// nil if no file is saved (e.g., audio without full recording)
    var mediaFileURL: String?
    
    // MARK: - Audio-Specific Properties
    
    /// When audio recording started
    var recordingStartTime: Date?
    
    /// When audio recording ended
    var recordingEndTime: Date?
    
    /// Total recording duration in seconds
    @Attribute(originalName: "audioRecordingDuration")
    var totalDuration: TimeInterval?
    
    /// Snoring score (0-100) - weighted combination of duration% and avg intensity
    /// Higher = more snoring detected
    var snoringScore: Double?
    
    /// Total time spent snoring in seconds
    var totalSnoringDuration: TimeInterval?
    
    /// Number of distinct snoring events detected
    var snoringEventCount: Int?
    
    // MARK: - Relationships
    
    /// Snoring events detected during this recording
    /// Cascade delete: when MediaCapture is deleted, all events are deleted
    @Relationship(deleteRule: .cascade, inverse: \SnoringEvent.parentCapture)
    var snoringEvents: [SnoringEvent] = []
    
    /// Parent atom instance this capture belongs to
    var parentAtomInstance: AtomInstance?
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        captureType: String = "photo",
        capturedAt: Date = Date(),
        mediaFileURL: String? = nil,
        parentAtomInstance: AtomInstance? = nil
    ) {
        self.id = id
        self.captureType = captureType
        self.capturedAt = capturedAt
        self.mediaFileURL = mediaFileURL
        self.parentAtomInstance = parentAtomInstance
    }
    
    /// Convenience initializer for audio capture
    init(
        audioRecordingStartTime: Date,
        audioRecordingEndTime: Date,
        mediaFileURL: String? = nil,
        snoringScore: Double? = nil,
        totalSnoringDuration: TimeInterval? = nil,
        snoringEventCount: Int? = nil,
        parentAtomInstance: AtomInstance? = nil
    ) {
        self.id = UUID()
        self.captureType = "audio"
        self.capturedAt = audioRecordingEndTime
        self.mediaFileURL = mediaFileURL
        self.recordingStartTime = audioRecordingStartTime
        self.recordingEndTime = audioRecordingEndTime
        self.totalDuration = audioRecordingEndTime.timeIntervalSince(audioRecordingStartTime)
        self.snoringScore = snoringScore
        self.totalSnoringDuration = totalSnoringDuration
        self.snoringEventCount = snoringEventCount
        self.parentAtomInstance = parentAtomInstance
    }
    
    // MARK: - Computed Properties
    
    /// Media type enum accessor
    var type: MediaCaptureType? {
        MediaCaptureType(rawValue: captureType)
    }
    
    /// Human-readable duration string
    var durationString: String? {
        guard let duration = totalDuration else { return nil }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Snoring score as a formatted percentage string
    var snoringScoreString: String? {
        guard let score = snoringScore else { return nil }
        return "\(Int(score))%"
    }
    
    /// Returns the snoring score category
    var snoringCategory: SnoringCategory {
        guard let score = snoringScore else { return .none }
        switch score {
        case 0..<20: return .minimal
        case 20..<40: return .light
        case 40..<60: return .moderate
        case 60..<80: return .heavy
        default: return .severe
        }
    }
}

// MARK: - Snoring Category

/// Categorization of snoring severity based on score
enum SnoringCategory: String {
    case none = "None"
    case minimal = "Minimal"
    case light = "Light"
    case moderate = "Moderate"
    case heavy = "Heavy"
    case severe = "Severe"
    
    var color: String {
        switch self {
        case .none, .minimal: return "green"
        case .light: return "yellow"
        case .moderate: return "orange"
        case .heavy, .severe: return "red"
        }
    }
    
    var systemImage: String {
        switch self {
        case .none, .minimal: return "checkmark.circle.fill"
        case .light: return "exclamationmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .heavy, .severe: return "xmark.circle.fill"
        }
    }
}

// MARK: - SnoringEvent Model

/// Represents a single snoring event detected during audio recording.
/// Each event has a timestamp, duration, and intensity level.
@Model
final class SnoringEvent {
    // MARK: - Properties
    
    /// Unique identifier
    var id: UUID = UUID()
    
    /// When the snoring event occurred (start time)
    var timestamp: Date = Date()
    
    /// Duration of the snoring event in seconds
    var duration: TimeInterval = 0
    
    /// Intensity level (0-100) - average loudness during the event
    var intensity: Double = 0
    
    /// Relative path to audio clip file (if saved)
    /// Typically 10-20 seconds of audio around the event
    var audioClipURL: String?
    
    // MARK: - Relationships
    
    /// Parent media capture this event belongs to
    var parentCapture: MediaCapture?
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        duration: TimeInterval = 0,
        intensity: Double = 0,
        audioClipURL: String? = nil,
        parentCapture: MediaCapture? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.intensity = intensity
        self.audioClipURL = audioClipURL
        self.parentCapture = parentCapture
    }
    
    // MARK: - Computed Properties
    
    /// Human-readable duration string
    var durationString: String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
    
    /// Intensity as a category
    var intensityCategory: String {
        switch intensity {
        case 0..<30: return "Low"
        case 30..<60: return "Medium"
        default: return "High"
        }
    }
    
    /// Time offset from recording start (for display in timeline)
    func timeOffset(from recordingStart: Date) -> TimeInterval {
        timestamp.timeIntervalSince(recordingStart)
    }
}

// MARK: - Hashable Conformance

extension MediaCapture: Hashable {
    static func == (lhs: MediaCapture, rhs: MediaCapture) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension SnoringEvent: Hashable {
    static func == (lhs: SnoringEvent, rhs: SnoringEvent) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
