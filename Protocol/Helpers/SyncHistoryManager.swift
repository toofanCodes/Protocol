//
//  SyncHistoryManager.swift
//  Protocol
//
//  Manages persisted sync history with rolling window and JSON export.
//

import Foundation

/// Manages sync history persistence and retrieval
@MainActor
final class SyncHistoryManager {
    
    // MARK: - Singleton
    
    static let shared = SyncHistoryManager()
    
    // MARK: - Configuration
    
    private let historyFilename = "sync_history.json"
    private let maxEntries = 100
    
    // MARK: - State
    
    private(set) var entries: [SyncHistoryEntry] = []
    
    // MARK: - Initialization
    
    private init() {
        loadFromFile()
    }
    
    // MARK: - Public API
    
    /// Records a sync event to persistent history
    func recordSync(
        action: SyncHistoryEntry.SyncAction,
        status: SyncHistoryEntry.SyncResult,
        uploaded: Int = 0,
        downloaded: Int = 0,
        duration: TimeInterval = 0,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        details: String = ""
    ) {
        let entry = SyncHistoryEntry(
            action: action,
            status: status,
            details: details,
            recordsUploaded: uploaded,
            recordsDownloaded: downloaded,
            durationMs: Int(duration * 1000),
            errorCode: errorCode,
            errorMessage: errorMessage
        )
        
        entries.insert(entry, at: 0)
        
        // Enforce rolling window
        if self.entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        
        saveToFile()
        
        AppLogger.sync.info("📝 Recorded sync: \(status.rawValue) (\(action.rawValue))")
    }
    
    /// Exports history as JSON data for sharing/debugging
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(entries)
    }
    
    /// Clears all history
    func clearHistory() {
        entries.removeAll()
        saveToFile()
        AppLogger.sync.info("🗑️ Sync history cleared")
    }
    
    /// Returns entries filtered by result type
    func entries(matching status: SyncHistoryEntry.SyncResult) -> [SyncHistoryEntry] {
        entries.filter { $0.status == status }
    }
    
    /// Returns the most recent entry
    var lastSync: SyncHistoryEntry? {
        entries.first
    }
    
    /// Returns the most recent successful sync
    var lastSuccessfulSync: SyncHistoryEntry? {
        entries.first { $0.status == .success }
    }
    
    // MARK: - Private: File I/O
    
    private var historyFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(historyFilename)
    }
    
    private func loadFromFile() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else {
            AppLogger.sync.debug("No sync history file found, starting fresh")
            return
        }
        
        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([SyncHistoryEntry].self, from: data)
            AppLogger.sync.debug("Loaded \(self.entries.count) sync history entries")
        } catch {
            AppLogger.sync.error("Failed to load sync history: \(error.localizedDescription)")
            entries = []
        }
    }
    
    private func saveToFile() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            AppLogger.sync.error("Failed to save sync history: \(error.localizedDescription)")
        }
    }
}
