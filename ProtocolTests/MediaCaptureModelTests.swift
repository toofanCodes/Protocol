//
//  MediaCaptureModelTests.swift
//  ProtocolTests
//
//  Unit tests for MediaCapture and SnoringEvent models.
//

import XCTest
@testable import Protocol

final class MediaCaptureModelTests: XCTestCase {
    
    // MARK: - MediaCapture Tests
    
    func testMediaCaptureInitialization() {
        let capture = MediaCapture()
        
        XCTAssertNotNil(capture.id)
        XCTAssertEqual(capture.captureType, "photo")
        XCTAssertNil(capture.mediaFileURL)
        XCTAssertNil(capture.snoringScore)
        XCTAssertTrue(capture.snoringEvents.isEmpty)
    }
    
    func testAudioCaptureInitialization() {
        let startTime = Date()
        let endTime = Date().addingTimeInterval(3600) // 1 hour later
        
        let capture = MediaCapture(
            audioRecordingStartTime: startTime,
            audioRecordingEndTime: endTime,
            snoringScore: 45.5,
            totalSnoringDuration: 1800, // 30 mins
            snoringEventCount: 12
        )
        
        XCTAssertEqual(capture.captureType, "audio")
        XCTAssertEqual(capture.recordingStartTime, startTime)
        XCTAssertEqual(capture.recordingEndTime, endTime)
        XCTAssertEqual(capture.snoringScore, 45.5)
        XCTAssertEqual(capture.totalSnoringDuration, 1800)
        XCTAssertEqual(capture.snoringEventCount, 12)
        XCTAssertEqual(capture.totalDuration, 3600, accuracy: 1)
    }
    
    func testMediaCaptureType() {
        let photoCapture = MediaCapture(captureType: "photo")
        let videoCapture = MediaCapture(captureType: "video")
        let audioCapture = MediaCapture(captureType: "audio")
        
        XCTAssertEqual(photoCapture.type, .photo)
        XCTAssertEqual(videoCapture.type, .video)
        XCTAssertEqual(audioCapture.type, .audio)
    }
    
    func testDurationString() {
        let capture = MediaCapture(
            audioRecordingStartTime: Date(),
            audioRecordingEndTime: Date().addingTimeInterval(7230) // 2h 0m 30s
        )
        
        XCTAssertEqual(capture.durationString, "2h 0m")
    }
    
    func testSnoringScoreString() {
        let capture = MediaCapture()
        capture.snoringScore = 67.8
        
        XCTAssertEqual(capture.snoringScoreString, "67%")
    }
    
    func testSnoringCategory() {
        let test: [(Double, SnoringCategory)] = [
            (0, .minimal),
            (15, .minimal),
            (25, .light),
            (45, .moderate),
            (65, .heavy),
            (85, .severe)
        ]
        
        for (score, expected) in test {
            let capture = MediaCapture()
            capture.snoringScore = score
            XCTAssertEqual(capture.snoringCategory, expected, "Score \(score) should be \(expected)")
        }
    }
    
    func testSnoringCategoryWithNoScore() {
        let capture = MediaCapture()
        XCTAssertEqual(capture.snoringCategory, .none)
    }
    
    // MARK: - SnoringEvent Tests
    
    func testSnoringEventInitialization() {
        let timestamp = Date()
        
        let event = SnoringEvent(
            timestamp: timestamp,
            duration: 15.5,
            intensity: 72.3,
            audioClipURL: "Audio/SnoringClips/test.m4a"
        )
        
        XCTAssertNotNil(event.id)
        XCTAssertEqual(event.timestamp, timestamp)
        XCTAssertEqual(event.duration, 15.5)
        XCTAssertEqual(event.intensity, 72.3)
        XCTAssertEqual(event.audioClipURL, "Audio/SnoringClips/test.m4a")
    }
    
    func testSnoringEventDurationString() {
        let shortEvent = SnoringEvent(duration: 45)
        let longEvent = SnoringEvent(duration: 125)
        
        XCTAssertEqual(shortEvent.durationString, "45s")
        XCTAssertEqual(longEvent.durationString, "2m 5s")
    }
    
    func testSnoringEventIntensityCategory() {
        let lowEvent = SnoringEvent(intensity: 20)
        let mediumEvent = SnoringEvent(intensity: 45)
        let highEvent = SnoringEvent(intensity: 75)
        
        XCTAssertEqual(lowEvent.intensityCategory, "Low")
        XCTAssertEqual(mediumEvent.intensityCategory, "Medium")
        XCTAssertEqual(highEvent.intensityCategory, "High")
    }
    
    func testSnoringEventTimeOffset() {
        let recordingStart = Date()
        let eventTime = recordingStart.addingTimeInterval(3600) // 1 hour in
        
        let event = SnoringEvent(timestamp: eventTime)
        let offset = event.timeOffset(from: recordingStart)
        
        XCTAssertEqual(offset, 3600, accuracy: 0.1)
    }
    
    // MARK: - Hashable Tests
    
    func testMediaCaptureHashable() {
        let capture1 = MediaCapture()
        let capture2 = MediaCapture()
        
        var set = Set<MediaCapture>()
        set.insert(capture1)
        set.insert(capture2)
        set.insert(capture1) // Duplicate
        
        XCTAssertEqual(set.count, 2)
    }
    
    func testSnoringEventHashable() {
        let event1 = SnoringEvent()
        let event2 = SnoringEvent()
        
        var set = Set<SnoringEvent>()
        set.insert(event1)
        set.insert(event2)
        set.insert(event1) // Duplicate
        
        XCTAssertEqual(set.count, 2)
    }
}
