//
//  MediaFileManager.swift
//  Protocol
//
//  Service for managing media files on disk.
//  Media files are stored in Documents/MediaCaptures/ with relative paths saved in SwiftData.
//

import Foundation
import os.log

// MARK: - Storage Report

/// Report of media storage usage
struct MediaStorageReport {
    var photoBytes: Int64 = 0
    var videoBytes: Int64 = 0
    var audioBytes: Int64 = 0
    var snoringClipBytes: Int64 = 0
    
    var totalBytes: Int64 {
        photoBytes + videoBytes + audioBytes + snoringClipBytes
    }
    
    var totalMB: Double {
        Double(totalBytes) / 1_000_000.0
    }
    
    var formattedTotal: String {
        if totalMB >= 1000 {
            return String(format: "%.1f GB", totalMB / 1000.0)
        } else {
            return String(format: "%.1f MB", totalMB)
        }
    }
}

// MARK: - Retention Policy

/// Policy for auto-cleaning old media files
struct MediaRetentionPolicy: Codable {
    /// Days to keep photos (nil = forever)
    var keepPhotosForDays: Int? = nil
    
    /// Days to keep videos (nil = forever)
    var keepVideosForDays: Int? = nil
    
    /// Days to keep audio recordings (nil = forever)
    var keepAudioForDays: Int? = 30
    
    /// If true, only keep snoring clips; delete full audio recordings
    var keepSnoringClipsOnly: Bool = true
    
    /// Default policy: 30 days for audio, keep clips only
    static var `default`: MediaRetentionPolicy {
        MediaRetentionPolicy()
    }
    
    /// Keep everything forever
    static var keepAll: MediaRetentionPolicy {
        MediaRetentionPolicy(
            keepPhotosForDays: nil,
            keepVideosForDays: nil,
            keepAudioForDays: nil,
            keepSnoringClipsOnly: false
        )
    }
}

// MARK: - Media File Error

enum MediaFileError: LocalizedError {
    case directoryCreationFailed(String)
    case fileWriteFailed(String)
    case fileReadFailed(String)
    case fileDeleteFailed(String)
    case fileNotFound(String)
    case insufficientStorage
    case invalidPath
    
    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path):
            return "Failed to create directory: \(path)"
        case .fileWriteFailed(let path):
            return "Failed to write file: \(path)"
        case .fileReadFailed(let path):
            return "Failed to read file: \(path)"
        case .fileDeleteFailed(let path):
            return "Failed to delete file: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .insufficientStorage:
            return "Insufficient storage space"
        case .invalidPath:
            return "Invalid file path"
        }
    }
}

// MARK: - Media File Manager

/// Manages media file storage outside of SwiftData.
/// Files are stored in Documents/MediaCaptures/ with subdirectories for each type.
final class MediaFileManager {
    
    // MARK: - Singleton
    
    static let shared = MediaFileManager()
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.Toofan.Toofanprotocol", category: "MediaFileManager")
    
    /// Root directory for all media captures
    private var mediaRootURL: URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not find documents directory")
        }
        return documentsURL.appendingPathComponent("MediaCaptures", isDirectory: true)
    }
    
    /// Subdirectory for photos
    private var photosURL: URL {
        mediaRootURL.appendingPathComponent("Photos", isDirectory: true)
    }
    
    /// Subdirectory for videos
    private var videosURL: URL {
        mediaRootURL.appendingPathComponent("Videos", isDirectory: true)
    }
    
    /// Subdirectory for audio recordings
    private var audioURL: URL {
        mediaRootURL.appendingPathComponent("Audio", isDirectory: true)
    }
    
    /// Subdirectory for snoring clips
    private var snoringClipsURL: URL {
        audioURL.appendingPathComponent("SnoringClips", isDirectory: true)
    }
    
    /// Lock for thread-safe file operations
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        // Initialize directories on first access
        try? initializeDirectories()
    }
    
    // MARK: - Directory Management
    
    /// Creates all required directories if they don't exist
    func initializeDirectories() throws {
        let directories = [mediaRootURL, photosURL, videosURL, audioURL, snoringClipsURL]
        
        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                do {
                    try fileManager.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true,
                        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                    )
                    logger.info("Created directory: \(directory.lastPathComponent)")
                } catch {
                    logger.error("Failed to create directory \(directory.path): \(error.localizedDescription)")
                    throw MediaFileError.directoryCreationFailed(directory.path)
                }
            }
        }
    }
    
    // MARK: - Save Operations
    
    /// Saves media data to disk and returns the relative path
    /// - Parameters:
    ///   - data: The media data to save
    ///   - type: Type of media (photo, video, audio)
    ///   - atomInstanceID: Associated atom instance ID
    /// - Returns: Relative path from Documents directory
    func saveMedia(data: Data, type: MediaCaptureType, atomInstanceID: UUID) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        // Check available storage
        let requiredSpace = Int64(data.count) + 1_000_000  // 1MB buffer
        guard hasAvailableStorage(bytes: requiredSpace) else {
            logger.error("Insufficient storage for \(data.count) bytes")
            throw MediaFileError.insufficientStorage
        }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename: String
        let directory: URL
        
        switch type {
        case .photo:
            filename = "\(atomInstanceID.uuidString)_\(timestamp).jpg"
            directory = photosURL
        case .video:
            filename = "\(atomInstanceID.uuidString)_\(timestamp).mp4"
            directory = videosURL
        case .audio:
            filename = "\(atomInstanceID.uuidString)_\(timestamp).m4a"
            directory = audioURL
        }
        
        let fileURL = directory.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            logger.info("Saved \(type.rawValue) file: \(filename) (\(data.count) bytes)")
            
            // Return relative path from Documents
            return relativePath(from: fileURL)
        } catch {
            logger.error("Failed to write \(type.rawValue) file: \(error.localizedDescription)")
            throw MediaFileError.fileWriteFailed(fileURL.path)
        }
    }
    
    /// Saves media file from a temporary URL to permanent storage
    func saveMedia(from sourceURL: URL, type: MediaCaptureType, atomInstanceID: UUID) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        // Calculate file size
        let resources = try? sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(resources?.fileSize ?? 0)
        
        guard hasAvailableStorage(bytes: fileSize) else {
            logger.error("Insufficient storage for \(fileSize) bytes")
            throw MediaFileError.insufficientStorage
        }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename: String
        let directory: URL
        
        switch type {
        case .photo:
            filename = "\(atomInstanceID.uuidString)_\(timestamp).jpg"
            directory = photosURL
        case .video:
            filename = "\(atomInstanceID.uuidString)_\(timestamp).mp4"
            directory = videosURL
        case .audio:
            filename = "\(atomInstanceID.uuidString)_\(timestamp).m4a"
            directory = audioURL
        }
        
        let destinationURL = directory.appendingPathComponent(filename)
        
        do {
            // Move file if possible, otherwise copy
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            logger.info("Moved \(type.rawValue) file: \(filename) (\(fileSize) bytes)")
            
            return relativePath(from: destinationURL)
        } catch {
            logger.error("Failed to move \(type.rawValue) file: \(error.localizedDescription)")
            // Try copy if move fails
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                return relativePath(from: destinationURL)
            } catch {
                throw MediaFileError.fileWriteFailed(destinationURL.path)
            }
        }
    }
    
    /// Saves a snoring clip and returns the relative path
    func saveSnoringClip(data: Data, eventID: UUID) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(eventID.uuidString)_\(timestamp).m4a"
        let fileURL = snoringClipsURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            logger.info("Saved snoring clip: \(filename) (\(data.count) bytes)")
            return relativePath(from: fileURL)
        } catch {
            logger.error("Failed to write snoring clip: \(error.localizedDescription)")
            throw MediaFileError.fileWriteFailed(fileURL.path)
        }
    }
    
    // MARK: - Load Operations
    
    /// Loads media data from a relative path
    func loadMedia(relativePath: String) throws -> Data {
        let fileURL = absoluteURL(from: relativePath)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.warning("File not found: \(relativePath)")
            throw MediaFileError.fileNotFound(relativePath)
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return data
        } catch {
            logger.error("Failed to read file \(relativePath): \(error.localizedDescription)")
            throw MediaFileError.fileReadFailed(relativePath)
        }
    }
    
    /// Returns the absolute URL for playback (e.g., for AVPlayer)
    func absoluteURL(for relativePath: String) -> URL {
        absoluteURL(from: relativePath)
    }
    
    /// Checks if a file exists at the given relative path
    func fileExists(at relativePath: String) -> Bool {
        let fileURL = absoluteURL(from: relativePath)
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    // MARK: - Delete Operations
    
    /// Deletes a media file at the given relative path
    func deleteMedia(relativePath: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let fileURL = absoluteURL(from: relativePath)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            // File already gone, not an error
            logger.debug("File already deleted: \(relativePath)")
            return
        }
        
        do {
            try fileManager.removeItem(at: fileURL)
            logger.info("Deleted file: \(relativePath)")
        } catch {
            logger.error("Failed to delete file \(relativePath): \(error.localizedDescription)")
            throw MediaFileError.fileDeleteFailed(relativePath)
        }
    }
    
    /// Deletes all media files for a specific atom instance
    func deleteAllMedia(for atomInstanceID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let prefix = atomInstanceID.uuidString
        var deletedCount = 0
        
        // Search all directories
        let directories = [photosURL, videosURL, audioURL, snoringClipsURL]
        
        for directory in directories {
            guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
                continue
            }
            
            for fileURL in contents where fileURL.lastPathComponent.hasPrefix(prefix) {
                try? fileManager.removeItem(at: fileURL)
                deletedCount += 1
            }
        }
        
        logger.info("Deleted \(deletedCount) files for atom \(prefix)")
    }
    
    // MARK: - Storage Reporting
    
    /// Calculates storage usage for all media types
    func calculateStorageUsage() -> MediaStorageReport {
        var report = MediaStorageReport()
        
        report.photoBytes = calculateDirectorySize(photosURL)
        report.videoBytes = calculateDirectorySize(videosURL)
        report.audioBytes = calculateDirectorySize(audioURL) - calculateDirectorySize(snoringClipsURL)
        report.snoringClipBytes = calculateDirectorySize(snoringClipsURL)
        
        return report
    }
    
    // MARK: - Cleanup
    
    /// Cleans up old media files based on retention policy
    func cleanupOldMedia(policy: MediaRetentionPolicy) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        var deletedCount = 0
        var bytesFreed: Int64 = 0
        
        // Cleanup photos
        if let days = policy.keepPhotosForDays {
            let (count, bytes) = cleanupDirectory(photosURL, olderThanDays: days, from: now)
            deletedCount += count
            bytesFreed += bytes
        }
        
        // Cleanup videos
        if let days = policy.keepVideosForDays {
            let (count, bytes) = cleanupDirectory(videosURL, olderThanDays: days, from: now)
            deletedCount += count
            bytesFreed += bytes
        }
        
        // Cleanup audio (excluding snoring clips subdirectory)
        if let days = policy.keepAudioForDays {
            let (count, bytes) = cleanupDirectory(audioURL, olderThanDays: days, from: now, excludeSubdirectories: true)
            deletedCount += count
            bytesFreed += bytes
        }
        
        // Cleanup snoring clips separately if needed
        if policy.keepSnoringClipsOnly {
            // Delete full audio recordings but keep clips
            // Already handled above with excludeSubdirectories
        } else if let days = policy.keepAudioForDays {
            let (count, bytes) = cleanupDirectory(snoringClipsURL, olderThanDays: days, from: now)
            deletedCount += count
            bytesFreed += bytes
        }
        
        let freedMB = Double(bytesFreed) / 1_000_000.0
        logger.info("Cleanup complete: \(deletedCount) files deleted, \(String(format: "%.1f", freedMB)) MB freed")
    }
    
    // MARK: - Private Helpers
    
    private func relativePath(from absoluteURL: URL) -> String {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return absoluteURL.lastPathComponent
        }
        let absolutePath = absoluteURL.path
        let documentsPath = documentsURL.path
        
        if absolutePath.hasPrefix(documentsPath) {
            // Return path relative to Documents
            let startIndex = absolutePath.index(absolutePath.startIndex, offsetBy: documentsPath.count + 1)
            return String(absolutePath[startIndex...])
        }
        
        return absoluteURL.lastPathComponent
    }
    
    private func absoluteURL(from relativePath: String) -> URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: relativePath)
        }
        return documentsURL.appendingPathComponent(relativePath)
    }
    
    private func hasAvailableStorage(bytes: Int64) -> Bool {
        do {
            guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return true // Assume available if can't check
            }
            let values = try documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let availableCapacity = values.volumeAvailableCapacityForImportantUsage {
                return availableCapacity > bytes
            }
        } catch {
            logger.warning("Could not check available storage: \(error.localizedDescription)")
        }
        // Assume we have space if check fails
        return true
    }
    
    private func calculateDirectorySize(_ directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if values.isDirectory == false {
                    totalSize += Int64(values.fileSize ?? 0)
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    private func cleanupDirectory(_ directory: URL, olderThanDays: Int, from date: Date, excludeSubdirectories: Bool = false) -> (count: Int, bytes: Int64) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: date)!
        var deletedCount = 0
        var bytesFreed: Int64 = 0
        
        for fileURL in contents {
            do {
                let values = try fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey, .isDirectoryKey])
                
                // Skip subdirectories if requested
                if excludeSubdirectories && values.isDirectory == true {
                    continue
                }
                
                guard let creationDate = values.creationDate,
                      creationDate < cutoffDate else {
                    continue
                }
                
                let fileSize = Int64(values.fileSize ?? 0)
                try fileManager.removeItem(at: fileURL)
                deletedCount += 1
                bytesFreed += fileSize
                
            } catch {
                continue
            }
        }
        
        return (deletedCount, bytesFreed)
    }
}
