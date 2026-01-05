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
    
    // MARK: - Properties
    
    let parentTemplate: MoleculeTemplate
    var existingAtom: AtomTemplate?
    
    // MARK: - State
    
    @State private var title: String = ""
    @State private var inputType: AtomInputType = .binary
    @State private var targetValue: String = ""
    @State private var unit: String = ""
    @State private var videoURL: String = ""
    
    // Workout-specific state
    @State private var isWorkoutExercise: Bool = false
    @State private var targetSets: String = ""
    @State private var targetReps: String = ""
    @State private var restTime: String = ""
    
    // Original values for change detection
    @State private var originalTitle: String = ""
    @State private var originalTargetValue: String = ""
    @State private var originalUnit: String = ""
    @State private var originalVideoURL: String = ""
    @State private var originalTargetSets: String = ""
    @State private var originalTargetReps: String = ""
    @State private var originalRestTime: String = ""
    
    // Dialog state
    @State private var showingCascadeDialog = false
    @State private var showingIconEditor = false
    
    // Icon state
    @State private var iconSymbol: String = ""
    @State private var iconFrame: IconFrameStyle = .circle
    @State private var themeColor: Color = .blue
    
    // Query for future instances
    @Query private var allAtomInstances: [AtomInstance]
    
    private var isEditing: Bool {
        existingAtom != nil
    }
    
    private var hasStructuralChanges: Bool {
        guard isEditing else { return false }
        return title != originalTitle ||
               targetValue != originalTargetValue ||
               unit != originalUnit ||
               videoURL != originalVideoURL ||
               targetSets != originalTargetSets ||
               targetReps != originalTargetReps ||
               restTime != originalRestTime
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
                            showingIconEditor = true
                        } label: {
                            AvatarView(
                                text: iconSymbol,
                                fallbackText: title.isEmpty ? "?" : title,
                                shape: iconFrame,
                                color: themeColor,
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
                    TextField("e.g., Drink Water", text: $title)
                }
                
                // Input Type Section
                Section {
                    Picker("Input Type", selection: $inputType) {
                        ForEach(AtomInputType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Tracking Method")
                } footer: {
                    Text(inputType.description)
                        .font(.caption)
                }
                
                // Target Value Section (for counter/value types)
                if inputType != .binary {
                    Section("Target") {
                        HStack {
                            TextField("Value", text: $targetValue)
                                .keyboardType(.decimalPad)
                            
                            TextField("Unit (optional)", text: $unit)
                                .frame(maxWidth: 120)
                        }
                    }
                }
                
                // Workout Configuration (for value type)
                if inputType == .value {
                    Section {
                        Toggle("Timed Sessions", isOn: $isWorkoutExercise)
                    } footer: {
                        Text("Enable to track sets, reps, and rest intervals between timed sessions.")
                    }
                    
                    if isWorkoutExercise {
                        Section("Workout Settings") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sets")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("4", text: $targetSets)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reps")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("12", text: $targetReps)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Rest (sec)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("60", text: $restTime)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }
                }
                
                // Instructional Video Section
                Section("Instructional Video") {
                    TextField("Paste YouTube/Video URL here", text: $videoURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                // Preview Section
                Section("Preview") {
                    AtomPreviewRow(
                        title: title.isEmpty ? "Task Name" : title,
                        inputType: inputType,
                        targetValue: Double(targetValue),
                        unit: unit.isEmpty ? nil : unit,
                        targetSets: isWorkoutExercise ? Int(targetSets) : nil,
                        targetReps: isWorkoutExercise ? Int(targetReps) : nil
                    )
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveAtom()
                    }
                    .disabled(title.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadExistingValues()
            }
            .confirmationDialog(
                "Update Future Events?",
                isPresented: $showingCascadeDialog,
                titleVisibility: .visible
            ) {
                Button("Update This Template Only") {
                    saveTemplateOnly()
                }
                
                Button("Update Template & All Future Events") {
                    saveWithCascade()
                }
                
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You've changed structural properties. Do you want to update all future scheduled instances of this task?")
            }
        }
        .sheet(isPresented: $showingIconEditor) {
            IconEditorSheet(
                iconSymbol: $iconSymbol,
                iconFrame: $iconFrame,
                themeColor: $themeColor,
                fallbackText: title.isEmpty ? "?" : title
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func loadExistingValues() {
        guard let atom = existingAtom else { return }
        
        title = atom.title
        inputType = atom.inputType
        videoURL = atom.videoURL ?? ""
        
        if let target = atom.targetValue {
            targetValue = String(format: target.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", target)
        }
        
        unit = atom.unit ?? ""
        
        // Load workout settings
        if let sets = atom.targetSets {
            targetSets = String(sets)
            isWorkoutExercise = true
        }
        
        if let reps = atom.targetReps {
            targetReps = String(reps)
        }
        
        if let rest = atom.defaultRestTime {
            restTime = String(Int(rest))
        }
        
        // Save originals for change detection
        originalTitle = title
        originalTargetValue = targetValue
        originalUnit = unit
        originalVideoURL = videoURL
        originalTargetSets = targetSets
        originalTargetReps = targetReps
        originalRestTime = restTime
        
        // Load icon values
        iconSymbol = atom.iconSymbol ?? ""
        iconFrame = atom.iconFrame
        themeColor = atom.themeColor
    }
    
    private func saveAtom() {
        if isEditing && hasStructuralChanges {
            // Show cascade dialog
            showingCascadeDialog = true
        } else {
            // New atom or no changes - just save
            saveTemplateOnly()
        }
    }
    
    private func saveTemplateOnly() {
        let target = Double(targetValue)
        let unitValue = unit.isEmpty ? nil : unit
        let videoValue = videoURL.isEmpty ? nil : videoURL
        
        // Workout values
        let sets = isWorkoutExercise ? Int(targetSets) : nil
        let reps = isWorkoutExercise ? Int(targetReps) : nil
        let rest = isWorkoutExercise ? TimeInterval(restTime) : nil
        
        if let existingAtom = existingAtom {
            // Update existing template
            existingAtom.title = title
            existingAtom.inputType = inputType
            existingAtom.targetValue = inputType == .binary ? nil : target
            existingAtom.unit = inputType == .binary ? nil : unitValue
            existingAtom.videoURL = videoValue
            existingAtom.targetSets = sets
            existingAtom.targetReps = reps
            existingAtom.defaultRestTime = rest
            existingAtom.iconSymbol = iconSymbol.isEmpty ? nil : iconSymbol
            existingAtom.iconFrame = iconFrame
            existingAtom.themeColor = themeColor
        } else {
            // Create new
            let nextOrder = (parentTemplate.atomTemplates.map(\.order).max() ?? -1) + 1
            
            let newAtom = AtomTemplate(
                title: title,
                inputType: inputType,
                targetValue: inputType == .binary ? nil : target,
                unit: inputType == .binary ? nil : unitValue,
                order: nextOrder,
                targetSets: sets,
                targetReps: reps,
                defaultRestTime: rest,
                videoURL: videoValue,
                parentMoleculeTemplate: parentTemplate,
                iconSymbol: iconSymbol.isEmpty ? nil : iconSymbol,
                iconFrame: iconFrame
            )
            newAtom.themeColor = themeColor
            
            modelContext.insert(newAtom)
            parentTemplate.atomTemplates.append(newAtom)
        }
        
        try? modelContext.save()
        dismiss()
    }
    
    private func saveWithCascade() {
        guard let existingAtom = existingAtom else {
            saveTemplateOnly()
            return
        }
        
        let target = Double(targetValue)
        let unitValue = unit.isEmpty ? nil : unit
        let videoValue = videoURL.isEmpty ? nil : videoURL
        let sets = isWorkoutExercise ? Int(targetSets) : nil
        let reps = isWorkoutExercise ? Int(targetReps) : nil
        let rest = isWorkoutExercise ? TimeInterval(restTime) : nil
        
        // 1. Update Template
        existingAtom.title = title
        existingAtom.inputType = inputType
        existingAtom.targetValue = inputType == .binary ? nil : target
        existingAtom.unit = inputType == .binary ? nil : unitValue
        existingAtom.videoURL = videoValue
        existingAtom.targetSets = sets
        existingAtom.targetReps = reps
        existingAtom.defaultRestTime = rest
        
        // 2. Cascade to Future Instances
        let today = Calendar.current.startOfDay(for: Date())
        let futureInstances = allAtomInstances.filter { instance in
            instance.sourceTemplateId == existingAtom.id &&
            instance.parentMoleculeInstance?.scheduledDate ?? Date.distantPast >= today
        }
        
        for instance in futureInstances {
            instance.title = title
            instance.inputType = inputType
            instance.targetValue = inputType == .binary ? nil : target
            instance.unit = inputType == .binary ? nil : unitValue
            instance.videoURL = videoValue
            instance.targetSets = sets
            instance.targetReps = reps
            instance.defaultRestTime = rest
        }
        
        try? modelContext.save()
        dismiss()
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
