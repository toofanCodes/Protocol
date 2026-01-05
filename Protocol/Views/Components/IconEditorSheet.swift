//
//  IconEditorSheet.swift
//  Protocol
//
//  Created on 2026-01-04.
//

import SwiftUI

/// A sheet for editing custom icon symbol, frame shape, and theme color
struct IconEditorSheet: View {
    // MARK: - Bindings
    
    @Binding var iconSymbol: String
    @Binding var iconFrame: IconFrameStyle
    @Binding var themeColor: Color
    
    // MARK: - Properties
    
    /// Fallback text to show in preview when symbol is empty
    let fallbackText: String
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var symbolInput: String = ""
    @State private var selectedShape: IconFrameStyle = .circle
    @State private var selectedColor: Color = .blue
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Live Preview Section
                Section {
                    HStack {
                        Spacer()
                        AvatarView(
                            text: symbolInput,
                            fallbackText: fallbackText,
                            shape: selectedShape,
                            color: selectedColor,
                            size: 80
                        )
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }
                
                // MARK: - Symbol Input Section
                Section {
                    HStack {
                        TextField("1-2 characters or emoji", text: $symbolInput)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .onChange(of: symbolInput) { _, newValue in
                                // Limit to 2 grapheme clusters
                                if newValue.count > 2 {
                                    symbolInput = String(newValue.prefix(2))
                                }
                            }
                        
                        if !symbolInput.isEmpty {
                            Button {
                                symbolInput = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Symbol")
                } footer: {
                    Text("Enter 1-2 characters, letters, or an emoji. Leave empty to use the first letter of the name.")
                }
                
                // MARK: - Shape Picker Section
                Section("Shape") {
                    Picker("Frame Shape", selection: $selectedShape) {
                        ForEach(IconFrameStyle.allCases) { shape in
                            HStack {
                                Image(systemName: shape.pickerSymbol)
                                Text(shape.displayName)
                            }
                            .tag(shape)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                
                // MARK: - Color Picker Section
                Section {
                    // Preset Color Palette
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Color.presetPalette, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(color)
                                            .frame(width: 36, height: 36)
                                        
                                        if colorsMatch(selectedColor, color) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(color.contrastingColor)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Custom Color Picker
                    ColorPicker("Custom Color", selection: $selectedColor, supportsOpacity: false)
                } header: {
                    Text("Color")
                } footer: {
                    Text("Choose a preset or pick a custom color.")
                }
                
                // MARK: - Quick Emoji Suggestions
                Section("Quick Picks") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(suggestedEmojis, id: \.self) { emoji in
                            Button {
                                symbolInput = emoji
                            } label: {
                                Text(emoji)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(symbolInput == emoji ? selectedColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Customize Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Initialize from bindings
                symbolInput = iconSymbol
                selectedShape = iconFrame
                selectedColor = themeColor
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Compare two colors by converting to hex (handles floating point variance)
    private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
        a.toHex() == b.toHex()
    }
    
    // MARK: - Actions
    
    private func saveAndDismiss() {
        iconSymbol = symbolInput.isEmpty ? "" : symbolInput
        iconFrame = selectedShape
        themeColor = selectedColor
        dismiss()
    }
    
    // MARK: - Data
    
    /// Suggested emojis for quick selection
    private var suggestedEmojis: [String] {
        [
            "💪", "🏃", "🧘", "🏋️", "🚴", "🏊",
            "💊", "💧", "🍎", "🥗", "🧠", "📚",
            "✏️", "💼", "🎯", "⭐", "🔥", "✨",
            "☀️", "🌙", "⏰", "📱", "🎵", "🧹"
        ]
    }
}

// MARK: - Preview

#Preview {
    IconEditorSheet(
        iconSymbol: .constant("💪"),
        iconFrame: .constant(.circle),
        themeColor: .constant(.blue),
        fallbackText: "Morning"
    )
}
