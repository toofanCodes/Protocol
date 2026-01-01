//
//  DataController.swift
//  Protocol
//
//  Created on 2025-12-31.
//

import SwiftData
import Foundation

@MainActor
class DataController {
    static let shared = DataController()
    
    // REPLACE THIS with your actual App Group ID from Xcode "Signing & Capabilities"
    static let appGroupIdentifier = "group.com.Toofan.Toofanprotocol.shared"
    
    let container: ModelContainer
    
    init() {
        let schema = Schema([
            MoleculeTemplate.self,
            MoleculeInstance.self,
            AtomTemplate.self,
            AtomInstance.self,
            WorkoutSet.self
        ])
        
        var modelConfiguration: ModelConfiguration
        var sqliteURL: URL?
        
        // Use App Group container if available, otherwise default
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            sqliteURL = url.appendingPathComponent("Protocol.sqlite")
            modelConfiguration = ModelConfiguration(
                schema: schema,
                url: sqliteURL!,
                allowsSave: true
            )
        } else {
            print("WARNING: Could not access App Group container. Falling back to default.")
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
        }
        
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("⚠️ ModelContainer creation failed: \(error)")
            print("⚠️ Attempting to recover by deleting old database...")
            
            // Delete the old database files and retry
            if let url = sqliteURL {
                let fileManager = FileManager.default
                let basePath = url.deletingLastPathComponent().path
                let dbName = url.deletingPathExtension().lastPathComponent
                
                // Delete all SQLite-related files
                let filesToDelete = [
                    "\(dbName).sqlite",
                    "\(dbName).sqlite-shm",
                    "\(dbName).sqlite-wal"
                ]
                
                for file in filesToDelete {
                    let filePath = (basePath as NSString).appendingPathComponent(file)
                    try? fileManager.removeItem(atPath: filePath)
                }
                
                print("✅ Deleted old database files. Creating fresh database...")
            }
            
            // Retry with fresh database
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("✅ Fresh database created successfully")
            } catch {
                fatalError("Could not create ModelContainer after recovery attempt: \(error)")
            }
        }
    }
}
