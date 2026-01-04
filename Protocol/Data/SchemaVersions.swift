//
//  SchemaVersions.swift
//  Protocol
//
//  For SwiftData migration support.
//  NOTE: VersionedSchema has been removed to avoid checksum conflicts.
//  SwiftData handles lightweight migration automatically when new properties have defaults.
//

import SwiftData
import Foundation

// MARK: - Current Schema
// We use a simple schema approach. SwiftData performs automatic lightweight migration
// for new properties with default values (like isAllDay: Bool = false).

// This file is kept for reference but is not actively used for versioning.
// The DataController now uses Schema([Model.self, ...]) directly.
