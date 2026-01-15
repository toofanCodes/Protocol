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
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var showValueEntry = false
    @State private var captureSession: CaptureSession?
    
    struct CaptureSession: Identifiable {
        let id = UUID()
        let settings: MediaCaptureSettings
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Input control
            inputControl
            
            // Title and progress
            VStack(alignment: .leading, spacing: 2) {
                Text(atom.title)
                    .font(.system(.body, design: .default, weight: .regular))
                    .strikethrough(atom.isCompleted && (atom.inputType == .binary || atom.inputType.isMediaType))
                    .foregroundStyle(atom.isCompleted ? .secondary : .primary)
                
                // Show subtitle for non-binary, non-media types
                if !atom.inputType.isMediaType && atom.inputType != .binary {
                    Text(atom.progressDisplayString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if atom.inputType.isMediaType && !atom.isCompleted {
                    Text("Tap to \(atom.inputType == .photo ? "take photo" : atom.inputType == .video ? "record video" : "start recording")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if atom.inputType.isMediaType && atom.isCompleted {
                    Text("Captured")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                handleRowTap()
            }
            
            Spacer()
            
            // Progress indicator for counter/value only
            if !atom.inputType.isMediaType && atom.inputType != .binary {
                ProgressView(value: atom.progress)
                    .frame(width: 50)
                    .tint(atom.isCompleted ? .green : Color.accentColor)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .sheet(isPresented: $showValueEntry) {
            AtomValueEntrySheet(atom: atom)
        }
        .sheet(item: $captureSession) { session in
            MediaCaptureSheet(atomInstance: atom, settings: session.settings)
        }
    }
    
    // MARK: - Actions
    
    private func handleRowTap() {
        switch atom.inputType {
        case .binary:
            HapticFeedback.light()
            withAnimation(.spring(response: DesignTokens.springResponse, dampingFraction: DesignTokens.springDamping)) {
                atom.toggleComplete()
            }
            
        case .value:
            showValueEntry = true
            
        case .photo, .video, .audio:
            prepareMediaCapture()
            
        case .counter:
            // No action on row tap for counter, as it has specific buttons
            break
        }
    }
    
    private func prepareMediaCapture() {
        var settingsToUse: MediaCaptureSettings
        
        // Resolve settings
        if let templateID = atom.sourceTemplateId {
            // Use specific lookup with simpler predicate to avoid confusion
            if let template = try? modelContext.fetch(FetchDescriptor<AtomTemplate>()).first(where: { $0.id == templateID }) {
                if let settings = template.mediaCaptureSettings {
                    settingsToUse = settings
                } else {
                    settingsToUse = createDefaultSettings()
                }
            } else {
                settingsToUse = createDefaultSettings()
            }
        } else {
            settingsToUse = createDefaultSettings()
        }
        
        // Set the session item to trigger the sheet
        self.captureSession = CaptureSession(settings: settingsToUse)
    }
    
    private func createDefaultSettings() -> MediaCaptureSettings {
        switch atom.inputType {
        case .audio: return .defaultAudio
        case .photo: return .defaultPhoto
        case .video: return .defaultVideo
        default: return .defaultPhoto
        }
    }
    
    // MARK: - Input Control
    
    @ViewBuilder
    private var inputControl: some View {
        switch atom.inputType {
        case .binary:
            Button {
                handleRowTap()
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
            Button {
                handleRowTap()
            } label: {
                Image(systemName: atom.isCompleted ? "checkmark.circle.fill" : "pencil.circle")
                    .font(.title2)
                    .foregroundColor(atom.isCompleted ? .green : Color.accentColor)
                    .frame(width: DesignTokens.minTouchTarget, height: DesignTokens.minTouchTarget)
            }
            .buttonStyle(.plain)
        
        case .photo:
            Button {
                handleRowTap()
            } label: {
                Image(systemName: atom.isCompleted ? "checkmark.circle.fill" : "camera.circle.fill")
                    .font(.title2)
                    .foregroundColor(atom.isCompleted ? .green : Color.accentColor)
                    .frame(width: DesignTokens.minTouchTarget, height: DesignTokens.minTouchTarget)
            }
            .buttonStyle(.plain)
        
        case .video:
            Button {
                handleRowTap()
            } label: {
                Image(systemName: atom.isCompleted ? "checkmark.circle.fill" : "video.circle.fill")
                    .font(.title2)
                    .foregroundColor(atom.isCompleted ? .green : Color.accentColor)
                    .frame(width: DesignTokens.minTouchTarget, height: DesignTokens.minTouchTarget)
            }
            .buttonStyle(.plain)
        
        case .audio:
            Button {
                handleRowTap()
            } label: {
                Image(systemName: atom.isCompleted ? "checkmark.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                    .foregroundColor(atom.isCompleted ? .green : Color.accentColor)
                    .frame(width: DesignTokens.minTouchTarget, height: DesignTokens.minTouchTarget)
            }
            .buttonStyle(.plain)
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
