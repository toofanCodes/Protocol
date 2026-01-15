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
//  ### V3 → V4 (2026-01-12)
//  Added media capture support:
//  - New models: MediaCapture, SnoringEvent
//  - AtomTemplate: mediaCaptureType (String?), mediaCaptureSettingsJSON (String?)
//  - AtomInstance: mediaCapture (MediaCapture?) relationship
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

// MARK: - Schema Version 4

/// Schema version 4.0.0 - Adds media capture support.
/// New models:
/// - MediaCapture: Stores metadata for photo/video/audio captures
/// - SnoringEvent: Individual snoring events detected during audio recording
/// New properties:
/// - AtomTemplate: mediaCaptureType (String?), mediaCaptureSettingsJSON (String?)
/// - AtomInstance: mediaCapture (MediaCapture?) relationship
enum SchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    
    // Note: MediaCapture and SnoringEvent are added directly in DataController.
    // SwiftData handles lightweight migration automatically for new models and
    // optional properties with defaults.
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
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }
    
    /// Lightweight migrations between versions.
    /// All new properties have defaults so lightweight migration is sufficient.
    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
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
    
    /// V3 → V4: Adds MediaCapture, SnoringEvent models and media capture properties
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self
    )
}

