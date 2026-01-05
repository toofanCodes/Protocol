//
//  ColorBombView.swift
//  Protocol
//
//  Created on 2026-01-05.
//

import SwiftUI

/// A radial gradient explosion that expands from center
struct ColorBombView: View {
    @Binding var isShowing: Bool
    
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var flashOpacity: Double = 0
    
    // Vibrant rainbow colors (Pastel)
    private let bombColors: [Color] = Color.presetPalette
    
    var body: some View {
        ZStack {
            // White flash at start
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
            
            // Radial gradient explosion
            RadialGradient(
                colors: bombColors + [.clear],
                center: .center,
                startRadius: 0,
                endRadius: 400
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .onAppear {
            triggerAnimation()
        }
    }
    
    private func triggerAnimation() {
        // White flash
        withAnimation(.easeOut(duration: 0.1)) {
            flashOpacity = 0.8
        }
        
        // Flash fade
        withAnimation(.easeIn(duration: 0.15).delay(0.1)) {
            flashOpacity = 0
        }
        
        // Explosion expand
        withAnimation(.easeOut(duration: 0.4)) {
            scale = 15
        }
        
        // Fade out
        withAnimation(.easeIn(duration: 0.3).delay(0.3)) {
            opacity = 0
        }
        
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        
        // Hide after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isShowing = false
        }
    }
}

#Preview {
    ColorBombView(isShowing: .constant(true))
}
