//
//  AtomDetailSheet.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData

/// Detailed sheet view for workout logging and notes
struct AtomDetailSheet: View {
    @Bindable var atom: AtomInstance
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var moleculeService: MoleculeService
    
    // MARK: - Timer State
    
    @State private var timerState: TimerState = .ready
    @State private var timerStartTime: Date?
    @State private var restStartTime: Date?
    @State private var displayedTime: TimeInterval = 0
    @State private var timer: Timer?
    
    // MARK: - Current Set State
    
    @State private var currentWeight: String = ""
    @State private var currentReps: String = ""
    
    // MARK: - Focus State for Keyboard
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case weight, reps
    }
    
    // MARK: - Edit Set State
    
    @State private var setToEdit: WorkoutSet?
    @State private var editWeight: String = ""
    @State private var editReps: String = ""
    
    // MARK: - Settings State
    
    @State private var showingEditor = false
    
    enum TimerState {
        case ready      // "Start Set"
        case working    // "Finish Set"
        case resting    // "End Rest" with countdown
    }
    
    // MARK: - Computed Properties
    
    private var restDuration: TimeInterval {
        atom.defaultRestTime ?? 45
    }
    
    /// Validates that weight and reps can be parsed as numbers
    private var isInputValid: Bool {
        guard !currentWeight.isEmpty || !currentReps.isEmpty else { return false }
        if !currentWeight.isEmpty && Double(currentWeight) == nil { return false }
        if !currentReps.isEmpty && Int(currentReps) == nil { return false }
        return true
    }
    
    private var remainingRestTime: TimeInterval {
        guard let start = restStartTime else { return restDuration }
        let elapsed = Date().timeIntervalSince(start)
        return max(0, restDuration - elapsed)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            List {
                // Header Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(atom.title)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let target = atom.workoutTargetString {
                            Text("Target: \(target)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Progress bar
                        HStack {
                            Text("\(atom.completedSetsCount)/\(atom.targetSets ?? 0) sets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(atom.progress * 100))%")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        ProgressView(value: atom.progress)
                            .tint(atom.isCompleted ? Color.green : Color.accentColor)
                    }
                    .padding(.vertical, 4)
                }
                
                // Timer & Action Button Section
                Section("Current Set") {
                    VStack(spacing: 16) {
                        // Timer Display
                        Text(formatTime(displayedTime))
                            .font(.system(size: 48, weight: .light, design: .monospaced))
                            .foregroundColor(timerState == .resting ? (remainingRestTime < 10 ? .red : .orange) : .primary)
                        
                        // State indicator
                        Text(stateIndicatorText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // Weight & Reps Input (visible when working or ready)
                        if timerState != .resting {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Weight")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        TextField("0", text: $currentWeight)
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                            .focused($focusedField, equals: .weight)
                                        Text(atom.unit ?? "lbs")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reps")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        TextField("0", text: $currentReps)
                                            .keyboardType(.numberPad)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                            .focused($focusedField, equals: .reps)
                                        Text("reps")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        
                        // Action Button
                        Button(action: handleTimerAction) {
                            Text(actionButtonText)
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(timerState == .working && !isInputValid ? Color.gray : actionButtonColor)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(timerState == .working && !isInputValid)
                        
                        // Helper text for invalid input
                        if timerState == .working && !isInputValid {
                            Text("Enter weight or reps to finish set")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Completed Sets Section
                if !atom.sets.isEmpty {
                    Section("Completed Sets") {
                        ForEach(atom.sortedSets) { set in
                            HStack {
                                Text("Set \(set.order)")
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                if let weight = set.weight {
                                    Text("\(Int(weight)) \(atom.unit ?? "lbs")")
                                        .foregroundStyle(.secondary)
                                }
                                
                                if let reps = set.reps {
                                    Text("× \(reps)")
                                        .foregroundStyle(.secondary)
                                }
                                
                                if let duration = set.formattedDuration {
                                    Text("(\(duration))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                
                                if set.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editWeight = set.weight.map { String(Int($0)) } ?? ""
                                editReps = set.reps.map { String($0) } ?? ""
                                setToEdit = set
                            }
                        }
                        .onDelete(perform: deleteSets)
                    }
                }
                
                // Notes Section
                Section("Notes") {
                    TextEditor(text: Binding(
                        get: { atom.notes ?? "" },
                        set: { atom.notes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 100)
                    .overlay(
                        Group {
                            if atom.notes == nil || atom.notes?.isEmpty == true {
                                Text("Add notes about this exercise...")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                            }
                        },
                        alignment: .topLeading
                    )
                }
                
                // Video Section
                if let videoURL = atom.videoURL, !videoURL.isEmpty {
                    Section("Instructional Video") {
                        if let url = URL(string: videoURL) {
                            Link(destination: url) {
                                Label("Watch Video", systemImage: "play.circle.fill")
                            }
                        }
                    }
                }
                
                // Settings Section
                Section {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit Settings", systemImage: "gear")
                    }
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        stopTimer()
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onDisappear {
                stopTimer()
            }
            .sheet(item: $setToEdit) { set in
                EditSetSheet(set: set, atom: atom, initialWeight: editWeight, initialReps: editReps)
            }
            .sheet(isPresented: $showingEditor) {
                AtomInstanceEditorView(atom: atom)
            }
            // Recalculate timer when returning from background
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    recalculateTimerDisplay()
                }
            }
        }
    }
    
    // MARK: - Timer Logic
    
    private var stateIndicatorText: String {
        switch timerState {
        case .ready:
            return "Ready to start"
        case .working:
            return "Set in progress..."
        case .resting:
            return "Rest period"
        }
    }
    
    private var actionButtonText: String {
        switch timerState {
        case .ready:
            return "Start Set"
        case .working:
            return "Finish Set"
        case .resting:
            let remaining = Int(remainingRestTime)
            return "End Rest (\(remaining)s)"
        }
    }
    
    private var actionButtonColor: Color {
        switch timerState {
        case .ready:
            return Color.accentColor
        case .working:
            return Color.green
        case .resting:
            return Color.orange
        }
    }
    
    private func handleTimerAction() {
        switch timerState {
        case .ready:
            startSet()
        case .working:
            finishSet()
        case .resting:
            endRest()
        }
    }
    
    private func startSet() {
        timerState = .working
        timerStartTime = Date()
        displayedTime = 0
        startTimer()
    }
    
    private func finishSet() {
        stopTimer()
        
        // Calculate duration
        let duration = timerStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        // Create the set
        let newSet = atom.addSet(
            weight: Double(currentWeight),
            reps: Int(currentReps)
        )
        newSet.duration = duration
        newSet.complete()
        
        // Progressive Overload: Update current value to max weight used
        if let weight = Double(currentWeight) {
            let maxWeight = max(atom.currentValue ?? 0, weight)
            atom.currentValue = maxWeight
        }
        
        // Update atom completion
        atom.updateCompletionFromSets()
        
        // Start rest timer
        timerState = .resting
        restStartTime = Date()
        displayedTime = restDuration
        startRestTimer()
        
        // Clear inputs for next set
        // Keep weight, clear reps (common pattern)
        currentReps = ""
        
        try? modelContext.save()
    }
    
    private func endRest() {
        stopTimer()
        
        // Check if all sets completed
        if atom.completedSetsCount >= (atom.targetSets ?? 0) {
            atom.markComplete()
            moleculeService.checkForProgression(atomInstance: atom)
            try? modelContext.save()
            dismiss()
        } else {
            // Ready for next set
            timerState = .ready
            displayedTime = 0
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let start = timerStartTime {
                displayedTime = Date().timeIntervalSince(start)
            }
        }
    }
    
    private func startRestTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let start = restStartTime {
                let elapsed = Date().timeIntervalSince(start)
                displayedTime = max(0, restDuration - elapsed)
                
                // Auto-advance when rest is done
                if displayedTime <= 0 {
                    endRest()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Recalculates timer display when returning from background
    private func recalculateTimerDisplay() {
        switch timerState {
        case .ready:
            break // Nothing to recalculate
        case .working:
            if let start = timerStartTime {
                displayedTime = Date().timeIntervalSince(start)
            }
        case .resting:
            if let start = restStartTime {
                let elapsed = Date().timeIntervalSince(start)
                displayedTime = max(0, restDuration - elapsed)
                if displayedTime <= 0 {
                    endRest()
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time - Double(Int(time))) * 10)
        
        if minutes > 0 {
            return String(format: "%d:%02d.%d", minutes, seconds, tenths)
        } else {
            return String(format: "%d.%d", seconds, tenths)
        }
    }
    
    private func deleteSets(at offsets: IndexSet) {
        let setsToDelete = offsets.map { atom.sortedSets[$0] }
        for set in setsToDelete {
            modelContext.delete(set)
        }
        atom.updateCompletionFromSets()
        try? modelContext.save()
    }
}

// MARK: - Edit Set Sheet

struct EditSetSheet: View {
    let set: WorkoutSet
    let atom: AtomInstance
    @State private var weight: String
    @State private var reps: String
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    init(set: WorkoutSet, atom: AtomInstance, initialWeight: String, initialReps: String) {
        self.set = set
        self.atom = atom
        _weight = State(initialValue: initialWeight)
        _reps = State(initialValue: initialReps)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Edit Set \(set.order)") {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("0", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(atom.unit ?? "lbs")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Reps")
                        Spacer()
                        TextField("0", text: $reps)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                }
            }
            .navigationTitle("Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        set.weight = Double(weight)
                        set.reps = Int(reps)
                        atom.updateCompletionFromSets()
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}

// MARK: - Atom Instance Editor

struct AtomInstanceEditorView: View {
    @Bindable var atom: AtomInstance
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var templates: [AtomTemplate]
    
    // UI State
    @State private var videoURL: String = ""
    @State private var targetSets: String = ""
    @State private var targetReps: String = ""
    @State private var restTime: String = ""
    
    // Logic State
    @State private var showingSaveDialog = false
    @State private var originalVideoURL: String?
    @State private var originalTargetSets: Int?
    @State private var originalTargetReps: Int?
    @State private var originalRestTime: TimeInterval?
    
    private var sourceTemplate: AtomTemplate? {
        guard let sourceId = atom.sourceTemplateId else { return nil }
        return templates.first { $0.id == sourceId }
    }
    
    private var hasStructuralChanges: Bool {
        let videoChanged = videoURL != (originalVideoURL ?? "")
        
        var targetChanged = false
        if atom.isWorkoutExercise {
            targetChanged = (Int(targetSets) != originalTargetSets) ||
                            (Int(targetReps) != originalTargetReps) ||
                            (Double(restTime) != originalRestTime)
        }
        
        return videoChanged || targetChanged
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Instructional Video
                Section("Instructional Video") {
                    TextField("https://youtube.com/...", text: $videoURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                // Workout Targets (if applicable)
                if atom.isWorkoutExercise {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Sets", text: $targetSets)
                                    .keyboardType(.numberPad)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Reps", text: $targetReps)
                                    .keyboardType(.numberPad)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rest (s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Sec", text: $restTime)
                                    .keyboardType(.numberPad)
                            }
                        }
                    } header: {
                        Text("Workout Targets")
                    } footer: {
                        Text("Modifying targets will affect progress calculation.")
                    }
                }
                
                // Info Section
                if sourceTemplate != nil {
                    Section {
                        Text("This task is part of a recurring series.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        handleSaveAttempt()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadValues)
            .confirmationDialog(
                "Update Series?",
                isPresented: $showingSaveDialog,
                titleVisibility: .visible
            ) {
                Button("Update This Session Only") {
                    saveSessionOnly()
                }
                
                Button("Update All Future Sessions") {
                    saveAllFuture()
                }
                
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You've changed the structure of this task. Do you want to apply these changes to the template for future sessions?")
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Logic
    
    private func loadValues() {
        // Current values
        videoURL = atom.videoURL ?? ""
        if let sets = atom.targetSets { targetSets = String(sets) }
        if let reps = atom.targetReps { targetReps = String(reps) }
        if let rest = atom.defaultRestTime { restTime = String(Int(rest)) }
        
        // Save original values for change detection
        originalVideoURL = atom.videoURL
        originalTargetSets = atom.targetSets
        originalTargetReps = atom.targetReps
        originalRestTime = atom.defaultRestTime
    }
    
    private func handleSaveAttempt() {
        if hasStructuralChanges && sourceTemplate != nil {
            showingSaveDialog = true
        } else {
            // No template or no structural changes -> just update instance
            saveSessionOnly()
        }
    }
    
    private func saveSessionOnly() {
        updateInstance(atom)
        saveContext()
    }
    
    private func saveAllFuture() {
        updateInstance(atom)
        
        if let template = sourceTemplate {
            // Update Template
            template.videoURL = videoURL.isEmpty ? nil : videoURL
            
            if atom.isWorkoutExercise {
                template.targetSets = Int(targetSets)
                template.targetReps = Int(targetReps)
                template.defaultRestTime = Double(restTime)
            }
        }
        
        saveContext()
    }
    
    private func updateInstance(_ instance: AtomInstance) {
        instance.videoURL = videoURL.isEmpty ? nil : videoURL
        
        if instance.isWorkoutExercise {
            instance.targetSets = Int(targetSets)
            instance.targetReps = Int(targetReps)
            instance.defaultRestTime = Double(restTime)
        }
    }
    
    private func saveContext() {
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    Text("Atom Detail Sheet Preview")
        .font(.headline)
}
