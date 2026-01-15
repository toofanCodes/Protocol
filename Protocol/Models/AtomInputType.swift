//
//  AtomInputType.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation

/// Defines the input type for an Atom (task)
/// This determines how the user interacts with the task
enum AtomInputType: String, Codable, CaseIterable, Identifiable {
    /// Binary = Checkbox (Done/Not Done)
    case binary = "binary"
    
    /// Counter = Incremental (e.g., 0/5 glasses of water)
    case counter = "counter"
    
    /// Value = Numeric Entry (e.g., Weight: 91kg)
    case value = "value"
    
    /// Photo = Capture a photo to complete
    case photo = "photo"
    
    /// Video = Record a video to complete
    case video = "video"
    
    /// Audio = Record audio (e.g., sleep tracking with snoring detection)
    case audio = "audio"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .binary: return "Checkbox"
        case .counter: return "Counter"
        case .value: return "Value Entry"
        case .photo: return "Photo"
        case .video: return "Video"
        case .audio: return "Audio Recording"
        }
    }
    
    var description: String {
        switch self {
        case .binary: return "Simple done/not done"
        case .counter: return "Track progress (e.g., 3/5)"
        case .value: return "Enter a number (e.g., weight)"
        case .photo: return "Take a photo to complete"
        case .video: return "Record a video to complete"
        case .audio: return "Sleep tracking with snoring detection"
        }
    }
    
    var iconName: String {
        switch self {
        case .binary: return "checkmark.circle"
        case .counter: return "number.circle"
        case .value: return "textformat.123"
        case .photo: return "camera.fill"
        case .video: return "video.fill"
        case .audio: return "mic.fill"
        }
    }
    
    /// Whether this is a media capture type
    var isMediaType: Bool {
        switch self {
        case .photo, .video, .audio:
            return true
        default:
            return false
        }
    }
    
    /// Convert to MediaCaptureType if applicable
    var mediaCaptureType: MediaCaptureType? {
        switch self {
        case .photo: return .photo
        case .video: return .video
        case .audio: return .audio
        default: return nil
        }
    }
}
