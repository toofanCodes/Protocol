//
//  UserSettings.swift
//  Protocol
//
//  A singleton-like model for storing app-wide user preferences.
//  Uses JSON metadata for flexible, migration-free storage of new preferences.
//

import Foundation
import SwiftData

/// Stores app-wide user settings and preferences.
/// This is designed as a singleton-like model — only one instance should exist.
@Model
final class UserSettings {
    
    // MARK: - Properties
    
    /// Unique identifier (should always be the same for singleton behavior)
    var id: UUID
    
    /// Creation timestamp
    var createdAt: Date
    
    /// Last modification timestamp
    var updatedAt: Date
    
    /// JSON-encoded metadata for flexible storage
    /// This field stores arbitrary configurations without requiring schema migrations.
    var metadataJSON: Data?
    
    // MARK: - Initialization
    
    init(id: UUID = UserSettings.singletonID) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.metadataJSON = nil
    }
    
    // MARK: - Singleton ID
    
    /// Fixed UUID for singleton behavior
    static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    
    // MARK: - Metadata Access
    
    /// Type-safe access to metadata
    var metadata: AppMetadata {
        get {
            guard let data = metadataJSON else { return .default }
            do {
                return try JSONDecoder().decode(AppMetadata.self, from: data)
            } catch {
                return .default
            }
        }
        set {
            do {
                metadataJSON = try JSONEncoder().encode(newValue)
                updatedAt = Date()
            } catch {
                // Encoding failure is non-critical, silently ignored
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Updates a specific metadata property
    func updateMetadata(_ transform: (inout AppMetadata) -> Void) {
        var current = metadata
        transform(&current)
        metadata = current
    }
    
    /// Checks if a feature flag is enabled
    func isFeatureEnabled(_ key: String) -> Bool {
        metadata.isFeatureEnabled(key)
    }
    
    /// Sets a feature flag
    func setFeatureFlag(_ key: String, enabled: Bool) {
        updateMetadata { $0.experimentFlags[key] = enabled }
    }
    
    // MARK: - Fetch/Create
    
    /// Fetches or creates the singleton UserSettings instance
    @MainActor
    static func current(in context: ModelContext) -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate<UserSettings> { $0.id == singletonID }
        )
        
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        
        // Create new instance
        let settings = UserSettings()
        context.insert(settings)
        return settings
    }
}

// MARK: - Hashable

extension UserSettings: Hashable {
    static func == (lhs: UserSettings, rhs: UserSettings) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
