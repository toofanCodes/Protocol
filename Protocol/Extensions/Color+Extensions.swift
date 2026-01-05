//
//  Color+Extensions.swift
//  Protocol
//
//  Color utilities for hex conversion and contrast calculation.
//

import SwiftUI

extension Color {
    
    // MARK: - Hex Initialization
    
    /// Initialize Color from hex string (e.g., "#007AFF" or "007AFF")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let r, g, b: Double
        switch hex.count {
        case 3: // RGB (12-bit)
            r = Double((int >> 8) & 0xF) / 15.0
            g = Double((int >> 4) & 0xF) / 15.0
            b = Double(int & 0xF) / 15.0
        case 6: // RGB (24-bit)
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        case 8: // ARGB (32-bit) - ignore alpha, use solid
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0; g = 0.478; b = 1 // Default blue
        }
        
        self.init(red: r, green: g, blue: b)
    }
    
    // MARK: - Hex Conversion
    
    /// Convert Color to hex string (e.g., "#007AFF")
    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components else {
            return "#007AFF"
        }
        
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        
        if components.count >= 3 {
            r = components[0]
            g = components[1]
            b = components[2]
        } else if components.count >= 1 {
            // Grayscale
            r = components[0]
            g = components[0]
            b = components[0]
        } else {
            return "#007AFF"
        }
        
        let hex = String(
            format: "#%02X%02X%02X",
            Int(r * 255),
            Int(g * 255),
            Int(b * 255)
        )
        
        return hex
    }
    
    // MARK: - Contrast Calculation
    
    /// Returns true if the color is light (needs dark text for contrast)
    var isLightColor: Bool {
        guard let components = UIColor(self).cgColor.components else {
            return false
        }
        
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        
        if components.count >= 3 {
            r = components[0]
            g = components[1]
            b = components[2]
        } else if components.count >= 1 {
            // Grayscale
            r = components[0]
            g = components[0]
            b = components[0]
        } else {
            return false
        }
        
        // Use relative luminance formula (ITU-R BT.709)
        // Weights: R=0.2126, G=0.7152, B=0.0722
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        
        // Threshold: > 0.5 is considered light
        return luminance > 0.5
    }
    
    /// Returns a contrasting color (black or white) for optimal legibility
    var contrastingColor: Color {
        isLightColor ? .black : .white
    }
}

// MARK: - Preset Colors

extension Color {
    /// Curated palette of preset theme colors
    static let presetPalette: [Color] = [
        Color(hex: "#AECBFA"), // Blue (Pastel)
        Color(hex: "#CCFF90"), // Green (Pastel)
        Color(hex: "#FFCC80"), // Orange (Pastel)
        Color(hex: "#F28B82"), // Red (Pastel)
        Color(hex: "#E6C9FF"), // Purple (Pastel)
        Color(hex: "#C5CAE9"), // Indigo (Pastel)
        Color(hex: "#FDCFE8"), // Pink (Pastel)
        Color(hex: "#A7FFEB"), // Teal (Pastel)
        Color(hex: "#FFF59D"), // Yellow (Pastel)
        Color(hex: "#E0E0E0"), // Gray (Pastel)
    ]
    
    /// Default theme color hex
    static let defaultThemeHex = "#007AFF"
    
    /// Returns a deterministic color for a given compound name
    static func color(forCompound compound: String?) -> Color {
        guard let name = compound, !name.isEmpty else {
            return .accentColor // Default fallback
        }
        
        // Simple hash: sum of unicode scalars
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let index = abs(sum % presetPalette.count)
        
        return presetPalette[index]
    }
}
