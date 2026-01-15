//
//  MediaCaptureSettingsTests.swift
//  ProtocolTests
//
//  Unit tests for MediaCaptureSettings and related Codable structs.
//

import XCTest
@testable import Protocol

final class MediaCaptureSettingsTests: XCTestCase {
    
    // MARK: - MediaCaptureType Tests
    
    func testMediaCaptureTypeDisplayName() {
        XCTAssertEqual(MediaCaptureType.photo.displayName, "Photo")
        XCTAssertEqual(MediaCaptureType.video.displayName, "Video")
        XCTAssertEqual(MediaCaptureType.audio.displayName, "Audio")
    }
    
    func testMediaCaptureTypeSystemImage() {
        XCTAssertEqual(MediaCaptureType.photo.systemImage, "camera.fill")
        XCTAssertEqual(MediaCaptureType.video.systemImage, "video.fill")
        XCTAssertEqual(MediaCaptureType.audio.systemImage, "mic.fill")
    }
    
    // MARK: - RecordingDuration Tests
    
    func testRecordingDurationDisplayString() {
        XCTAssertEqual(RecordingDuration.manual.displayString, "Manual")
        XCTAssertEqual(RecordingDuration.fixed(minutes: 30).displayString, "30 min")
        XCTAssertEqual(RecordingDuration.fixed(minutes: 60).displayString, "1 hour")
        XCTAssertEqual(RecordingDuration.fixed(minutes: 90).displayString, "1h 30m")
        XCTAssertEqual(RecordingDuration.fixed(minutes: 120).displayString, "2 hours")
    }
    
    func testRecordingDurationPresets() {
        let presets = RecordingDuration.presets
        XCTAssertTrue(presets.count >= 5, "Should have at least 5 presets")
        XCTAssertEqual(presets.first, .manual)
    }
    
    func testRecordingDurationEquatable() {
        XCTAssertEqual(RecordingDuration.manual, RecordingDuration.manual)
        XCTAssertEqual(RecordingDuration.fixed(minutes: 60), RecordingDuration.fixed(minutes: 60))
        XCTAssertNotEqual(RecordingDuration.fixed(minutes: 30), RecordingDuration.fixed(minutes: 60))
        XCTAssertEqual(RecordingDuration.untilTime(hour: 7, minute: 0), RecordingDuration.untilTime(hour: 7, minute: 0))
    }
    
    // MARK: - VideoQuality Tests
    
    func testVideoQualityDisplayName() {
        XCTAssertEqual(VideoQuality.low.displayName, "Low (480p)")
        XCTAssertEqual(VideoQuality.medium.displayName, "Medium (720p)")
        XCTAssertEqual(VideoQuality.high.displayName, "High (1080p)")
    }
    
    // MARK: - AudioCaptureSettings Tests
    
    func testAudioCaptureSettingsDefaults() {
        let settings = AudioCaptureSettings()
        
        XCTAssertTrue(settings.enableSnoringDetection)
        XCTAssertEqual(settings.recordingDuration, .fixed(minutes: 480))
        XCTAssertFalse(settings.saveFullRecording)
        XCTAssertTrue(settings.saveSnoringClips)
        XCTAssertEqual(settings.sensitivityThreshold, 40.0)
        XCTAssertEqual(settings.retentionDays, 30)
    }
    
    func testAudioCaptureSettingsEstimatedStorage() {
        var settings = AudioCaptureSettings()
        
        // Full recording
        settings.saveFullRecording = true
        XCTAssertEqual(settings.estimatedStorageMB, 20.0)
        
        // Clips only
        settings.saveFullRecording = false
        settings.saveSnoringClips = true
        XCTAssertEqual(settings.estimatedStorageMB, 2.0)
        
        // Metadata only
        settings.saveSnoringClips = false
        XCTAssertEqual(settings.estimatedStorageMB, 0.1)
    }
    
    // MARK: - PhotoCaptureSettings Tests
    
    func testPhotoCaptureSettingsDefaults() {
        let settings = PhotoCaptureSettings()
        
        XCTAssertFalse(settings.useFrontCamera)
        XCTAssertFalse(settings.saveToPhotos)
        XCTAssertEqual(settings.compressionQuality, 0.8)
    }
    
    // MARK: - VideoCaptureSettings Tests
    
    func testVideoCaptureSettingsDefaults() {
        let settings = VideoCaptureSettings()
        
        XCTAssertEqual(settings.maxDuration, 60.0)
        XCTAssertEqual(settings.quality, .medium)
        XCTAssertFalse(settings.saveToPhotos)
    }
    
    // MARK: - MediaCaptureSettings Tests
    
    func testDefaultAudioSettings() {
        let settings = MediaCaptureSettings.defaultAudio
        
        XCTAssertEqual(settings.captureType, .audio)
        XCTAssertNotNil(settings.audioSettings)
        XCTAssertNil(settings.photoSettings)
        XCTAssertNil(settings.videoSettings)
    }
    
    func testDefaultPhotoSettings() {
        let settings = MediaCaptureSettings.defaultPhoto
        
        XCTAssertEqual(settings.captureType, .photo)
        XCTAssertNil(settings.audioSettings)
        XCTAssertNotNil(settings.photoSettings)
        XCTAssertNil(settings.videoSettings)
    }
    
    func testDefaultVideoSettings() {
        let settings = MediaCaptureSettings.defaultVideo
        
        XCTAssertEqual(settings.captureType, .video)
        XCTAssertNil(settings.audioSettings)
        XCTAssertNil(settings.photoSettings)
        XCTAssertNotNil(settings.videoSettings)
    }
    
    // MARK: - JSON Encoding/Decoding Tests
    
    func testMediaCaptureSettingsJSONRoundTrip() {
        let original = MediaCaptureSettings.defaultAudio
        
        guard let json = original.toJSON() else {
            XCTFail("Failed to encode to JSON")
            return
        }
        
        guard let decoded = MediaCaptureSettings.fromJSON(json) else {
            XCTFail("Failed to decode from JSON")
            return
        }
        
        XCTAssertEqual(decoded.captureType, original.captureType)
        XCTAssertEqual(decoded.audioSettings?.enableSnoringDetection, original.audioSettings?.enableSnoringDetection)
        XCTAssertEqual(decoded.audioSettings?.sensitivityThreshold, original.audioSettings?.sensitivityThreshold)
    }
    
    func testMediaCaptureSettingsJSONWithCustomValues() {
        var settings = MediaCaptureSettings.defaultAudio
        settings.audioSettings?.enableSnoringDetection = true
        settings.audioSettings?.sensitivityThreshold = 75
        settings.audioSettings?.recordingDuration = .untilTime(hour: 7, minute: 30)
        settings.audioSettings?.saveFullRecording = true
        
        guard let json = settings.toJSON(),
              let decoded = MediaCaptureSettings.fromJSON(json) else {
            XCTFail("JSON round-trip failed")
            return
        }
        
        XCTAssertEqual(decoded.audioSettings?.sensitivityThreshold, 75)
        XCTAssertEqual(decoded.audioSettings?.saveFullRecording, true)
    }
    
    func testInvalidJSONReturnsNil() {
        let invalidJSON = "{ this is not valid JSON }"
        let result = MediaCaptureSettings.fromJSON(invalidJSON)
        XCTAssertNil(result)
    }
    
    // MARK: - Codable Conformance Tests
    
    func testRecordingDurationCodable() throws {
        let durations: [RecordingDuration] = [
            .manual,
            .fixed(minutes: 60),
            .untilTime(hour: 7, minute: 0)
        ]
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for original in durations {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(RecordingDuration.self, from: data)
            XCTAssertEqual(decoded, original)
        }
    }
}
