//
//  BackupManager.swift
//  Protocol
//
//  Created on 2026-01-05.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers
import UIKit

// MARK: - Backup Models

/// A complete backup container for the app's data
struct AppBackup: Codable {
    let metadata: BackupMetadata
    let moleculeTemplates: [MoleculeTemplateData]
    let moleculeInstances: [MoleculeInstanceData]
}

struct BackupMetadata: Codable {
    let appVersion: String
    let timestamp: Date
    let deviceName: String
    let schemaVersion: Int
}

/// Serializable representation of a MoleculeTemplate
struct MoleculeTemplateData: Codable {
    let id: UUID
    let title: String
    let baseTime: Date
    let recurrenceFreq: String
    let themeColorHex: String?
    let iconSymbol: String?
    let compound: String?
    let notes: String?
    let isAllDay: Bool
    let isArchived: Bool
    
    // Nested Atoms
    let atoms: [AtomTemplateData]
    
    init(from template: MoleculeTemplate) {
        self.id = template.id
        self.title = template.title
        self.baseTime = template.baseTime
        self.recurrenceFreq = template.recurrenceFreq.rawValue
        self.themeColorHex = template.themeColorHex
        self.iconSymbol = template.iconSymbol
        self.compound = template.compound
        self.notes = template.notes
        self.isAllDay = template.isAllDay
        self.isArchived = template.isArchived
        
        self.atoms = template.atomTemplates.map { AtomTemplateData(from: $0) }
    }
}

/// Serializable representation of an AtomTemplate
struct AtomTemplateData: Codable {
    let id: UUID
    let title: String
    let inputType: String // rawValue of enum
    let targetValue: Double?
    let unit: String?
    let order: Int
    let targetSets: Int?
    let targetReps: Int?
    let defaultRestTime: TimeInterval?
    let videoURL: String?
    let iconSymbol: String?
    let iconFrameRaw: String
    
    init(from atom: AtomTemplate) {
        self.id = atom.id
        self.title = atom.title
        self.inputType = atom.inputType.rawValue
        self.targetValue = atom.targetValue
        self.unit = atom.unit
        self.order = atom.order
        self.targetSets = atom.targetSets
        self.targetReps = atom.targetReps
        self.defaultRestTime = atom.defaultRestTime
        self.videoURL = atom.videoURL
        self.iconSymbol = atom.iconSymbol
        self.iconFrameRaw = atom.iconFrameRaw
    }
}

/// Serializable representation of a MoleculeInstance
struct MoleculeInstanceData: Codable {
    let id: UUID
    let scheduledDate: Date
    let isCompleted: Bool
    let isException: Bool
    let exceptionTitle: String?
    let exceptionTime: Date?
    let parentTemplateID: UUID?
    
    // Nested Atoms
    let atoms: [AtomInstanceData]
    
    init(from instance: MoleculeInstance) {
        self.id = instance.id
        self.scheduledDate = instance.scheduledDate
        self.isCompleted = instance.isCompleted
        self.isException = instance.isException
        self.exceptionTitle = instance.exceptionTitle
        self.exceptionTime = instance.exceptionTime
        self.parentTemplateID = instance.parentTemplate?.id
        
        self.atoms = instance.atomInstances.map { AtomInstanceData(from: $0) }
    }
}

/// Serializable representation of an AtomInstance
struct AtomInstanceData: Codable {
    let id: UUID
    let title: String
    let inputType: String
    let isCompleted: Bool
    let currentValue: Double?
    let targetValue: Double?
    let unit: String?
    let order: Int
    let completedAt: Date?
    let sourceTemplateId: UUID?
    let targetSets: Int?
    let targetReps: Int?
    let defaultRestTime: TimeInterval?
    let notes: String?
    let videoURL: String?
    
    // Note: We are not backing up `sets` (WorkoutSet) for now to keep complexity manageable,
    // assuming they can be reconstructed or are less critical for v1 backup.
    // If strict fidelity is needed, we should add `sets: [WorkoutSetData]`.
    
    init(from atom: AtomInstance) {
        self.id = atom.id
        self.title = atom.title
        self.inputType = atom.inputType.rawValue
        self.isCompleted = atom.isCompleted
        self.currentValue = atom.currentValue
        self.targetValue = atom.targetValue
        self.unit = atom.unit
        self.order = atom.order
        self.completedAt = atom.completedAt
        self.sourceTemplateId = atom.sourceTemplateId
        self.targetSets = atom.targetSets
        self.targetReps = atom.targetReps
        self.defaultRestTime = atom.defaultRestTime
        self.notes = atom.notes
        self.videoURL = atom.videoURL
    }
}

// MARK: - Backup Manager

@MainActor
final class BackupManager: ObservableObject {
    static let shared = BackupManager()
    
    private let fileManager = FileManager.default
    private let localBackupDirectoryName = "Backups"
    
    // Published state for UI monitoring
    @Published var isBackingUp = false
    @Published var lastBackupDate: Date? // Ideally persist this in UserDefaults for auto-backup check
    @Published var isCloudEnabled = false
    
    private init() {
        // Check for iCloud availability
        if let _ = fileManager.url(forUbiquityContainerIdentifier: nil) {
            isCloudEnabled = true
        }
        createBackupDirectoryIfNeeded()
    }
    
    // MARK: - Core Operations
    
    /// Auto-backup on app launch if needed (e.g. daily)
    func autoBackup(context: ModelContext) async {
        // Read preference (default to Daily)
        let frequencyRaw = UserDefaults.standard.string(forKey: "backupFrequency") ?? "Daily"
        
        // Skip if manual
        if frequencyRaw == "Manual" {
            AppLogger.backup.info("🚫 Auto-Backup skipped (Manual preference)")
            return
        }
        
        // Determine interval
        let interval: TimeInterval
        if frequencyRaw == "Weekly" {
            interval = 604800 // 7 days
        } else {
            interval = 86400 // 24 hours
        }
        
        let lastDate = UserDefaults.standard.object(forKey: "LastAutoBackupDate") as? Date ?? Date.distantPast
        let now = Date()
        
        // If time interval passed
        if now.timeIntervalSince(lastDate) > interval {
            AppLogger.backup.info("🔄 Performing Auto-Backup (\(frequencyRaw))...")
            do {
                _ = try await createBackup(context: context)
                UserDefaults.standard.set(now, forKey: "LastAutoBackupDate")
                AppLogger.backup.info("✅ Auto-Backup complete.")
            } catch {
                AppLogger.backup.error("❌ Auto-Backup failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Creates a complete backup of the current data context
    func createBackup(context: ModelContext) async throws -> URL {
        isBackingUp = true
        defer { isBackingUp = false }
        
        // 1. Fetch all data
        let templateDescriptor = FetchDescriptor<MoleculeTemplate>()
        let templates = try context.fetch(templateDescriptor)
        
        let instanceDescriptor = FetchDescriptor<MoleculeInstance>()
        let instances = try context.fetch(instanceDescriptor)
        
        // 2. Convert to serializable format
        let templateData = templates.map { MoleculeTemplateData(from: $0) }
        let instanceData = instances.map { MoleculeInstanceData(from: $0) }
        
        let metadata = BackupMetadata(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            timestamp: Date(),
            deviceName: getDeviceName(),
            schemaVersion: 1
        )
        
        let backup = AppBackup(
            metadata: metadata,
            moleculeTemplates: templateData,
            moleculeInstances: instanceData
        )
        
        // 3. Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(backup)
        
        // 4. Save to file
        let filename = "backup_\(formatDate(Date())).json"
        let dir = getBackupDirectory()
        let fileURL = dir.appendingPathComponent(filename)
        
        // Ensure iCloud Documents dir exists if using iCloud
        if isCloudEnabled {
            if !fileManager.fileExists(atPath: dir.path) {
                 try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
        
        try data.write(to: fileURL)
        
        // 5. Update state
        lastBackupDate = Date()
        
        // 6. Prune old backups
        pruneOldBackups()
        
        return fileURL
    }
    
    /// Lists available backup files
    func listBackups() -> [URL] {
        let dir = getBackupDirectory()
        
        // If iCloud, we might need to trigger a download or coordination,
        // but for simple file listing in Documents, this often works if synced.
        // For robustness, we just list what's there.
        
        do {
            let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            return files.filter { $0.pathExtension == "json" }
                        .sorted {
                            let date1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                            let date2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                            return date1 > date2
                        }
        } catch {
            // If folder doesn't exist yet, return empty
            return []
        }
    }
    
    /// Restores data from a backup file (Destructive)
    func restore(from url: URL, context: ModelContext) async throws {
        // 1. Load and decode
        // Ensure we have access security scope if needed (mostly for picking external files, but good practice)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(AppBackup.self, from: data)
        
        // 2. Clear existing data
        try clearAllData(context: context)
        
        // 3. Reconstruct Templates & Atoms
        var templateMap: [UUID: MoleculeTemplate] = [:]
        
        for tData in backup.moleculeTemplates {
            let freq = RecurrenceFrequency(rawValue: tData.recurrenceFreq) ?? .daily
            
            let newTemplate = MoleculeTemplate(
                title: tData.title,
                baseTime: tData.baseTime,
                recurrenceFreq: freq,
                isAllDay: tData.isAllDay
            )
            newTemplate.themeColorHex = tData.themeColorHex ?? "#007AFF"
            newTemplate.iconSymbol = tData.iconSymbol
            newTemplate.compound = tData.compound
            newTemplate.notes = tData.notes
            newTemplate.isArchived = tData.isArchived
            newTemplate.id = tData.id // Preserve ID
            
            // Reconstruct Atom Templates
            for aData in tData.atoms {
                let inputType = AtomInputType(rawValue: aData.inputType) ?? .binary
                let newAtom = AtomTemplate(
                    id: aData.id,
                    title: aData.title,
                    inputType: inputType,
                    targetValue: aData.targetValue,
                    unit: aData.unit,
                    order: aData.order,
                    targetSets: aData.targetSets,
                    targetReps: aData.targetReps,
                    defaultRestTime: aData.defaultRestTime,
                    videoURL: aData.videoURL,
                    parentMoleculeTemplate: newTemplate,
                    iconSymbol: aData.iconSymbol
                )
                newAtom.iconFrameRaw = aData.iconFrameRaw
                context.insert(newAtom)
                // Appending to parent happens via relationship or manual append?
                // SwiftData usually handles the 'inverse', but appending to the array is safer.
                newTemplate.atomTemplates.append(newAtom)
            }
            
            context.insert(newTemplate)
            templateMap[tData.id] = newTemplate
        }
        
        // 4. Reconstruct Instances & Atoms
        for iData in backup.moleculeInstances {
            let newInstance = MoleculeInstance(
                scheduledDate: iData.scheduledDate,
                isCompleted: iData.isCompleted,
                isException: iData.isException,
                exceptionTitle: iData.exceptionTitle,
                exceptionTime: iData.exceptionTime,
                isAllDay: false // Default
            )
            newInstance.id = iData.id
            
            // Link parent
            if let parentID = iData.parentTemplateID, let parent = templateMap[parentID] {
                newInstance.parentTemplate = parent
                // Ideally also inherit isAllDay from parent if not an exception
            }
            
            // Reconstruct Atom Instances
            for aData in iData.atoms {
                let inputType = AtomInputType(rawValue: aData.inputType) ?? .binary
                let newAtom = AtomInstance(
                    id: aData.id,
                    title: aData.title,
                    inputType: inputType,
                    isCompleted: aData.isCompleted,
                    currentValue: aData.currentValue,
                    targetValue: aData.targetValue,
                    unit: aData.unit,
                    order: aData.order,
                    targetSets: aData.targetSets,
                    targetReps: aData.targetReps,
                    defaultRestTime: aData.defaultRestTime,
                    notes: aData.notes,
                    videoURL: aData.videoURL,
                    parentMoleculeInstance: newInstance,
                    sourceTemplateId: aData.sourceTemplateId
                )
                if let completedAt = aData.completedAt {
                    newAtom.completedAt = completedAt
                }
                context.insert(newAtom)
                newInstance.atomInstances.append(newAtom)
            }
            
            context.insert(newInstance)
        }
        
        try context.save()
    }
    
    // MARK: - Helpers
    
    private func clearAllData(context: ModelContext) throws {
        // SwiftData cascade rules should help, but precise order is safer
        // Delete instances (and cascade atoms)
        try context.delete(model: MoleculeInstance.self)
        // Delete templates (and cascade atom templates)
        try context.delete(model: MoleculeTemplate.self)
    }
    
    private func getBackupDirectory() -> URL {
        // Prefer iCloud Documents if available
        if let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
            return iCloudURL
        }
        
        // Fallback to local
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(localBackupDirectoryName)
    }
    
    private func createBackupDirectoryIfNeeded() {
        let url = getBackupDirectory()
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    private func pruneOldBackups() {
        // Keep last 7 backups
        let backups = listBackups()
        if backups.count > 7 {
            let toDelete = backups.suffix(from: 7)
            for url in toDelete {
                try? fileManager.removeItem(at: url)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }
    
    private func getDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "Unknown"
        #endif
    }
}
