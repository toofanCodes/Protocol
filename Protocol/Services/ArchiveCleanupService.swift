//
//  ArchiveCleanupService.swift
//  Protocol
//
//  Background service to automatically clean up old archived items.
//

import SwiftUI
import SwiftData

actor ArchiveCleanupService {
    static let shared = ArchiveCleanupService()
    
    private init() {}
    
    /// Clean up archived molecules older than the specified threshold
    /// - Parameters:
    ///   - modelContext: The SwiftData model context
    ///   - daysThreshold: Number of days after which archived items should be deleted (default: 30)
    func cleanupOldArchives(modelContext: ModelContext, daysThreshold: Int = 30) async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysThreshold, to: Date()) ?? Date()
        
        // Find archived templates older than threshold
        let descriptor = FetchDescriptor<MoleculeTemplate>(
            predicate: #Predicate<MoleculeTemplate> { 
                $0.isArchived && $0.updatedAt < cutoffDate 
            }
        )
        
        guard let oldArchives = try? modelContext.fetch(descriptor) else { return }
        
        for template in oldArchives {
            // Log permanent deletion
            await AuditLogger.shared.logDelete(
                entityType: .moleculeTemplate,
                entityId: template.id.uuidString,
                entityName: template.title,
                additionalInfo: "Auto-deleted: archived > \(daysThreshold) days"
            )
            
            modelContext.delete(template)
        }
        
        try? modelContext.save()
        
        if !oldArchives.isEmpty {
            AppLogger.data.info("Cleaned up \(oldArchives.count) archived molecules older than \(daysThreshold) days")
        }
    }
    
    /// Clean up archived atoms older than the specified threshold
    func cleanupOldAtomArchives(modelContext: ModelContext, daysThreshold: Int = 30) async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysThreshold, to: Date()) ?? Date()
        
        let descriptor = FetchDescriptor<AtomTemplate>(
            predicate: #Predicate<AtomTemplate> { 
                $0.isArchived && $0.updatedAt < cutoffDate 
            }
        )
        
        guard let oldArchives = try? modelContext.fetch(descriptor) else { return }
        
        for atom in oldArchives {
            await AuditLogger.shared.logDelete(
                entityType: .atomTemplate,
                entityId: atom.id.uuidString,
                entityName: atom.title,
                additionalInfo: "Auto-deleted: archived > \(daysThreshold) days"
            )
            
            modelContext.delete(atom)
        }
        
        try? modelContext.save()
        
        if !oldArchives.isEmpty {
            AppLogger.data.info("Cleaned up \(oldArchives.count) archived atoms older than \(daysThreshold) days")
        }
    }
}
