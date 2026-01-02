//
//  AtomInstanceRowView.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData

/// Row view for displaying an AtomInstance with interactive controls
struct AtomInstanceRowView: View {
    
    @Bindable var atom: AtomInstance
    @EnvironmentObject var moleculeService: MoleculeService
    
    var body: some View {
        HStack(spacing: 12) {
            // Input control
            inputControl
            
            // Title and progress
            VStack(alignment: .leading, spacing: 2) {
                Text(atom.title)
                    .font(.system(.body, design: .default, weight: .regular))
                    .strikethrough(atom.isCompleted && atom.inputType == .binary)
                    .foregroundStyle(atom.isCompleted ? .secondary : .primary)
                
                if atom.inputType != .binary {
                    Text(atom.progressDisplayString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Progress indicator for counter/value
            if atom.inputType != .binary {
                ProgressView(value: atom.progress)
                    .frame(width: 50)
                    .tint(atom.isCompleted ? .green : Color.accentColor)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    // MARK: - Input Control
    
    @ViewBuilder
    private var inputControl: some View {
        switch atom.inputType {
        case .binary:
            Button {
                HapticFeedback.light()
                withAnimation(.spring(response: DesignTokens.springResponse, dampingFraction: DesignTokens.springDamping)) {
                    atom.toggleComplete()
                }
            } label: {
                Image(systemName: atom.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(atom.isCompleted ? .green : .secondary)
                    .frame(width: DesignTokens.minTouchTarget, height: DesignTokens.minTouchTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            
        case .counter:
            HStack(spacing: 8) {
                Button {
                    HapticFeedback.light()
                    withAnimation(.spring(response: DesignTokens.springResponse, dampingFraction: DesignTokens.springDamping)) {
                        atom.decrement()
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(atom.currentValue ?? 0 > 0 ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(width: DesignTokens.minTouchTarget, height: DesignTokens.minTouchTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(atom.currentValue ?? 0 <= 0)
                
                Text("\(Int(atom.currentValue ?? 0))")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 24)
                
                Button {
                    HapticFeedback.light()
                    withAnimation(.spring(response: DesignTokens.springResponse, dampingFraction: DesignTokens.springDamping)) {
                        atom.increment()
                        moleculeService.checkForProgression(atomInstance: atom)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(Color.accentColor)
                        .frame(width: DesignTokens.minTouchTarget, height: DesignTokens.minTouchTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
        case .value:
            Image(systemName: atom.isCompleted ? "checkmark.circle.fill" : "pencil.circle")
                .font(.title2)
                .foregroundColor(atom.isCompleted ? .green : Color.accentColor)
                .frame(width: DesignTokens.minTouchTarget, height: DesignTokens.minTouchTarget)
        }
    }
}

// MARK: - Value Entry Sheet

struct AtomValueEntrySheet: View {
    @Bindable var atom: AtomInstance
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var moleculeService: MoleculeService
    
    @State private var valueText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Enter value", text: $valueText)
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                        
                        if let unit = atom.unit {
                            Text(unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(atom.title)
                } footer: {
                    if let target = atom.targetValue {
                        Text("Target: \(Int(target)) \(atom.unit ?? "")")
                    }
                }
            }
            .navigationTitle("Enter Value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = Double(valueText) {
                            atom.setValue(value)
                            moleculeService.checkForProgression(atomInstance: atom)
                        }
                        dismiss()
                    }
                    .disabled(Double(valueText) == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let current = atom.currentValue {
                    valueText = String(format: current.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", current)
                }
                isFocused = true
            }
        }
        .presentationDetents([.height(200)])
    }
}

// MARK: - Preview

#Preview {
    List {
        Text("Atom Instance Row Preview")
            .font(.headline)
        Text("Run in simulator to see full functionality")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
