//
//  AvatarView.swift
//  Protocol
//
//  Created on 2026-01-04.
//

import SwiftUI

/// A customizable avatar view that displays 1-2 characters/emoji within a shaped frame
struct AvatarView: View {
    // MARK: - Properties
    
    /// The custom symbol text (emoji or characters)
    let text: String
    
    /// Fallback text to use if text is empty (typically name's first letter)
    let fallbackText: String
    
    /// The frame shape for the avatar
    let shape: IconFrameStyle
    
    /// The background color for the avatar
    let color: Color
    
    /// Size of the avatar (width and height)
    var size: CGFloat = 40
    
    // MARK: - Computed Properties
    
    /// The text to display, limited to 2 grapheme clusters
    /// Handles emojis and complex scripts (Hindi/Telugu) correctly
    private var displayText: String {
        let source = text.isEmpty ? fallbackText : text
        guard !source.isEmpty else { return "?" }
        
        // Use prefix to get up to 2 grapheme clusters
        // Swift handles Unicode grapheme clusters natively
        return String(source.prefix(2)).uppercased()
    }
    
    /// Font size scaled to the avatar size
    private var fontSize: CGFloat {
        // Smaller font for 2 characters, larger for 1
        let characterCount = displayText.count
        return characterCount > 1 ? size * 0.35 : size * 0.45
    }
    
    /// Smart contrast: returns black or white based on background luminance
    private var textColor: Color {
        color.contrastingColor
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            switch shape {
            case .circle:
                circleShape
            case .square:
                squareShape
            case .star:
                symbolShape(sfSymbol: "star.fill")
            case .triangle:
                symbolShape(sfSymbol: "triangle.fill")
            }
        }
        .frame(width: size, height: size)
    }
    
    // MARK: - Shape Views
    
    /// Circle shape with filled background and border
    private var circleShape: some View {
        ZStack {
            Circle()
                .fill(color)
            
            Text(displayText)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .overlay(
            Circle()
                .stroke(textColor.opacity(0.3), lineWidth: 1.5)
        )
    }
    
    /// Rounded square shape with filled background and border
    private var squareShape: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(color)
            
            Text(displayText)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22)
                .stroke(textColor.opacity(0.3), lineWidth: 1.5)
        )
    }
    
    /// SF Symbol background with text overlay and border (for star/triangle)
    private func symbolShape(sfSymbol: String) -> some View {
        ZStack {
            Image(systemName: sfSymbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(color)
            
            Text(displayText)
                .font(.system(size: fontSize * 0.8, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .offset(y: shape == .triangle ? size * 0.05 : 0) // Adjust for triangle center
        }
        // Applying border to SF Symbols is tricky as they aren't shapes.
        // We can add a shadow for contrast instead, which works for irregular shapes.
        .shadow(color: textColor.opacity(0.3), radius: 1, x: 0, y: 0)
    }
}

// MARK: - Convenience Initializers

extension AvatarView {
    /// Creates an AvatarView for a MoleculeTemplate using its theme color
    init(molecule: MoleculeTemplate, color: Color? = nil, size: CGFloat = 40) {
        self.text = molecule.iconSymbol ?? ""
        self.fallbackText = String(molecule.title.prefix(1))
        self.shape = molecule.iconFrame
        self.color = color ?? molecule.themeColor
        self.size = size
    }
    
    /// Creates an AvatarView for an AtomTemplate using its theme color
    init(atom: AtomTemplate, color: Color? = nil, size: CGFloat = 40) {
        self.text = atom.iconSymbol ?? ""
        self.fallbackText = String(atom.title.prefix(1))
        self.shape = atom.iconFrame
        self.color = color ?? atom.themeColor
        self.size = size
    }
}

// MARK: - Preview

#Preview("All Shapes") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            AvatarView(text: "🔥", fallbackText: "F", shape: .circle, color: .blue)
            AvatarView(text: "AB", fallbackText: "A", shape: .square, color: .purple)
            AvatarView(text: "⭐", fallbackText: "S", shape: .star, color: .orange)
            AvatarView(text: "T", fallbackText: "T", shape: .triangle, color: .green)
        }
        
        HStack(spacing: 16) {
            AvatarView(text: "", fallbackText: "Morning Routine", shape: .circle, color: .red)
            AvatarView(text: "💪", fallbackText: "W", shape: .square, color: .indigo, size: 60)
            AvatarView(text: "नम", fallbackText: "H", shape: .circle, color: .teal, size: 50)
        }
    }
    .padding()
}
