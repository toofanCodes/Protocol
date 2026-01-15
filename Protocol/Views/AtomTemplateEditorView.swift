//
//  AtomTemplateEditorView.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData

/// Editor view for creating or editing an AtomTemplate
struct AtomTemplateEditorView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - ViewModel
    
    @StateObject private var viewModel: AtomTemplateEditorViewModel
    
    // Query for future instances (needed for cascade saving)
    @Query private var allAtomInstances: [AtomInstance]
    
    // MARK: - Initialization
    
    init(parentTemplate: MoleculeTemplate, existingAtom: AtomTemplate? = nil) {
        _viewModel = StateObject(wrappedValue: AtomTemplateEditorViewModel(
            parentTemplate: parentTemplate,
            existingAtom: existingAtom
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // Icon Section
                Section {
                    HStack {
                        Spacer()
                        Button {
                            viewModel.showingIconEditor = true
                        } label: {
                            AvatarView(
                                text: viewModel.iconSymbol,
                                fallbackText: viewModel.title.isEmpty ? "?" : viewModel.title,
                                shape: viewModel.iconFrame,
                                color: viewModel.themeColor,
                                size: 60
                            )
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Tap to customize icon")
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                
                // Title Section
                Section("Task Name") {
                    TextField("e.g., Drink Water", text: $viewModel.title)
                }
                
                // Input Type Section
                Section {
                    Picker("Input Type", selection: $viewModel.inputType) {
                        ForEach(AtomInputType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName)
                            .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Tracking Method")
                } footer: {
                    Text(viewModel.inputType.description)
                    .font(.caption)
                }
                
                // Target Value Section (for counter/value types)
                if viewModel.inputType != .binary {
                    Section("Target") {
                        HStack {
                            TextField("Value", text: $viewModel.targetValue)
                            .keyboardType(.decimalPad)
                            
                            TextField("Unit (optional)", text: $viewModel.unit)
                            .frame(maxWidth: 120)
                        }
                    }
                }
                
                // Workout Configuration (for value type)
                if viewModel.inputType == .value {
                    Section {
                        Toggle("Timed Sessions", isOn: $viewModel.isWorkoutExercise)
                    } footer: {
                        Text("Enable to track sets, reps, and rest intervals between timed sessions.")
                    }
                    
                    if viewModel.isWorkoutExercise {
                        Section("Workout Settings") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    TextField("4", text: $viewModel.targetSets)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    TextField("12", text: $viewModel.targetReps)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Rest (sec)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    TextField("60", text: $viewModel.restTime)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }
                }
                
                // Instructional Video Section
                Section("Instructional Video") {
                    TextField("Paste YouTube/Video URL here", text: $viewModel.videoURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                
                // Audio Recording Settings (only for audio type)
                if viewModel.inputType == .audio {
                    Section {
                        Toggle("Snoring Detection", isOn: $viewModel.enableSnoringDetection)
                        
                        if viewModel.enableSnoringDetection {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Sensitivity")
                                    Spacer()
                                    Text("\(Int(viewModel.snoringThreshold))%")
                                    .foregroundStyle(.secondary)
                                }
                                Slider(value: $viewModel.snoringThreshold, in: 20...80, step: 5)
                            }
                        }
                        
                        Picker("Duration", selection: $viewModel.recordingDuration) {
                            ForEach(RecordingDuration.presets, id: \.self) { duration in
                                Text(duration.displayString).tag(duration)
                            }
                        }
                        
                        Toggle("Save Full Recording", isOn: $viewModel.saveFullRecording)
                    } header: {
                        Label("Audio Settings", systemImage: "waveform")
                    } footer: {
                        if viewModel.saveFullRecording {
                            Text("Full recordings use ~20MB per night. Recommended: keep off to save only snoring clips (~2MB).")
                            .foregroundStyle(.orange)
                        } else {
                            Text("Only snoring clips will be saved. Enable snoring detection to track sleep quality.")
                        }
                    }
                }
                
                // Photo/Video info
                if viewModel.inputType == .photo || viewModel.inputType == .video {
                    Section {
                        HStack {
                            Image(systemName: viewModel.inputType == .photo ? "camera.fill" : "video.fill")
                            .foregroundStyle(.blue)
                            Text("Tap the task to capture \(viewModel.inputType == .photo ? "a photo" : "video")")
                            .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Media will be stored locally on your device.")
                    }
                }
                
                // Preview Section
                Section("Preview") {
                    AtomPreviewRow(
                        title: viewModel.title.isEmpty ? "Task Name" : viewModel.title,
                        inputType: viewModel.inputType,
                        targetValue: Double(viewModel.targetValue),
                        unit: viewModel.unit.isEmpty ? nil : viewModel.unit,
                        targetSets: viewModel.isWorkoutExercise ? Int(viewModel.targetSets) : nil,
                        targetReps: viewModel.isWorkoutExercise ? Int(viewModel.targetReps) : nil
                    )
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isEditing ? "Save" : "Add") {
                        viewModel.save(context: modelContext) {
                            dismiss()
                        }
                    }
                    .disabled(viewModel.title.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Update Future Events?",
                isPresented: $viewModel.showingCascadeDialog,
                titleVisibility: .visible
            ) {
                Button("Update This Template Only") {
                    viewModel.saveTemplateOnly(context: modelContext)
                    dismiss()
                }
                
                Button("Update Template & All Future Events") {
                    viewModel.saveWithCascade(context: modelContext, allInstances: allAtomInstances) {
                        dismiss()
                    }
                }
                
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You've changed structural properties. Do you want to update all future scheduled instances of this task?")
            }
        }
        .sheet(isPresented: $viewModel.showingIconEditor) {
            IconEditorSheet(
                iconSymbol: $viewModel.iconSymbol,
                iconFrame: $viewModel.iconFrame,
                themeColor: $viewModel.themeColor,
                fallbackText: viewModel.title.isEmpty ? "?" : viewModel.title
            )
        }
    }
}

// MARK: - Atom Preview Row

struct AtomPreviewRow: View {
    let title: String
    let inputType: AtomInputType
    let targetValue: Double?
    let unit: String?
    var targetSets: Int? = nil
    var targetReps: Int? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            // Input control preview
            switch inputType {
            case .binary:
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
            case .counter:
                HStack(spacing: 4) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                    Text("0/\(Int(targetValue ?? 0))")
                        .font(.caption)
                        .monospacedDigit()
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                
            case .value:
                if targetSets != nil {
                    // Workout exercise
                    Image(systemName: "dumbbell.fill")
                        .foregroundColor(Color.accentColor)
                } else {
                    HStack(spacing: 4) {
                        Text("—")
                            .foregroundStyle(.secondary)
                        if let unit = unit {
                            Text(unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
            case .photo:
                Image(systemName: "camera.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
            case .video:
                Image(systemName: "video.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
            case .audio:
                Image(systemName: "mic.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            
            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                
                // Workout target display
                if let sets = targetSets, let reps = targetReps {
                    Text("\(sets) Sets × \(reps) Reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Target indicator
            if inputType != .binary, let target = targetValue, targetSets == nil {
                Text("Goal: \(Int(target))\(unit != nil ? " \(unit!)" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    Text("Atom Template Editor Preview")
        .font(.headline)
}
