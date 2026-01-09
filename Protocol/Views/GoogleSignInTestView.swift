//
//  GoogleSignInTestView.swift
//  Protocol
//
//  Created on 2026-01-07.
//

import SwiftUI
import GoogleSignIn

/// Test view for verifying Google Sign-In integration
struct GoogleSignInTestView: View {
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @State private var isSigningIn = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: authManager.isSignedIn ? "checkmark.shield.fill" : "person.badge.key")
                    .font(.system(size: 60))
                    .foregroundStyle(authManager.isSignedIn ? .green : .gray)
                
                Text(authManager.isSignedIn ? "Signed In" : "Not Signed In")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top, 40)
            
            // User info (when signed in)
            if authManager.isSignedIn, let user = authManager.currentUser {
                VStack(spacing: 12) {
                    if let profileURL = user.profile?.imageURL(withDimension: 100) {
                        AsyncImage(url: profileURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                    }
                    
                    Text(user.profile?.name ?? "Unknown")
                        .font(.headline)
                    
                    Text(user.profile?.email ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
            }
            
            Spacer()
            
            // Error message
            if let error = authManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            // Sign In / Sign Out button
            if authManager.isSignedIn {
                VStack(spacing: 12) {
                    // Print token button
                    Button {
                        printAccessToken()
                    } label: {
                        Label("Print Access Token", systemImage: "key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    // Sign out button
                    Button(role: .destructive) {
                        authManager.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                // Google Sign-In button
                Button {
                    signIn()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "g.circle.fill")
                            .font(.title2)
                        Text("Sign in with Google")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isSigningIn)
            }
        }
        .padding()
        .navigationTitle("Google Sign-In Test")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Actions
    
    private func signIn() {
        guard let rootVC = UIApplication.shared.rootViewController else {
            print("❌ Could not get root view controller")
            return
        }
        
        isSigningIn = true
        
        Task {
            do {
                try await authManager.signIn(presentingViewController: rootVC)
            } catch {
                print("❌ Sign-in failed: \(error)")
            }
            isSigningIn = false
        }
    }
    
    private func printAccessToken() {
        Task {
            if let token = await authManager.getAccessToken() {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🔑 ACCESS TOKEN:")
                print(token)
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            } else {
                print("❌ No access token available")
            }
        }
    }
}

#Preview {
    NavigationStack {
        GoogleSignInTestView()
    }
}
