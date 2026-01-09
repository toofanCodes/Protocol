//
//  GoogleAuthManager.swift
//  Protocol
//
//  Created on 2026-01-07.
//

import Foundation
import GoogleSignIn
import UIKit

/// Manages Google Sign-In authentication and Drive API access
@MainActor
final class GoogleAuthManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = GoogleAuthManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var currentUser: GIDGoogleUser?
    @Published private(set) var errorMessage: String?
    
    // MARK: - Constants
    
    /// Drive file scope - allows app to create/access only files it created
    private let driveScope = "https://www.googleapis.com/auth/drive.file"
    
    // MARK: - Initialization
    
    private init() {
        // Check if user is already signed in
        if GIDSignIn.sharedInstance.hasPreviousSignIn() {
            isSignedIn = true
        }
    }
    
    // MARK: - Public Methods
    
    /// Attempts to restore a previous sign-in session silently
    /// Call this on app launch to maintain signed-in state
    func restorePreviousSignIn() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
            return
        }
        
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            handleSignInSuccess(user: user)
            AppLogger.auth.info("✅ Restored previous sign-in for: \(user.profile?.email ?? "unknown")")
        } catch {
            AppLogger.auth.error("⚠️ Failed to restore sign-in: \(error.localizedDescription)")
            isSignedIn = false
            currentUser = nil
        }
    }
    
    /// Initiates interactive Google Sign-In flow
    /// - Parameter presentingViewController: The view controller to present the sign-in UI from
    func signIn(presentingViewController: UIViewController) async throws {
        // AppLogger.auth.debug("🔍 CLIENT_ID check passed") // Debug: verify plist is readable
        
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: [driveScope]
            )
            
            handleSignInSuccess(user: result.user)
            AppLogger.auth.info("✅ Sign-in successful for: \(result.user.profile?.email ?? "unknown")")
            
        } catch let error as GIDSignInError {
            switch error.code {
            case .canceled:
                AppLogger.auth.info("ℹ️ Sign-in canceled by user")
            case .hasNoAuthInKeychain:
                AppLogger.auth.warning("⚠️ No auth in keychain")
            default:
                AppLogger.auth.error("❌ Sign-in error: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Signs out the current user
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        currentUser = nil
        errorMessage = nil
        AppLogger.auth.info("✅ Signed out successfully")
    }
    
    /// Disconnects the app from the user's Google account (revokes access)
    func disconnect() async {
        do {
            try await GIDSignIn.sharedInstance.disconnect()
            isSignedIn = false
            currentUser = nil
            AppLogger.auth.info("✅ Disconnected from Google account")
        } catch {
            AppLogger.auth.error("❌ Failed to disconnect: \(error.localizedDescription)")
        }
    }
    
    /// Returns the current access token for API calls
    /// Refreshes the token if needed
    func getAccessToken() async -> String? {
        guard let user = currentUser else { return nil }
        
        do {
            // This refreshes the token if expired
            try await user.refreshTokensIfNeeded()
            return user.accessToken.tokenString
        } catch {
            AppLogger.auth.error("❌ Failed to refresh token: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func handleSignInSuccess(user: GIDGoogleUser) {
        currentUser = user
        isSignedIn = true
        errorMessage = nil
        
        // Print token for verification (Debug level)
        let tokenPrefix = String(user.accessToken.tokenString.prefix(20))
        AppLogger.auth.debug("🔑 Access Token (first 20 chars): \(tokenPrefix)...")
    }
    
    /// Reads CLIENT_ID from GoogleService-Info.plist
    private var clientID: String {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String else {
            fatalError("❌ [GoogleAuth] Could not find CLIENT_ID in GoogleService-Info.plist")
        }
        return clientID
    }
}

// MARK: - UIApplication Helper

extension UIApplication {
    /// Gets the root view controller for presenting sign-in
    var rootViewController: UIViewController? {
        guard let windowScene = connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }
        return window.rootViewController
    }
}
