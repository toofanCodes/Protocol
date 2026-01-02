//
//  DesignTokens.swift
//  Protocol
//
//  Design System - Global constants for consistent UI
//

import SwiftUI

// MARK: - Design Tokens

enum DesignTokens {
    // MARK: Corner Radii
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 16
    static let cornerRadiusLarge: CGFloat = 24
    
    // MARK: Padding
    static let paddingSmall: CGFloat = 8
    static let paddingStandard: CGFloat = 16
    static let paddingLarge: CGFloat = 24
    
    // MARK: Touch Targets
    static let minTouchTarget: CGFloat = 44
    
    // MARK: Animation
    static let springResponse: Double = 0.4
    static let springDamping: Double = 0.7
}

// MARK: - Empire Color Palette

extension Color {
    /// Empire Gold - Use for streaks, achievements, premium highlights
    static let empireGold = Color(red: 0.85, green: 0.65, blue: 0.13)
    
    /// Empire Bronze - Use for secondary accents, progress indicators
    static let empireBronze = Color(red: 0.80, green: 0.50, blue: 0.20)
    
    /// Empire Charcoal - Use for headers on light mode, premium text
    static let empireCharcoal = Color(red: 0.15, green: 0.15, blue: 0.18)
}

// MARK: - Haptic Helpers

enum HapticFeedback {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
