//
//  AuditLogViewModel.swift
//  Protocol
//
//  ViewModel for AuditLogViewer, handling state, filtering, and export logic.
//

import SwiftUI
import Combine

@MainActor
final class AuditLogViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var entries: [AuditLogEntry] = []
    @Published var isLoading = true
    @Published var selectedEntry: AuditLogEntry?
    
    // Filter State
    @Published var operationFilter: AuditOperation? = nil
    @Published var entityFilter: AuditEntityType? = nil
    @Published var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @Published var endDate: Date = Date()
    @Published var showFilters = false
    
    // Export State
    @Published var showingExportSheet = false
    @Published var shareItems: [Any] = []
    
    // Dependencies
    private let auditLogger: AuditLogger
    
    // MARK: - Initialization
    
    init(auditLogger: AuditLogger = .shared) {
        self.auditLogger = auditLogger
    }
    
    // MARK: - Derived State
    
    var filteredEntries: [AuditLogEntry] {
        entries.filter { entry in
            // Operation filter
            if let op = operationFilter, entry.operation != op {
                return false
            }
            // Entity filter
            if let entity = entityFilter, entry.entityType != entity {
                return false
            }
            // Date range filter
            if entry.timestamp < startDate || entry.timestamp > endDate {
                return false
            }
            return true
        }
    }
    
    var resultCountText: String {
        "\(filteredEntries.count) of \(entries.count) entries"
    }
    
    // MARK: - Actions
    
    func loadEntries() async {
        isLoading = true
        entries = await auditLogger.getEntries()
        isLoading = false
    }
    
    func resetFilters() {
        operationFilter = nil
        entityFilter = nil
        startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        endDate = Date()
    }
    
    func clearLogs() {
        Task {
            await auditLogger.clearAll()
            // Reload after clearing
            await loadEntries()
        }
    }
    
    // MARK: - Export Logic
    
    func exportAsJSON() {
        Task {
            if let data = await auditLogger.exportAsJSON() {
                shareItems = [data]
                showingExportSheet = true
            }
        }
    }
    
    func exportAsCSV() {
        let entriesToExport = filteredEntries // Capture before detached task
        Task.detached(priority: .userInitiated) { [weak self] in
            let csv = Self.generateCSV(from: entriesToExport)
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit_log.csv")
            do {
                try csv.write(to: tempURL, atomically: true, encoding: .utf8)
                
                await MainActor.run {
                    self?.shareItems = [tempURL]
                    self?.showingExportSheet = true
                }
            } catch {
                print("Failed to export CSV: \(error.localizedDescription)")
            }
        }
    }
    
    private nonisolated static func generateCSV(from entries: [AuditLogEntry]) -> String {
        var csv = "Timestamp,Operation,Entity Type,Entity ID,Entity Name,Call Site,Changes,Additional Info\n"
        
        let dateFormatter = ISO8601DateFormatter()
        
        for entry in entries {
            let timestamp = dateFormatter.string(from: entry.timestamp)
            let changes = entry.changes?.map { $0.description }.joined(separator: "; ") ?? ""
            let row = [
                timestamp,
                entry.operation.rawValue,
                entry.entityType.rawValue,
                entry.entityId,
                entry.entityName ?? "",
                entry.callSite,
                "\"\(changes)\"",
                entry.additionalInfo ?? ""
            ].joined(separator: ",")
            csv += row + "\n"
        }
        
        return csv
    }
}
