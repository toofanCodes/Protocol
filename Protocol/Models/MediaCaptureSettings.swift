//
//  MediaCaptureSettings.swift
//  Protocol
//
//  Codable structs for media capture configuration.
//  These are NOT SwiftData models - they are stored as JSON in AtomTemplate.
//

import Foundation

// MARK: - Media Capture Type

/// Type of media that can be captured for an atom
enum MediaCaptureType: String, Codable, CaseIterable {
    case photo
    case video
    case audio
    
    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        case .audio: return "Audio"
        }
    }
    
    var systemImage: String {
        switch self {
        case .photo: return "camera.fill"
        case .video: return "video.fill"
        case .audio: return "mic.fill"
        }
    }
}

// MARK: - Recording Duration

/// Defines when audio recording should stop
enum RecordingDuration: Codable, Equatable, Hashable {
    /// User manually stops recording
    case manual
    
    /// Record until a specific time (e.g., 7:00 AM)
    case untilTime(hour: Int, minute: Int)
    
    /// Record for a fixed duration in minutes
    case fixed(minutes: Int)
    
    var displayString: String {
        switch self {
        case .manual:
            return "Manual"
        case .untilTime(let hour, let minute):
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            if let date = Calendar.current.date(from: components) {
                return "Until \(formatter.string(from: date))"
            }
            return "Until \(hour):\(String(format: "%02d", minute))"
        case .fixed(let minutes):
            if minutes >= 60 {
                let hours = minutes / 60
                let mins = minutes % 60
                if mins == 0 {
                    return "\(hours) hour\(hours > 1 ? "s" : "")"
                }
                return "\(hours)h \(mins)m"
            }
            return "\(minutes) min"
        }
    }
    
    /// Common presets for recording duration
    static var presets: [RecordingDuration] {
        [
            .manual,
            .fixed(minutes: 30),
            .fixed(minutes: 60),
            .fixed(minutes: 120),
            .fixed(minutes: 180),
            .fixed(minutes: 360),  // 6 hours
            .fixed(minutes: 480),  // 8 hours
            .untilTime(hour: 6, minute: 0),
            .untilTime(hour: 7, minute: 0),
            .untilTime(hour: 8, minute: 0)
        ]
    }
}

// MARK: - Video Quality

/// Quality setting for video capture
enum VideoQuality: String, Codable, CaseIterable {
    case low
    case medium
    case high
    
    var displayName: String {
        switch self {
        case .low: return "Low (480p)"
        case .medium: return "Medium (720p)"
        case .high: return "High (1080p)"
        }
    }
}

// MARK: - Audio Capture Settings

/// Configuration for audio recording with optional snoring detection
struct AudioCaptureSettings: Codable, Equatable {
    /// Enable snoring detection using Apple's Sound Analysis
    var enableSnoringDetection: Bool = true
    
    /// When recording should stop
    var recordingDuration: RecordingDuration = .fixed(minutes: 480)  // 8 hours default
    
    /// Save the full recording (warning: ~20MB/night)
    var saveFullRecording: Bool = true
    
    /// Save individual snoring event clips (10-20s each)
    var saveSnoringClips: Bool = true
    
    /// Sensitivity threshold for snoring detection (0-100)
    /// Lower = more sensitive (more events detected)
    var sensitivityThreshold: Double = 40.0
    
    /// Auto-cleanup: Delete recordings older than this many days (nil = keep forever)
    var retentionDays: Int? = 30
    
    /// Estimated storage per night
    var estimatedStorageMB: Double {
        if saveFullRecording {
            return 20.0  // ~20MB for 8hrs at 48kbps AAC
        } else if saveSnoringClips {
            return 2.0   // ~2MB for typical 5-10 clips
        }
        return 0.1  // Metadata only
    }
}

// MARK: - Photo Capture Settings

/// Configuration for photo capture
struct PhotoCaptureSettings: Codable, Equatable {
    /// Use front-facing camera
    var useFrontCamera: Bool = false
    
    /// Also save photo to device's Photos library
    var saveToPhotos: Bool = false
    
    /// Compress photo (vs full resolution)
    var compressionQuality: Double = 0.8  // 0-1
}

// MARK: - Video Capture Settings

/// Configuration for video recording
struct VideoCaptureSettings: Codable, Equatable {
    /// Maximum recording duration in seconds
    var maxDuration: TimeInterval = 60.0
    
    /// Video quality preset
    var quality: VideoQuality = .medium
    
    /// Also save to device's Photos library
    var saveToPhotos: Bool = false
}

// MARK: - Main Settings Container

/// Complete media capture configuration for an AtomTemplate
struct MediaCaptureSettings: Codable, Equatable {
    /// Type of media capture
    var captureType: MediaCaptureType
    
    /// Audio-specific settings (only used when captureType == .audio)
    var audioSettings: AudioCaptureSettings?
    
    /// Photo-specific settings (only used when captureType == .photo)
    var photoSettings: PhotoCaptureSettings?
    
    /// Video-specific settings (only used when captureType == .video)
    var videoSettings: VideoCaptureSettings?
    
    // MARK: - Factory Methods
    
    /// Default settings for audio (sleep tracking with snoring detection)
    static var defaultAudio: MediaCaptureSettings {
        MediaCaptureSettings(
            captureType: .audio,
            audioSettings: AudioCaptureSettings()
        )
    }
    
    /// Default settings for photo
    static var defaultPhoto: MediaCaptureSettings {
        MediaCaptureSettings(
            captureType: .photo,
            photoSettings: PhotoCaptureSettings()
        )
    }
    
    /// Default settings for video
    static var defaultVideo: MediaCaptureSettings {
        MediaCaptureSettings(
            captureType: .video,
            videoSettings: VideoCaptureSettings()
        )
    }
    
    // MARK: - JSON Encoding/Decoding
    
    /// Encode to JSON string for storage in SwiftData
    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Decode from JSON string
    static func fromJSON(_ json: String) -> MediaCaptureSettings? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MediaCaptureSettings.self, from: data)
    }
}
