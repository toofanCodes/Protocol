//
//  AuditLogger.swift
//  Protocol
//
//  Comprehensive audit logging for all data operations.
//  Tracks create, update, delete operations with field-level change tracking.
//

import Foundation

// MARK: - Audit Log Models
// Moved to Models/PersistentAuditLog.swift for visibility

/// A single audit log entry
struct AuditLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let operation: AuditOperation
    let entityType: AuditEntityType
    let entityId: String
    let entityName: String?
    let changes: [FieldChange]?
    let callSite: String
    let additionalInfo: String?
    
    init(
        operation: AuditOperation,
        entityType: AuditEntityType,
        entityId: String,
        entityName: String? = nil,
        changes: [FieldChange]? = nil,
        callSite: String,
        additionalInfo: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.operation = operation
        self.entityType = entityType
        self.entityId = entityId
        self.entityName = entityName
        self.changes = changes
        self.callSite = callSite
        self.additionalInfo = additionalInfo
    }
    
    /// Human-readable summary for list display
    var summary: String {
        switch operation {
        case .create:
            return "Created \(entityType.rawValue): \(entityName ?? entityId)"
        case .update:
            let fieldCount = changes?.count ?? 0
            return "Updated \(entityType.rawValue): \(entityName ?? entityId) (\(fieldCount) field\(fieldCount == 1 ? "" : "s"))"
        case .delete:
            return "Deleted \(entityType.rawValue): \(entityName ?? entityId)"
        case .bulkCreate:
            return "Bulk created \(entityType.rawValue)s"
        case .bulkDelete:
            return "Bulk deleted \(entityType.rawValue)s"
        }
    }
    
    /// Formatted timestamp for display
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}

// FieldChange struct moved to Models/PersistentAuditLog.swift

// MARK: - AuditLogger

/// Singleton service for audit logging
/// Thread-safe, persists to JSON file, auto-prunes old entries
actor AuditLogger {
    
    // MARK: - Singleton
    
    static let shared = AuditLogger()
    
    // MARK: - Constants
    
    private let maxEntries = 1000
    private let maxAgeDays = 7
    private let fileName = "audit_log.json"
    
    // MARK: - Properties
    
    private var entries: [AuditLogEntry] = []
    private var isLoaded = false
    
    // MARK: - Initialization
    
    private init() {
        // Load happens lazily on first access
    }
    
    // MARK: - Public API
    
    /// Logs a create operation
    func logCreate(
        entityType: AuditEntityType,
        entityId: String,
        entityName: String? = nil,
        additionalInfo: String? = nil,
        file: String = #file,
        line: Int = #line
    ) async {
        let callSite = formatCallSite(file: file, line: line)
        let entry = AuditLogEntry(
            operation: .create,
            entityType: entityType,
            entityId: entityId,
            entityName: entityName,
            callSite: callSite,
            additionalInfo: additionalInfo
        )
        await addEntry(entry)
    }
    
    /// Logs an update operation with field changes
    func logUpdate(
        entityType: AuditEntityType,
        entityId: String,
        entityName: String? = nil,
        changes: [FieldChange],
        additionalInfo: String? = nil,
        file: String = #file,
        line: Int = #line
    ) async {
        let callSite = formatCallSite(file: file, line: line)
        let entry = AuditLogEntry(
            operation: .update,
            entityType: entityType,
            entityId: entityId,
            entityName: entityName,
            changes: changes,
            callSite: callSite,
            additionalInfo: additionalInfo
        )
        await addEntry(entry)
    }
    
    /// Logs a delete operation
    func logDelete(
        entityType: AuditEntityType,
        entityId: String,
        entityName: String? = nil,
        additionalInfo: String? = nil,
        file: String = #file,
        line: Int = #line
    ) async {
        let callSite = formatCallSite(file: file, line: line)
        let entry = AuditLogEntry(
            operation: .delete,
            entityType: entityType,
            entityId: entityId,
            entityName: entityName,
            callSite: callSite,
            additionalInfo: additionalInfo
        )
        await addEntry(entry)
    }
    
    /// Logs a bulk create operation
    func logBulkCreate(
        entityType: AuditEntityType,
        count: Int,
        additionalInfo: String? = nil,
        file: String = #file,
        line: Int = #line
    ) async {
        let callSite = formatCallSite(file: file, line: line)
        let entry = AuditLogEntry(
            operation: .bulkCreate,
            entityType: entityType,
            entityId: "bulk-\(count)",
            entityName: "\(count) items",
            callSite: callSite,
            additionalInfo: additionalInfo
        )
        await addEntry(entry)
    }
    
    /// Logs a bulk delete operation
    func logBulkDelete(
        entityType: AuditEntityType,
        count: Int,
        additionalInfo: String? = nil,
        file: String = #file,
        line: Int = #line
    ) async {
        let callSite = formatCallSite(file: file, line: line)
        let entry = AuditLogEntry(
            operation: .bulkDelete,
            entityType: entityType,
            entityId: "bulk-\(count)",
            entityName: "\(count) items",
            callSite: callSite,
            additionalInfo: additionalInfo
        )
        await addEntry(entry)
    }
    
    /// Returns all log entries (most recent first)
    func getEntries() async -> [AuditLogEntry] {
        await loadIfNeeded()
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Returns entries as JSON data for export
    func exportAsJSON() async -> Data? {
        await loadIfNeeded()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(entries)
    }
    
    /// Clears all log entries
    func clearAll() async {
        entries.removeAll()
        await save()
    }
    
    // MARK: - Private Methods
    
    private func addEntry(_ entry: AuditLogEntry) async {
        await loadIfNeeded()
        entries.append(entry)
        await prune()
        await save()
        
        // Debug print
        AppLogger.audit.info("📋 AUDIT: \(entry.summary) [\(entry.callSite)]")
    }
    
    private func formatCallSite(file: String, line: Int) -> String {
        let fileName = (file as NSString).lastPathComponent
        return "\(fileName):\(line)"
    }
    
    private func prune() async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date())!
        
        // Remove old entries
        entries.removeAll { $0.timestamp < cutoffDate }
        
        // Trim to max count (keep most recent)
        if entries.count > maxEntries {
            entries.sort { $0.timestamp > $1.timestamp }
            entries = Array(entries.prefix(maxEntries))
        }
    }
    
    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        isLoaded = true
        
        let url = getLogFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([AuditLogEntry].self, from: data)
        } catch {
            AppLogger.audit.error("⚠️ Failed to load audit log: \(error.localizedDescription)")
            entries = []
        }
    }
    
    private func save() async {
        let url = getLogFileURL()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        // Capture current state to avoid actor isolation issues in closure
        let entriesToSave = self.entries
        
        do {
            let data = try encoder.encode(entriesToSave)
            
            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    } catch {
                        // Note: Depending on AppLogger implementation, this might need to be isolated.
                        // Assuming OSLog/Logger which is thread-safe.
                        print("⚠️ Failed to save audit log: \(error.localizedDescription)")
                    }
                    continuation.resume()
                }
            }
        } catch {
            AppLogger.audit.error("⚠️ Failed to encode audit log: \(error.localizedDescription)")
        }
    }
    
    private func getLogFileURL() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent(fileName)
    }
}

// MARK: - Convenience Extensions

extension AuditLogger {
    /// Creates field changes from comparing two values
    static func fieldChange(_ field: String, old: String?, new: String?) -> FieldChange? {
        guard old != new else { return nil }
        return FieldChange(field: field, oldValue: old, newValue: new)
    }
    
    /// Creates field changes from comparing two optional values with custom formatting
    static func fieldChange<T: CustomStringConvertible>(_ field: String, old: T?, new: T?) -> FieldChange? {
        let oldStr = old?.description
        let newStr = new?.description
        guard oldStr != newStr else { return nil }
        return FieldChange(field: field, oldValue: oldStr, newValue: newStr)
    }
}
