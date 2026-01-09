//
//  AppMigrationPlan.swift
//  Protocol
//
//  Created on 2026-01-04.
//
//  Defines the versioned schema and migration plan for SwiftData.
//  This provides a formal baseline for future schema migrations.
//
//  ## Migration Notes
//
//  ### V2 → V3 (2026-01-07)
//  Added `updatedAt: Date` to `AtomTemplate` for sync tracking.
//
//  **Backup Restoration Behavior:**
//  When restoring a pre-V3 backup, `AtomTemplate.updatedAt` will be set to the
//  restore time (Date()), NOT the original modification time. This is expected
//  because:
//  - The field didn't exist in older schemas
//  - Future edits will update it correctly
//  - For sync purposes, "restored now" is an acceptable baseline
//
//  If you need the original modification time, consider using `createdAt` as a
//  fallback when `updatedAt` equals restore time.
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

// MARK: - Schema Version 3

/// Schema version 3.0.0 - Adds sync support properties.
/// New properties:
/// - AtomTemplate: updatedAt (Date) - for incremental sync tracking
enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    
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
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }
    
    /// Lightweight migrations between versions.
    /// All new properties have defaults so lightweight migration is sufficient.
    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }
    
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
    
    /// V2 → V3: AtomTemplate gains updatedAt: Date = Date()
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )
}

