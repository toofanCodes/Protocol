//
//  SplashScreenView.swift
//  Protocol
//
//  Created on 2025-12-31.
//

import SwiftUI

/// Animated splash screen shown at app launch
struct SplashScreenView: View {
    @State private var isActive = false
    @State private var opacity: Double = 0
    
    var body: some View {
        if isActive {
            ContentView()
        } else {
            ZStack {
                // Background
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    // Logo
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150)
                    
                    // Tagline
                    Text("Laying the foundation of your empire, one habit brick at a time!")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                    
                    Spacer()
                    
                    // Footer
                    Text("® Saran Pavuluri 2026")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 30)
                }
                .opacity(opacity)
            }
            .onAppear {
                // Fade in animation
                withAnimation(.easeIn(duration: 1.0)) {
                    opacity = 1.0
                }
                
                // Transition to main app after 2.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        isActive = true
                    }
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
