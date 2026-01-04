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

/// The initial (and current) schema version.
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

// MARK: - Migration Plan

/// The app's migration plan.
/// Currently defines only SchemaV1. When adding new properties or models,
/// create SchemaV2, add a migration stage, and update this plan.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }
    
    /// Migration stages. Empty for now since we only have one version.
    /// When adding SchemaV2, add a stage like:
    /// `static let migrateV1toV2 = MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`
    static var stages: [MigrationStage] {
        []
    }
}
