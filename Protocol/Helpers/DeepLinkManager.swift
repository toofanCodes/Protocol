//
//  DeepLinkManager.swift
//  Protocol
//
//  Manages navigation state for deep links from notifications.
//

import Foundation
import Combine

/// Observable object that coordinates deep linking from notifications
/// to the appropriate view in the app.
@MainActor
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    /// The instance ID to navigate to (set when notification is tapped)
    @Published var pendingInstanceId: UUID?
    
    private init() {}
    
    /// Called when a notification is tapped - triggers navigation
    func navigateToInstance(_ instanceId: UUID) {
        pendingInstanceId = instanceId
    }
    
    /// Called after navigation is complete to clear state
    func clearPendingNavigation() {
        pendingInstanceId = nil
    }
}
