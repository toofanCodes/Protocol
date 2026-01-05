//
//  GreetingCardView.swift
//  Protocol
//
//  Created on 2026-01-05.
//

import SwiftUI

/// A falling greeting card for Perfect Day celebration
struct GreetingCardView: View {
    @Binding var isShowing: Bool
    
    @State private var offsetY: CGFloat = -500
    @State private var cardOpacity: Double = 0
    @State private var shadowRadius: CGFloat = 20
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black
                .opacity(cardOpacity * 0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissCard()
                }
            
            // The Card
            VStack(spacing: 16) {
                // Crown icon
                Image(systemName: "crown.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.yellow)
                
                // Main message
                Text("Perfect Day!")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                
                // Subtitle
                Text("Great job building your empire.")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                // Dismiss hint
                Text("Tap anywhere to continue")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: shadowRadius, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.yellow.opacity(0.6), .orange.opacity(0.4), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .offset(y: offsetY)
            .opacity(cardOpacity)
        }
        .allowsHitTesting(cardOpacity > 0.5)
        .onAppear {
            triggerAnimation()
        }
    }
    
    private func triggerAnimation() {
        // Delay start (after color bomb begins)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Fade in
            withAnimation(.easeOut(duration: 0.2)) {
                cardOpacity = 1.0
            }
            
            // Fall with spring physics
            withAnimation(.interpolatingSpring(stiffness: 100, damping: 12)) {
                offsetY = 0
                shadowRadius = 30
            }
            
            // Settle shadow
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
                shadowRadius = 15
            }
            
            // Haptic on landing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
            }
            
            // Auto-dismiss after 5 seconds (user can tap to dismiss earlier)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if isShowing {
                    dismissCard()
                }
            }
        }
    }
    
    private func dismissCard() {
        // Exit animation
        withAnimation(.easeIn(duration: 0.3)) {
            offsetY = 800
            cardOpacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isShowing = false
        }
    }
}

#Preview {
    GreetingCardView(isShowing: .constant(true))
}
