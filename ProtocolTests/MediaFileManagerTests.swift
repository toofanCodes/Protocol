//
//  MediaFileManagerTests.swift
//  ProtocolTests
//
//  Unit tests for MediaFileManager service.
//

import XCTest
@testable import Protocol

final class MediaFileManagerTests: XCTestCase {
    
    var fileManager: MediaFileManager!
    var testDirectory: URL!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = MediaFileManager.shared
        
        // Create temp test directory
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaFileManagerTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        // Clean up test directory
        if FileManager.default.fileExists(atPath: testDirectory.path) {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try super.tearDownWithError()
    }
    
    // MARK: - Storage Report Tests
    
    func testMediaStorageReportTotalBytes() {
        var report = MediaStorageReport()
        report.photoBytes = 1_000_000  // 1 MB
        report.videoBytes = 2_000_000  // 2 MB
        report.audioBytes = 500_000    // 0.5 MB
        report.snoringClipBytes = 100_000  // 0.1 MB
        
        XCTAssertEqual(report.totalBytes, 3_600_000)
    }
    
    func testMediaStorageReportTotalMB() {
        var report = MediaStorageReport()
        report.photoBytes = 5_000_000  // 5 MB
        
        XCTAssertEqual(report.totalMB, 5.0)
    }
    
    func testMediaStorageReportFormattedTotal() {
        var report = MediaStorageReport()
        
        // MB format
        report.photoBytes = 50_000_000  // 50 MB
        XCTAssertEqual(report.formattedTotal, "50.0 MB")
        
        // GB format
        report.photoBytes = 1_500_000_000  // 1.5 GB
        XCTAssertEqual(report.formattedTotal, "1.5 GB")
    }
    
    // MARK: - Retention Policy Tests
    
    func testRetentionPolicyDefault() {
        let policy = MediaRetentionPolicy.default
        
        XCTAssertNil(policy.keepPhotosForDays)
        XCTAssertNil(policy.keepVideosForDays)
        XCTAssertEqual(policy.keepAudioForDays, 30)
        XCTAssertTrue(policy.keepSnoringClipsOnly)
    }
    
    func testRetentionPolicyKeepAll() {
        let policy = MediaRetentionPolicy.keepAll
        
        XCTAssertNil(policy.keepPhotosForDays)
        XCTAssertNil(policy.keepVideosForDays)
        XCTAssertNil(policy.keepAudioForDays)
        XCTAssertFalse(policy.keepSnoringClipsOnly)
    }
    
    func testRetentionPolicyCodable() throws {
        let original = MediaRetentionPolicy(
            keepPhotosForDays: 7,
            keepVideosForDays: 14,
            keepAudioForDays: 30,
            keepSnoringClipsOnly: true
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MediaRetentionPolicy.self, from: data)
        
        XCTAssertEqual(decoded.keepPhotosForDays, 7)
        XCTAssertEqual(decoded.keepVideosForDays, 14)
        XCTAssertEqual(decoded.keepAudioForDays, 30)
        XCTAssertTrue(decoded.keepSnoringClipsOnly)
    }
    
    // MARK: - Error Tests
    
    func testMediaFileErrorDescriptions() {
        let errors: [MediaFileError] = [
            .directoryCreationFailed("/test/path"),
            .fileWriteFailed("/test/file.m4a"),
            .fileReadFailed("/test/file.m4a"),
            .fileDeleteFailed("/test/file.m4a"),
            .fileNotFound("/test/file.m4a"),
            .insufficientStorage,
            .invalidPath
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
    
    // MARK: - File Existence Tests
    
    func testFileExistsReturnsFalseForMissingFile() {
        let result = fileManager.fileExists(at: "nonexistent/path/file.m4a")
        XCTAssertFalse(result)
    }
    
    // MARK: - Storage Calculation Tests
    
    func testCalculateStorageUsageReturnsReport() {
        let report = fileManager.calculateStorageUsage()
        
        // Should return valid report (all zeros if no files, or actual values)
        XCTAssertGreaterThanOrEqual(report.photoBytes, 0)
        XCTAssertGreaterThanOrEqual(report.videoBytes, 0)
        XCTAssertGreaterThanOrEqual(report.audioBytes, 0)
        XCTAssertGreaterThanOrEqual(report.snoringClipBytes, 0)
    }
    
    // MARK: - Report Extension Tests
    
    func testStorageReportBreakdown() {
        var report = MediaStorageReport()
        report.photoBytes = 10_000_000
        report.videoBytes = 20_000_000
        report.audioBytes = 5_000_000
        report.snoringClipBytes = 1_000_000
        
        let breakdown = report.formattedBreakdown
        
        XCTAssertTrue(breakdown.contains("Photos: 10.0 MB"))
        XCTAssertTrue(breakdown.contains("Videos: 20.0 MB"))
        XCTAssertTrue(breakdown.contains("Audio: 5.0 MB"))
        XCTAssertTrue(breakdown.contains("Clips: 1.0 MB"))
    }
    
    func testStorageReportEmptyBreakdown() {
        let report = MediaStorageReport()
        XCTAssertEqual(report.formattedBreakdown, "No media")
    }
}
