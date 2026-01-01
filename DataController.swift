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
        
        let modelConfiguration: ModelConfiguration
        
        // Use App Group container if available, otherwise default
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            let sqliteURL = url.appendingPathComponent("Protocol.sqlite")
            modelConfiguration = ModelConfiguration(
                schema: schema,
                url: sqliteURL,
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
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
