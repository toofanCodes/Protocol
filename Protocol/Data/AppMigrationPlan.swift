//
//  AppMigrationPlan.swift
//  Protocol
//
//  Created on 2026-01-04.
//
//  Defines the versioned schema and migration plan for SwiftData.
//  This provides a formal baseline for future schema migrations.
//

import SwiftData
import Foundation

// MARK: - Schema Version 1

/// The initial schema version.
/// Lists all persistent model types in the app.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [
            MoleculeTemplate.self,
            MoleculeInstance.self,
            AtomTemplate.self,
            AtomInstance.self,
            WorkoutSet.self,
            UserSettings.self
        ]
    }
}

// MARK: - Schema Version 2

/// Schema version 2.0.0 - Adds icon customization properties.
/// New properties:
/// - MoleculeTemplate: iconSymbol (String?), iconFrameRaw (String)
/// - AtomTemplate: iconSymbol (String?), iconFrameRaw (String)
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [
            MoleculeTemplate.self,
            MoleculeInstance.self,
            AtomTemplate.self,
            AtomInstance.self,
            WorkoutSet.self,
            UserSettings.self
        ]
    }
}

// MARK: - Migration Plan

/// The app's migration plan.
/// Defines schema versions and migration stages.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }
    
    /// Lightweight migration from V1 to V2.
    /// New properties have defaults (iconSymbol: nil, iconFrameRaw: "circle")
    /// so lightweight migration is sufficient.
    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}
