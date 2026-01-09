//
//  DriveService.swift
//  Protocol
//
//  Created on 2026-01-07.
//

import Foundation
import GoogleSignIn
import GoogleAPIClientForREST_Drive
import SwiftData

/// Actor responsible for all Google Drive API interactions.
/// Ensures thread safety for network calls and manages auth injection.
actor DriveService {
    static let shared = DriveService()
    
    // MARK: - Properties
    
    private let service = GTLRDriveService()
    private let rootFolderName = "Toofan_Empire_Sync"
    private let recordsFolderName = "Records"
    private let recordsFolderKey = "com.protocol.drive.recordsFolderID"
    
    // MARK: - Initialization
    
    private init() {
        #if DEBUG
        service.isRetryEnabled = false
        service.shouldFetchNextPages = false
        #endif
    }
    
    // MARK: - Public API: Directory Setup
    
    /// Ensures the required directory structure exists on Drive:
    /// Toofan_Empire_Sync / Records
    /// - Returns: The file ID of the 'Records' folder
    func ensureRemoteDirectoryReady() async throws -> String {
        try await configureService()
        
        if let cachedID = UserDefaults.standard.string(forKey: recordsFolderKey) {
            AppLogger.backup.debug("Using cached Records folder ID: \(cachedID)")
            return cachedID
        }
        
        AppLogger.backup.debug("No cached Records folder. Finding/Creating...")
        let rootID = try await findOrCreateFolder(name: rootFolderName, parentID: nil)
        AppLogger.backup.debug("Resolved Root ID: \(rootID)")
        
        let recordsID = try await findOrCreateFolder(name: recordsFolderName, parentID: rootID)
        AppLogger.backup.debug("Resolved Records ID: \(recordsID)")
        
        UserDefaults.standard.set(recordsID, forKey: recordsFolderKey)
        return recordsID
    }
    
    // MARK: - Public API: Upload Pipeline
    
    /// Uploads all pending records from the sync queue to Google Drive.
    /// - Parameter context: ModelContext to fetch records from SwiftData
    /// - Returns: Number of successfully uploaded records
    func uploadPendingRecords(context: ModelContext) async throws -> Int {
        try await configureService()
        
        let folderID = try await ensureRemoteDirectoryReady()
        let queue = await MainActor.run { SyncQueueManager.shared.getPriorityQueue() }
        
        guard !queue.isEmpty else {
            return 0
        }
        
        var uploadedCount = 0
        
        for item in queue {
            do {
                // Fetch record from SwiftData
                guard let jsonData = try await fetchAndSerialize(item: item, context: context) else {
                    // Record not found (deleted locally) - upload tombstone before removing from queue
                    AppLogger.backup.info("📋 Record deleted locally, uploading tombstone: \(item.modelType)_\(item.syncID)")
                    
                    let tombstone: [String: Any] = [
                        "syncID": item.syncID.uuidString,
                        "isDeleted": true,
                        "lastModified": ISO8601DateFormatter().string(from: Date())
                    ]
                    
                    guard let tombstoneData = try? JSONSerialization.data(withJSONObject: tombstone) else {
                        AppLogger.backup.error("❌ Failed to serialize tombstone for \(item.syncID)")
                        continue
                    }
                    
                    // Upload tombstone to Drive
                    do {
                        try await uploadRecord(item: item, data: tombstoneData, folderID: folderID)
                        AppLogger.backup.info("✅ Tombstone uploaded successfully")
                    } catch {
                        AppLogger.backup.warning("⚠️ Failed to upload tombstone: \(error.localizedDescription)")
                        // Don't remove from queue if tombstone upload failed
                        continue
                    }
                    
                    // Only remove from queue after successful tombstone upload
                    await MainActor.run { SyncQueueManager.shared.removeFromQueue(item) }
                    continue
                }
                
                // Upload to Drive
                try await uploadRecord(item: item, data: jsonData, folderID: folderID)
                
                // Success: Remove from queue
                await MainActor.run { SyncQueueManager.shared.removeFromQueue(item) }
                uploadedCount += 1
                
            } catch {
                // Log error but continue with other items
                AppLogger.backup.warning("⚠️ Failed to upload \(item.modelType)_\(item.syncID): \(error.localizedDescription)")
            }
        }
        
        return uploadedCount
    }
    
    // MARK: - Private: Record Fetching
    
    /// Fetches a record from SwiftData by ID and type, then serializes to JSON
    private func fetchAndSerialize(item: SyncQueueManager.PendingSyncItem, context: ModelContext) async throws -> Data? {
        // Must run on MainActor since context is main-actor bound
        return try await MainActor.run {
            switch item.modelType {
            case "MoleculeTemplate":
                let id = item.syncID
                let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == id })
                guard let record = try context.fetch(descriptor).first else { return nil }
                return record.toSyncJSON()
                
            case "MoleculeInstance":
                let id = item.syncID
                let descriptor = FetchDescriptor<MoleculeInstance>(predicate: #Predicate { $0.id == id })
                guard let record = try context.fetch(descriptor).first else { return nil }
                return record.toSyncJSON()
                
            case "AtomTemplate":
                let id = item.syncID
                let descriptor = FetchDescriptor<AtomTemplate>(predicate: #Predicate { $0.id == id })
                guard let record = try context.fetch(descriptor).first else { return nil }
                return record.toSyncJSON()
                
            default:
                AppLogger.backup.warning("⚠️ Unknown model type: \(item.modelType)")
                return nil
            }
        }
    }
    
    // MARK: - Private: Upload Logic
    
    /// Uploads a single record: creates or updates based on existence
    private func uploadRecord(item: SyncQueueManager.PendingSyncItem, data: Data, folderID: String) async throws {
        let filename = await MainActor.run { SyncQueueManager.shared.generateFilename(for: item) }
        
        // Check if file already exists
        if let existingFileID = try await searchFile(name: filename, in: folderID) {
            // Update existing file
            try await updateFile(fileID: existingFileID, data: data)
        } else {
            // Create new file
            try await createFile(name: filename, data: data, folderID: folderID)
        }
    }
    
    /// Searches for a file by name in a folder using raw URLSession
    private func searchFile(name: String, in folderID: String) async throws -> String? {
        guard let accessToken = await getAccessToken() else {
            throw DriveError.notSignedIn
        }
        
        let queryString = "name = '\(name)' and '\(folderID)' in parents and trashed = false"
        guard let encodedQuery = queryString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]],
              let firstFile = files.first else {
            return nil
        }
        
        return DriveService.safeString(from: firstFile["id"])
    }
    
    /// Creates a new file on Drive using raw URLSession multipart upload
    private func createFile(name: String, data: Data, folderID: String) async throws {
        guard let accessToken = await getAccessToken() else {
            throw DriveError.notSignedIn
        }
        
        guard let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id") else {
            throw DriveError.invalidData
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart body
        var body = Data()
        
        // Part 1: Metadata
        let metadata: [String: Any] = [
            "name": name,
            "parents": [folderID],
            "mimeType": "application/json"
        ]
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n".data(using: .utf8)!)
        
        // Part 2: File content
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DriveError.uploadFailed
        }
    }
    
    /// Updates an existing file on Drive using raw URLSession
    private func updateFile(fileID: String, data: Data) async throws {
        guard let accessToken = await getAccessToken() else {
            throw DriveError.notSignedIn
        }
        
        guard let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media") else {
            throw DriveError.invalidData
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DriveError.uploadFailed
        }
    }
    
    // MARK: - Public API: Reconciliation (Remote → Local)
    
    /// Represents a remote file's metadata
    struct RemoteFileInfo {
        let fileID: String
        let name: String
        let modifiedTime: Date
        let syncID: UUID
        let modelType: String
    }
    
    /// Lists all JSON files in the Records folder with their metadata
    /// Uses raw URLSession to bypass SDK's problematic object parsing
    func listRemoteRecords() async throws -> [RemoteFileInfo] {
        let folderID = try await ensureRemoteDirectoryReady()
        
        guard let accessToken = await getAccessToken() else {
            throw DriveError.notSignedIn
        }
        
        let queryString = "'\(folderID)' in parents and trashed = false and mimeType = 'application/json'"
        guard let encodedQuery = queryString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name,modifiedTime)") else {
            throw DriveError.invalidData
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            AppLogger.backup.error("❌ Drive API returned non-200 status for file list")
            throw DriveError.unknown
        }
        
        // Parse JSON ourselves - completely safe from SDK type casting issues
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            AppLogger.backup.debug("Remote file list is empty or invalid response")
            return []
        }
        
        AppLogger.backup.debug("Found \(files.count) remote files. Processing...")
        
        // ISO 8601 date formatter for modifiedTime
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return files.compactMap { file -> RemoteFileInfo? in
            // Safely extract fields using our helper
            guard let fileID = DriveService.safeString(from: file["id"]),
                  let name = DriveService.safeString(from: file["name"]),
                  let modifiedTimeStr = DriveService.safeString(from: file["modifiedTime"]),
                  let modifiedTime = dateFormatter.date(from: modifiedTimeStr) else {
                return nil
            }
            
            // Parse filename: ModelType_UUID.json
            let components = name.replacingOccurrences(of: ".json", with: "").split(separator: "_")
            guard components.count == 2,
                  let syncID = UUID(uuidString: String(components[1])) else {
                return nil
            }
            
            return RemoteFileInfo(
                fileID: fileID,
                name: name,
                modifiedTime: modifiedTime,
                syncID: syncID,
                modelType: String(components[0])
            )
        }
    }
    
    // MARK: - Private Helpers (Type Safety)
    

    
    /// Downloads a file's content from Drive using raw URLSession
    func downloadFile(fileID: String) async throws -> Data {
        guard let accessToken = await getAccessToken() else {
            throw DriveError.notSignedIn
        }
        
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media") else {
            throw DriveError.invalidData
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            AppLogger.backup.error("❌ Drive API download failed for file: \(fileID)")
            throw DriveError.downloadFailed
        }
        
        return data
    }
    
    /// Reconciles remote files with local SwiftData (Last-Write-Wins)
    /// - Parameter context: ModelContext for SwiftData operations
    /// - Returns: Number of records updated/created
    func reconcileFromRemote(context: ModelContext) async throws -> Int {
        let remoteFiles = try await listRemoteRecords()
        var reconciledCount = 0
        
        for remoteInfo in remoteFiles {
            do {
                AppLogger.backup.debug("Checking remote file: \(remoteInfo.name) (\(remoteInfo.syncID))")
                let wasReconciled = try await reconcileRecord(remoteInfo: remoteInfo, context: context)
                if wasReconciled {
                    reconciledCount += 1
                }
            } catch {
                AppLogger.backup.warning("⚠️ Failed to reconcile \(remoteInfo.name): \(error.localizedDescription)")
            }
        }
        
        return reconciledCount
    }

    /// Reconciles a single remote record with local data
    private func reconcileRecord(remoteInfo: RemoteFileInfo, context: ModelContext) async throws -> Bool {
        // Check local timestamp - capture result before async boundary
        let localModified = await MainActor.run {
            getLocalModifiedDate(syncID: remoteInfo.syncID, modelType: remoteInfo.modelType, context: context)
        }
        
        // Compare timestamps (Last-Write-Wins)
        if let localModified = localModified {
            // Record exists locally
            if remoteInfo.modifiedTime > localModified {
                // Remote is newer - download and update
                let data = try await downloadFile(fileID: remoteInfo.fileID)
                try await MainActor.run {
                    try applyRemoteData(data: data, modelType: remoteInfo.modelType, syncID: remoteInfo.syncID, context: context)
                }
                return true
            } else {
                // Local is newer or same - skip (upload pipeline handles)
                return false
            }
        } else {
            // Record doesn't exist locally - create it
            let data = try await downloadFile(fileID: remoteInfo.fileID)
            try await MainActor.run {
                try createFromRemoteData(data: data, modelType: remoteInfo.modelType, context: context)
            }
            return true
        }
    }
    
    // MARK: - Private: Reconciliation Helpers
    
    /// Gets the local lastModified date for a record
    private nonisolated func getLocalModifiedDate(syncID: UUID, modelType: String, context: ModelContext) -> Date? {
        switch modelType {
        case "MoleculeTemplate":
            let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == syncID })
            return try? context.fetch(descriptor).first?.lastModified
            
        case "MoleculeInstance":
            let descriptor = FetchDescriptor<MoleculeInstance>(predicate: #Predicate { $0.id == syncID })
            return try? context.fetch(descriptor).first?.lastModified
            
        case "AtomTemplate":
            let descriptor = FetchDescriptor<AtomTemplate>(predicate: #Predicate { $0.id == syncID })
            return try? context.fetch(descriptor).first?.lastModified
            
        default:
            return nil
        }
    }
    
    /// Updates an existing local record from remote JSON
    private nonisolated func applyRemoteData(data: Data, modelType: String, syncID: UUID, context: ModelContext) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DriveError.invalidData
        }
        
        // Check for tombstone - handle String or Bool
        let isDeleted: Bool
        if let val = json["isDeleted"] {
            isDeleted = DriveService.safeBool(from: val)
        } else {
            isDeleted = false
        }
        
        if isDeleted {
            try deleteLocalRecord(syncID: syncID, modelType: modelType, context: context)
            return
        }
        
        // Update based on type
        switch modelType {
        case "MoleculeTemplate":
            let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == syncID })
            guard let record = try context.fetch(descriptor).first else { return }
            applyJSONToMoleculeTemplate(json: json, record: record)
            
        case "MoleculeInstance":
            let descriptor = FetchDescriptor<MoleculeInstance>(predicate: #Predicate { $0.id == syncID })
            guard let record = try context.fetch(descriptor).first else { return }
            applyJSONToMoleculeInstance(json: json, record: record)
            
        case "AtomTemplate":
            let descriptor = FetchDescriptor<AtomTemplate>(predicate: #Predicate { $0.id == syncID })
            guard let record = try context.fetch(descriptor).first else { return }
            applyJSONToAtomTemplate(json: json, record: record)
            
        default:
            break
        }
        
        try context.save()
    }
    
    /// Creates a new local record from remote JSON
    private nonisolated func createFromRemoteData(data: Data, modelType: String, context: ModelContext) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AppLogger.backup.error("❌ Failed to parse JSON for \(modelType)")
            throw DriveError.invalidData
        }
        AppLogger.backup.debug("Received JSON for \(modelType): keys=\(Array(json.keys))")
        
        // Check for tombstone - handle String or Bool
        let isDeleted: Bool
        if let val = json["isDeleted"] {
            isDeleted = DriveService.safeBool(from: val)
        } else {
            isDeleted = false
        }
        
        if isDeleted {
            return // Don't create tombstones
        }
        
        let formatter = ISO8601DateFormatter()
        
        switch modelType {
        case "MoleculeTemplate":
            try createMoleculeTemplateFromJSON(json: json, formatter: formatter, context: context)
            
        case "MoleculeInstance":
            try createMoleculeInstanceFromJSON(json: json, formatter: formatter, context: context)
            
        case "AtomTemplate":
            try createAtomTemplateFromJSON(json: json, formatter: formatter, context: context)
            
        default:
            AppLogger.backup.warning("⚠️ Unknown model type for creation: \(modelType)")
        }
        
        try context.save()
        AppLogger.backup.info("✅ Created new \(modelType) from remote data")
    }
    
    // MARK: - Private: Create From JSON Helpers
    
    private nonisolated func createMoleculeTemplateFromJSON(json: [String: Any], formatter: ISO8601DateFormatter, context: ModelContext) throws {
        // Required fields
        guard let syncIDStr = DriveService.safeString(from: json["syncID"]),
              let syncID = UUID(uuidString: syncIDStr),
              let title = DriveService.safeString(from: json["title"]),
              let baseTimeStr = DriveService.safeString(from: json["baseTime"]),
              let baseTime = formatter.date(from: baseTimeStr) else {
            AppLogger.backup.error("❌ Missing required fields for MoleculeTemplate")
            throw DriveError.invalidData
        }
        
        // Parse recurrence
        let recurrenceFreq: RecurrenceFrequency
        if let freqStr = DriveService.safeString(from: json["recurrenceFreq"]),
           let freq = RecurrenceFrequency(rawValue: freqStr) {
            recurrenceFreq = freq
        } else {
            recurrenceFreq = .daily
        }
        
        let recurrenceDays = json["recurrenceDays"] as? [Int] ?? []
        
        // Parse end rule
        let endRuleType: RecurrenceEndRuleType
        if let typeStr = DriveService.safeString(from: json["endRuleType"]),
           let type = RecurrenceEndRuleType(rawValue: typeStr) {
            endRuleType = type
        } else {
            endRuleType = .never
        }
        
        // Parse dates
        let createdAt: Date
        if let dateStr = DriveService.safeString(from: json["createdAt"]), let date = formatter.date(from: dateStr) {
            createdAt = date
        } else {
            createdAt = Date()
        }
        
        var endRuleDate: Date? = nil
        if let dateStr = DriveService.safeString(from: json["endRuleDate"]), let date = formatter.date(from: dateStr) {
            endRuleDate = date
        }
        
        // Create the template
        let template = MoleculeTemplate(
            id: syncID,
            title: title,
            baseTime: baseTime,
            recurrenceFreq: recurrenceFreq,
            recurrenceDays: recurrenceDays,
            endRuleType: endRuleType,
            endRuleDate: endRuleDate,
            endRuleCount: json["endRuleCount"] as? Int,
            notes: DriveService.safeString(from: json["notes"]),
            compound: DriveService.safeString(from: json["compound"]),
            alertOffsets: json["alertOffsets"] as? [Int] ?? [15],
            isAllDay: DriveService.safeBool(from: json["isAllDay"]),
            iconSymbol: DriveService.safeString(from: json["iconSymbol"]),
            createdAt: createdAt
        )
        
        // Apply additional fields
        template.isPinned = DriveService.safeBool(from: json["isPinned"])
        template.sortOrder = json["sortOrder"] as? Int ?? 0
        if let frameStr = DriveService.safeString(from: json["iconFrameRaw"]) {
            template.iconFrameRaw = frameStr
        }
        if let colorHex = DriveService.safeString(from: json["themeColorHex"]) {
            template.themeColorHex = colorHex
        }
        
        context.insert(template)
    }
    
    private nonisolated func createMoleculeInstanceFromJSON(json: [String: Any], formatter: ISO8601DateFormatter, context: ModelContext) throws {
        // Required fields
        guard let syncIDStr = DriveService.safeString(from: json["syncID"]),
              let syncID = UUID(uuidString: syncIDStr),
              let scheduledDateStr = DriveService.safeString(from: json["scheduledDate"]),
              let scheduledDate = formatter.date(from: scheduledDateStr) else {
            AppLogger.backup.error("❌ Missing required fields for MoleculeInstance")
            throw DriveError.invalidData
        }
        
        // Parse dates
        let createdAt: Date
        if let dateStr = DriveService.safeString(from: json["createdAt"]), let date = formatter.date(from: dateStr) {
            createdAt = date
        } else {
            createdAt = Date()
        }
        
        var completedAt: Date? = nil
        if let dateStr = DriveService.safeString(from: json["completedAt"]), let date = formatter.date(from: dateStr) {
            completedAt = date
        }
        
        var exceptionTime: Date? = nil
        if let dateStr = DriveService.safeString(from: json["exceptionTime"]), let date = formatter.date(from: dateStr) {
            exceptionTime = date
        }
        
        // Resolve parent template if referenced
        var parentTemplate: MoleculeTemplate? = nil
        if let parentIDStr = DriveService.safeString(from: json["moleculeTemplateID"]),
           let parentID = UUID(uuidString: parentIDStr) {
            let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == parentID })
            parentTemplate = try? context.fetch(descriptor).first
        }
        
        // Create the instance
        let instance = MoleculeInstance(
            id: syncID,
            scheduledDate: scheduledDate,
            isCompleted: DriveService.safeBool(from: json["isCompleted"]),
            isException: DriveService.safeBool(from: json["isException"]),
            exceptionTitle: DriveService.safeString(from: json["exceptionTitle"]),
            exceptionTime: exceptionTime,
            parentTemplate: parentTemplate,
            alertOffsets: json["alertOffsets"] as? [Int],
            isAllDay: DriveService.safeBool(from: json["isAllDay"]),
            createdAt: createdAt,
            notes: DriveService.safeString(from: json["notes"])
        )
        
        instance.completedAt = completedAt
        if let dateStr = DriveService.safeString(from: json["originalScheduledDate"]), let date = formatter.date(from: dateStr) {
            instance.originalScheduledDate = date
        }
        
        context.insert(instance)
    }
    
    private nonisolated func createAtomTemplateFromJSON(json: [String: Any], formatter: ISO8601DateFormatter, context: ModelContext) throws {
        // Required fields
        guard let syncIDStr = DriveService.safeString(from: json["syncID"]),
              let syncID = UUID(uuidString: syncIDStr),
              let title = DriveService.safeString(from: json["title"]) else {
            AppLogger.backup.error("❌ Missing required fields for AtomTemplate")
            throw DriveError.invalidData
        }
        
        // Parse input type
        let inputType: AtomInputType
        if let typeStr = DriveService.safeString(from: json["inputType"]),
           let type = AtomInputType(rawValue: typeStr) {
            inputType = type
        } else {
            inputType = .binary
        }
        
        // Parse dates
        let createdAt: Date
        if let dateStr = DriveService.safeString(from: json["createdAt"]), let date = formatter.date(from: dateStr) {
            createdAt = date
        } else {
            createdAt = Date()
        }
        
        // Resolve parent template if referenced
        var parentTemplate: MoleculeTemplate? = nil
        if let parentIDStr = DriveService.safeString(from: json["moleculeTemplateID"]),
           let parentID = UUID(uuidString: parentIDStr) {
            let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == parentID })
            parentTemplate = try? context.fetch(descriptor).first
        }
        
        // Create the atom template
        let atomTemplate = AtomTemplate(
            id: syncID,
            title: title,
            inputType: inputType,
            targetValue: json["targetValue"] as? Double,
            unit: DriveService.safeString(from: json["unit"]),
            order: json["order"] as? Int ?? 0,
            targetSets: json["targetSets"] as? Int,
            targetReps: json["targetReps"] as? Int,
            defaultRestTime: json["defaultRestTime"] as? TimeInterval,
            videoURL: DriveService.safeString(from: json["videoURL"]),
            parentMoleculeTemplate: parentTemplate,
            createdAt: createdAt,
            iconSymbol: DriveService.safeString(from: json["iconSymbol"])
        )
        
        // Apply additional fields
        if let frameStr = DriveService.safeString(from: json["iconFrameRaw"]) {
            atomTemplate.iconFrameRaw = frameStr
        }
        if let colorHex = DriveService.safeString(from: json["themeColorHex"]) {
            atomTemplate.themeColorHex = colorHex
        }
        
        context.insert(atomTemplate)
    }
    
    /// Deletes a local record (tombstone handling)
    private nonisolated func deleteLocalRecord(syncID: UUID, modelType: String, context: ModelContext) throws {
        switch modelType {
        case "MoleculeTemplate":
            let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == syncID })
            if let record = try context.fetch(descriptor).first {
                record.isArchived = true // Soft delete
            }
            
        case "MoleculeInstance":
            let descriptor = FetchDescriptor<MoleculeInstance>(predicate: #Predicate { $0.id == syncID })
            if let record = try context.fetch(descriptor).first {
                record.isArchived = true // Soft delete
            }
            
        case "AtomTemplate":
            let descriptor = FetchDescriptor<AtomTemplate>(predicate: #Predicate { $0.id == syncID })
            if let record = try context.fetch(descriptor).first {
                record.isArchived = true // Soft delete
            }
            
        default:
            break
        }
        
        try context.save()
    }
    
    // MARK: - Private: JSON Appliers (Partial Update)
    
    private nonisolated func applyJSONToMoleculeTemplate(json: [String: Any], record: MoleculeTemplate) {
        // Basic fields
        if let val = json["title"], let title = DriveService.safeString(from: val) { record.title = title }
        if let val = json["isDeleted"] { record.isArchived = DriveService.safeBool(from: val) }
        
        // Date fields
        let formatter = ISO8601DateFormatter()
        if let val = json["baseTime"], let dateStr = DriveService.safeString(from: val), let date = formatter.date(from: dateStr) {
            record.baseTime = date
        }
        if let val = json["endRuleDate"], let dateStr = DriveService.safeString(from: val), let date = formatter.date(from: dateStr) {
            record.endRuleDate = date
        }
        if let val = json["createdAt"], let dateStr = DriveService.safeString(from: val), let date = formatter.date(from: dateStr) {
            record.createdAt = date
        }
        
        // Recurrence fields
        if let val = json["recurrenceFreq"], let freqStr = DriveService.safeString(from: val), let freq = RecurrenceFrequency(rawValue: freqStr) {
            record.recurrenceFreq = freq
        }
        if let val = json["recurrenceDays"] as? [Int] {
            record.recurrenceDays = val
        }
        if let val = json["endRuleType"], let typeStr = DriveService.safeString(from: val), let type = RecurrenceEndRuleType(rawValue: typeStr) {
            record.endRuleType = type
        }
        if let val = json["endRuleCount"] as? Int {
            record.endRuleCount = val
        }
        
        // Alert and display fields
        if let val = json["alertOffsets"] as? [Int] {
            record.alertOffsets = val
        }
        if let val = json["isAllDay"] { record.isAllDay = DriveService.safeBool(from: val) }
        if let val = json["isPinned"] { record.isPinned = DriveService.safeBool(from: val) }
        if let val = json["sortOrder"] as? Int { record.sortOrder = val }
        
        // Icon and color fields
        if let val = json["iconFrameRaw"], let frameStr = DriveService.safeString(from: val) {
            record.iconFrameRaw = frameStr
        }
        if let val = json["themeColorHex"], let colorHex = DriveService.safeString(from: val) {
            record.themeColorHex = colorHex
        }
        if let val = json["iconSymbol"], let symbol = DriveService.safeString(from: val) {
            record.iconSymbol = symbol
        }
        
        // Optional text fields
        if let val = json["notes"], let notes = DriveService.safeString(from: val) {
            record.notes = notes
        }
        if let val = json["compound"], let compound = DriveService.safeString(from: val) {
            record.compound = compound
        }
        
        // Note: Relationship IDs (atomTemplateIDs, instanceIDs) are not applied here
        // They require separate reconciliation logic to resolve UUIDs to actual objects
    }
    
    private nonisolated func applyJSONToMoleculeInstance(json: [String: Any], record: MoleculeInstance) {
        // Basic fields
        if let val = json["isCompleted"] { record.isCompleted = DriveService.safeBool(from: val) }
        if let val = json["isDeleted"] { record.isArchived = DriveService.safeBool(from: val) }
        if let val = json["isException"] { record.isException = DriveService.safeBool(from: val) }
        if let val = json["isAllDay"] { record.isAllDay = DriveService.safeBool(from: val) }
        
        // Date fields
        let formatter = ISO8601DateFormatter()
        if let val = json["scheduledDate"], let dateStr = DriveService.safeString(from: val), let date = formatter.date(from: dateStr) {
            record.scheduledDate = date
        }
        if let val = json["completedAt"], let dateStr = DriveService.safeString(from: val), let date = formatter.date(from: dateStr) {
            record.completedAt = date
        }
        if let val = json["exceptionTime"], let dateStr = DriveService.safeString(from: val), let date = formatter.date(from: dateStr) {
            record.exceptionTime = date
        }
        if let val = json["originalScheduledDate"], let dateStr = DriveService.safeString(from: val), let date = formatter.date(from: dateStr) {
            record.originalScheduledDate = date
        }
        if let val = json["createdAt"], let dateStr = DriveService.safeString(from: val), let date = formatter.date(from: dateStr) {
            record.createdAt = date
        }
        
        // Alert offsets
        if let val = json["alertOffsets"] as? [Int] {
            record.alertOffsets = val
        }
        
        // Optional text fields
        if let val = json["notes"], let notes = DriveService.safeString(from: val) {
            record.notes = notes
        }
        if let val = json["exceptionTitle"], let title = DriveService.safeString(from: val) {
            record.exceptionTitle = title
        }
        
        // Note: Parent relationship (moleculeTemplateID) and child relationships (atomInstanceIDs)
        // require separate reconciliation logic to resolve UUIDs to actual objects
    }
    
    private nonisolated func applyJSONToAtomTemplate(json: [String: Any], record: AtomTemplate) {
        // Basic fields
        if let val = json["title"], let title = DriveService.safeString(from: val) { record.title = title }
        if let val = json["isDeleted"] { record.isArchived = DriveService.safeBool(from: val) }
        if let val = json["order"] as? Int { record.order = val }
        
        // Date fields
        let formatter = ISO8601DateFormatter()
        if let val = json["createdAt"], let dateStr = DriveService.safeString(from: val), let date = formatter.date(from: dateStr) {
            record.createdAt = date
        }
        
        // Input type
        if let val = json["inputType"], let typeStr = DriveService.safeString(from: val), let inputType = AtomInputType(rawValue: typeStr) {
            record.inputType = inputType
        }
        
        // Target and unit fields
        if let val = json["targetValue"] as? Double {
            record.targetValue = val
        }
        if let val = json["unit"], let unit = DriveService.safeString(from: val) {
            record.unit = unit
        }
        
        // Workout fields
        if let val = json["targetSets"] as? Int {
            record.targetSets = val
        }
        if let val = json["targetReps"] as? Int {
            record.targetReps = val
        }
        if let val = json["defaultRestTime"] as? Double {
            record.defaultRestTime = val
        }
        if let val = json["videoURL"], let url = DriveService.safeString(from: val) {
            record.videoURL = url
        }
        
        // Icon and color fields
        if let val = json["iconFrameRaw"], let frameStr = DriveService.safeString(from: val) {
            record.iconFrameRaw = frameStr
        }
        if let val = json["themeColorHex"], let colorHex = DriveService.safeString(from: val) {
            record.themeColorHex = colorHex
        }
        if let val = json["iconSymbol"], let symbol = DriveService.safeString(from: val) {
            record.iconSymbol = symbol
        }
        
        // Note: Parent relationship (moleculeTemplateID) requires separate reconciliation logic
    }
    
    // MARK: - Private: Folder Helpers
    
    private func configureService() async throws {
        let user = await MainActor.run { GoogleAuthManager.shared.currentUser }
        guard let user = user else {
            throw DriveError.notSignedIn
        }
        service.authorizer = user.fetcherAuthorizer
    }
    
    private func findOrCreateFolder(name: String, parentID: String?) async throws -> String {
        if let existingID = try await searchForFolder(name: name, parentID: parentID) {
            return existingID
        }
        return try await createFolder(name: name, parentID: parentID)
    }
    
    private func searchForFolder(name: String, parentID: String?) async throws -> String? {
        AppLogger.backup.debug("Searching for folder: '\(name)' in \(parentID ?? "root")")
        
        // Use raw URLSession to bypass SDK's problematic object parsing
        // The SDK crashes internally on type mismatches we can't catch
        guard let accessToken = await getAccessToken() else {
            throw DriveError.notSignedIn
        }
        
        let parentClause = parentID != nil ? "'\(parentID!)' in parents" : "'root' in parents"
        let queryString = "name = '\(name)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false and \(parentClause)"
        
        guard let encodedQuery = queryString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name)") else {
            throw DriveError.invalidData
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            AppLogger.backup.error("❌ Drive API returned non-200 status")
            throw DriveError.unknown
        }
        
        // Parse JSON ourselves - safe from SDK's type casting issues
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            AppLogger.backup.debug("Folder '\(name)' not found (empty or invalid response)")
            return nil
        }
        
        // Safely extract the first file's ID
        if let firstFile = files.first, let fileID = DriveService.safeString(from: firstFile["id"]) {
            AppLogger.backup.debug("Found folder '\(name)' with ID: \(fileID)")
            return fileID
        }
        
        AppLogger.backup.debug("Folder '\(name)' not found")
        return nil
    }
    
    /// Gets the current access token from Google Sign-In
    private func getAccessToken() async -> String? {
        return await MainActor.run {
            GoogleAuthManager.shared.currentUser?.accessToken.tokenString
        }
    }
    
    private func createFolder(name: String, parentID: String?) async throws -> String {
        guard let accessToken = await getAccessToken() else {
            throw DriveError.notSignedIn
        }
        
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files?fields=id") else {
            throw DriveError.invalidData
        }
        
        var metadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        
        if let parentID = parentID {
            metadata["parents"] = [parentID]
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            AppLogger.backup.error("❌ Failed to create folder: \(name)")
            throw DriveError.creationFailed
        }
        
        // Parse response to get folder ID
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let folderID = DriveService.safeString(from: json["id"]) else {
            throw DriveError.creationFailed
        }
        
        AppLogger.backup.debug("Created folder '\(name)' with ID: \(folderID)")
        return folderID
    }
    
    private func execute(_ query: GTLRQuery) async throws -> Any? {
        AppLogger.backup.debug("Executing GTLRQuery: \(type(of: query))")
        return try await withCheckedThrowingContinuation { continuation in
            // Wrap the callback execution in ObjC exception catcher
            // This prevents crashes from type casting errors inside the Google SDK
            var result: Any?
            var queryError: Error?
            
            service.executeQuery(query) { ticket, queryResult, error in
                // This callback may throw ObjC exceptions when accessing result properties
                var objcError: NSError?
                let success = ObjCTryCatch({
                    if let error = error {
                        queryError = error
                    } else {
                        result = queryResult
                    }
                }, &objcError)
                
                if !success, let objcError = objcError {
                    AppLogger.backup.error("❌ ObjC exception in GTLRQuery callback: \(objcError.localizedDescription)")
                    continuation.resume(throwing: DriveError.unknown)
                } else if let queryError = queryError {
                    AppLogger.backup.error("GTLRQuery failed: \(queryError.localizedDescription)")
                    continuation.resume(throwing: queryError)
                } else {
                    AppLogger.backup.debug("GTLRQuery success: \(type(of: result))")
                    continuation.resume(returning: result)
                }
            }
        }
    }
}

// MARK: - Errors

enum DriveError: LocalizedError {
    case notSignedIn
    case creationFailed
    case uploadFailed
    case downloadFailed
    case invalidData
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "User is not signed in to Google."
        case .creationFailed: return "Failed to create folder on Drive."
        case .uploadFailed: return "Failed to upload file to Drive."
        case .downloadFailed: return "Failed to download file from Drive."
        case .invalidData: return "Invalid data format received from Drive."
        case .unknown: return "An unknown error occurred."
        }
    }
}

// MARK: - Safe Type Extensions

extension GTLRDrive_File {
    /// Safely extracts identifier - ONLY uses raw JSON to avoid NSNumber→NSString crash
    /// Never call self.identifier directly as it performs unsafe casting internally
    var safeIdentifier: String? {
        guard let json = self.json, let val = json["id"] else {
            // Log warning but don't crash - return nil instead of trying self.identifier
            AppLogger.backup.warning("⚠️ GTLRDrive_File missing 'id' in JSON dictionary")
            return nil
        }
        return DriveService.safeString(from: val)
    }
    
    /// Safely extracts name - ONLY uses raw JSON to avoid NSNumber→NSString crash
    /// Never call self.name directly as it performs unsafe casting internally
    var safeName: String? {
        guard let json = self.json, let val = json["name"] else {
            AppLogger.backup.warning("⚠️ GTLRDrive_File missing 'name' in JSON dictionary")
            return nil
        }
        return DriveService.safeString(from: val)
    }
}

// MARK: - Type Safety Helpers

extension DriveService {
    /// Publicly exposed (internal) helper for safe string extraction
    static func safeString(from value: Any?) -> String? {
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        if let int = value as? Int { return String(int) }
        return nil
    }
    
    /// Publicly exposed (internal) helper for safe boolean extraction
    static func safeBool(from value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let num = value as? NSNumber { return num.boolValue }
        if let str = value as? String { return str.lowercased() == "true" }
        return false
    }
}

