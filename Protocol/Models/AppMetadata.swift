//
//  AppMetadata.swift
//  Protocol
//
//  A Codable struct for storing arbitrary JSON configurations.
//  This allows adding new preferences without triggering schema migrations.
//

import Foundation

/// Flexible metadata storage for user preferences and feature flags.
/// Add new properties here freely — changes are stored as JSON and don't require DB migrations.
struct AppMetadata: Codable {
    
    // MARK: - User Preferences
    
    /// Default alert offset in minutes (e.g., 15 = notify 15 min before)
    var defaultAlertOffset: Int = 15
    
    /// App theme preference
    var theme: ThemePreference = .system
    
    /// Whether to show completed items in the main list
    var showCompletedItems: Bool = true
    
    /// Default recurrence for new molecules
    var defaultRecurrence: String = "daily"
    
    // MARK: - Feature Flags
    
    /// Experiment flags for A/B testing or gradual rollouts
    var experimentFlags: [String: Bool] = [:]
    
    /// Check if a feature flag is enabled
    func isFeatureEnabled(_ key: String) -> Bool {
        experimentFlags[key] ?? false
    }
    
    // MARK: - App State
    
    /// Last sync timestamp (for future cloud sync)
    var lastSyncTimestamp: Date?
    
    /// Onboarding completion status
    var hasCompletedOnboarding: Bool = false
    
    /// App version that last modified settings (for future compatibility)
    var lastAppVersion: String?
    
    // MARK: - Default
    
    static let `default` = AppMetadata()
}

// MARK: - Theme Preference

enum ThemePreference: String, Codable, CaseIterable {
    case system
    case light
    case dark
}

// MARK: - Convenience Initializers

extension AppMetadata {
    /// Creates metadata with specific experiment flags
    static func withFlags(_ flags: [String: Bool]) -> AppMetadata {
        var metadata = AppMetadata()
        metadata.experimentFlags = flags
        return metadata
    }
}
